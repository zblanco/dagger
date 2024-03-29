defmodule Dagger.Workflow.Rule do
  @moduledoc """
  A Dagger Rule is a user-facing component to a workflow that is evaluated as a set of conditions that if true prepare a reaction.

  A rule is a the pair of a condition (otherwise known as the left hand side: LHS) and a reaction (right hand side: RHS)

  Like how a function in Elixir/Erlang has a head with a pattern for parameters and a body (the reaction) a rule is similar except
    these components are separate and modeled as data we can compose at runtime rather than compile time.

  A rule added to a workflow is a way to compose many patterns/conditionals that can be evaluated like
    a bunch of overloaded functions being matched against.

  Rules are useful for things like Rule based expert systems where one may query for pertinent rules from a database and build a workflow of them at runtime.
  """
  alias Dagger.Workflow
  alias Dagger.Workflow.Condition
  alias Dagger.Workflow.Step
  alias Dagger.Workflow.Conjunction
  alias Dagger.Workflow.Steps

  defstruct name: nil,
            description: nil,
            arity: nil,
            expression: [],
            workflow: nil

  @typedoc """
  A rule.
  """
  @type t() :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          arity: arity(),
          workflow: Workflow.t(),
          expression: expression()
        }

  @typedoc """
  A list of clauses or branches of the rule where each item is a tuple containing the lhs, rhs
  of the function/rule.
  """
  @type expression() :: [{lhs(), rhs()}] | any()

  @typedoc """
  The left hand side of a clause correlating with the pattern or condition of a function.
  """
  @type lhs() :: any()

  @typedoc """
  The right hand side of a clause correlating with the block or reaction of a function.
  """
  @type rhs() :: any()

  @boolean_expressions ~w(
    ==
    ===
    !=
    !==
    <
    >
    <=
    >=
    in
    not
    =~
  )a

  @doc """
  Constructs a rule struct given an expression and options. Expects the expression to be a tuple of a left a right hand side.
  """
  def new(expression, opts \\ []) do
    name = Keyword.get(opts, :name) || Steps.name_of_expression(expression)
    description = Keyword.get(opts, :description)
    context = Keyword.get(opts, :context)
    arity = Steps.arity_of(expression)
    workflow = workflow_of_expression(expression, arity, context)

    %__MODULE__{
      name: name,
      description: description,
      arity: arity,
      expression: expression,
      workflow: workflow
    }
  end

  @doc """
  Checks a rule's left hand side.
  """
  def check(%__MODULE__{} = rule, input) do
    rule
    |> Dagger.Flowable.to_workflow()
    |> Workflow.plan_eagerly(input)
    |> Workflow.is_runnable?()
  end

  @doc """
  Evaluates a rule, checking its left hand side, then evaluating the right.
  """
  def run(%__MODULE__{} = rule, input) do
    rule
    |> Dagger.Flowable.to_workflow()
    |> Workflow.plan_eagerly(input)
    |> Workflow.react()
    |> Workflow.raw_productions()
    |> List.first()
    |> case do
      nil -> {:error, :no_conditions_satisfied}
      result_otherwise -> result_otherwise
    end
  end

  defp workflow_of_expression({:fn, _, [{:->, _, [[], rhs]}]} = expression, 0 = arity, _context) do
    reaction = reaction_step_of_rhs(expression, arity)

    Steps.name_of_expression(rhs)
    |> Workflow.new()
    |> Workflow.add_step(reaction)
  end

  defp workflow_of_expression({lhs, rhs}, arity, _context) when lhs in [true, nil] do
    reaction = reaction_step_of_rhs({lhs, rhs}, arity)

    Steps.name_of_expression(rhs)
    |> Workflow.new()
    |> Workflow.add_step(reaction)
  end

  defp workflow_of_expression(
         {{:&, _capture_meta,
           [
             {:/, _arity_meta,
              [
                {{:., _dot_meta, [_, _function_name]}, _dot_opts, _dot_etc}
                | [_arity]
              ]}
           ]} = captured_function_lhs, rhs} = expression,
         arity,
         _context
       ) do
    condition = Condition.new(Steps.work_of_lhs(captured_function_lhs), arity)

    reaction = reaction_step_of_rhs({captured_function_lhs, rhs}, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> workflow_from_rule(condition, reaction)
  end

  defp workflow_of_expression(
         {{:fn, _, [{:->, _, [[{term, _meta, _context}], true]}]}, rhs},
         arity,
         context
       )
       when is_atom(term) do
    if term |> to_string() |> String.first() == "_" do
      workflow_of_expression({nil, rhs}, arity, context)
    end
  end

  defp workflow_of_expression(
         {{:fn, _, [{:->, _, [[{_term, _meta, _context}], true]}]} = lhs, rhs} = expression,
         arity,
         _context_env
       ) do
    condition = Condition.new(Steps.work_of_lhs(lhs), arity)

    reaction = reaction_step_of_rhs(rhs, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> workflow_from_rule(condition, reaction)
  end

  defp workflow_of_expression(
         {{:fn, _, _} = lhs, rhs} = expression,
         arity,
         _context_env
       ) do
    condition =
      Condition.new(
        lhs
        |> Code.eval_quoted()
        |> elem(0),
        arity
      )

    reaction = reaction_step_of_rhs(rhs, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> workflow_from_rule(condition, reaction)
  end

  defp workflow_of_expression(
         {:&, _capture_meta,
          [
            {:/, _arity_meta,
             [
               {{:., _dot_meta, [{:__aliases__, _aliasing_opts, _aliases}, _function_name]},
                _dot_opts, _dot_etc}
               | [_arity]
             ]}
          ]} = captured_function,
         arity,
         _context
       ) do
    {lhs, rhs} = expression = Steps.expression_of(captured_function)

    conditions =
      Enum.map(lhs, fn condition ->
        Condition.new(Steps.work_of_lhs(condition), arity)
      end)

    reaction = reaction_step_of_rhs(rhs, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> workflow_from_rule(conditions, reaction)
  end

  defp workflow_of_expression(
         {[_first | _rest] = lhs_conditions, _rhs} = expression,
         arity,
         _context
       ) do
    conditions =
      Enum.map(lhs_conditions, fn condition ->
        Condition.new(Steps.work_of_lhs(condition), arity)
      end)

    reaction = reaction_step_of_rhs(expression, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> workflow_from_rule(conditions, reaction)
  end

  defp workflow_of_expression(
         {:fn, _meta, [{:->, _, [[{:when, _, _} = lhs], _rhs]}]} = quoted_fun_expression,
         arity,
         context
       ) do
    arity_condition =
      arity
      |> Steps.is_of_arity?()
      |> Condition.new()

    new_workflow =
      quoted_fun_expression
      |> Steps.fact_hash()
      |> to_string()
      |> Workflow.new()

    workflow_with_arity_check = %Workflow{
      new_workflow
      | flow:
          new_workflow.flow
          |> Graph.add_vertex(arity_condition, [
            arity_condition.hash,
            "is_of_arity_#{arity}"
          ])
          |> Graph.add_edge(Workflow.root(), arity_condition, label: {:root, arity_condition.hash})
    }

    reaction = reaction_step_of_rhs(quoted_fun_expression, arity)

    lhs
    |> Macro.postwalker()
    |> Enum.reduce(
      %{
        workflow: workflow_with_arity_check,
        arity: arity,
        arity_condition: arity_condition,
        context: context,
        binds: binds_of_guarded_anonymous(quoted_fun_expression, arity),
        reaction: reaction,
        children: [],
        possible_children: %{},
        conditions: []
      },
      &post_extract_guarded_into_workflow/2
    )
    |> Map.get(:workflow)
  end

  defp workflow_of_expression(
         {:fn, _meta, [{:->, _, [[lhs], rhs]}]} = expression,
         arity,
         _context
       ) do
    lhs_match_fun_ast =
      {:fn, [],
       [
         {:->, [], [[lhs], true]},
         {:->, [], [[{:_otherwise, [if_undefined: :apply], Elixir}], false]}
       ]}

    match_fun =
      lhs_match_fun_ast
      |> Code.eval_quoted()
      |> elem(0)

    condition = Condition.new(match_fun, arity)

    reaction = reaction_step_of_rhs({lhs, rhs}, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> workflow_from_rule(condition, reaction)
  end

  defp workflow_of_expression(
         {:fn, _meta, [_first_clause | _remaining_clauses]},
         _arity,
         _context
       ) do
    throw("A rule can have only one clause")
    # {:error, "A rule can have only one clause"}
  end

  defp workflow_from_rule(
         %Workflow{flow: flow} = workflow,
         [%Condition{} = a_condition | _more_conditions] = conditions,
         %Step{} = reaction_step
       ) do
    unless Enum.count(conditions) == 1 do
      arity_check = Steps.is_of_arity?(a_condition.arity)
      arity_condition = Condition.new(arity_check)

      conjunction = Conjunction.new(conditions)

      flow =
        flow
        |> Graph.add_vertex(arity_condition, [
          arity_condition.hash,
          "is_of_arity_#{a_condition.arity}"
        ])
        |> Graph.add_edge(Workflow.root(), arity_condition, label: {:root, arity_condition.hash})
        |> Graph.add_vertex(conjunction, [
          conjunction.hash,
          "conjunction : #{conditions |> Enum.map(& &1.hash) |> Enum.join(" AND ")}"
        ])

      # Add the conditions beneath the arity check
      # Connect the conditions to the conjunction
      flow =
        Enum.reduce(conditions, flow, fn condition, flow ->
          flow
          |> Graph.add_vertex(condition, [condition.hash, function_name(condition.work)])
          |> Graph.add_edge(arity_condition, condition,
            label: {"is_of_arity_#{condition.arity}", condition.hash}
          )
          |> Graph.add_edge(condition, conjunction, label: :and)
        end)

      # Finally add the reaction and connect it to the conjunction above
      flow =
        flow
        |> Graph.add_vertex(reaction_step, [
          reaction_step.hash,
          reaction_step.name,
          function_name(reaction_step.work)
        ])
        |> Graph.add_edge(conjunction, reaction_step)

      %Workflow{workflow | flow: flow}
    else
      workflow_from_rule(workflow, a_condition, reaction_step)
    end
  end

  defp workflow_from_rule(
         %Workflow{flow: flow} = workflow,
         %Condition{} = condition,
         %Step{} = reaction_step
       ) do
    arity_check = Steps.is_of_arity?(condition.arity)
    arity_condition = Condition.new(arity_check)

    %Workflow{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(arity_condition, [
            arity_condition.hash,
            "is_of_arity_#{condition.arity}"
          ])
          |> Graph.add_vertex(condition, [condition.hash, function_name(condition.work)])
          |> Graph.add_vertex(reaction_step, [
            reaction_step.hash,
            reaction_step.name,
            function_name(reaction_step.work)
          ])
          |> Graph.add_edge(Workflow.root(), arity_condition, label: {:root, arity_condition.hash})
          |> Graph.add_edge(arity_condition, condition,
            label: {"is_of_arity_#{condition.arity}", condition.hash}
          )
          |> Graph.add_edge(condition, reaction_step, label: {condition.hash, reaction_step.hash})
    }
  end

  defp binds_of_guarded_anonymous(
         {:fn, _meta, [{:->, _, [[lhs], _rhs]}]} = _quoted_fun_expression,
         arity
       ) do
    binds_of_guarded_anonymous(lhs, arity)
  end

  defp binds_of_guarded_anonymous({:when, _meta, guarded_expression}, arity) do
    Enum.take(guarded_expression, arity)
  end

  defp reaction_step_of_rhs(
         {:fn, _meta, [{:->, _, [_lhs, _rhs]}]} = quoted_fun_expression,
         _arity
       ) do
    {fun, _} = Code.eval_quoted(quoted_fun_expression)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({_lhs, rhs}, _arity) when is_function(rhs), do: Step.new(work: rhs)

  defp reaction_step_of_rhs({_lhs, rhs}, 0) do
    quoted_rhs = {:fn, [], [{:->, [], [[{:_, [], Elixir}], rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs(
         {
           {:fn, _meta, [{:->, _, [lhs, _rhs]}]},
           rhs
         },
         1
       ) do
    quoted_rhs = {:fn, [], [{:->, [], [lhs, rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({nil, {:fn, _, [{:->, _, [_lhs_of_rhs, _]}]} = rhs} = _expression, 1) do
    {fun, _} = Code.eval_quoted(rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({nil, rhs} = _expression, 1) do
    quoted_rhs = {:fn, [], [{:->, [], [[{:_any, [], nil}], rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs(
         {[] = _lhs_conditions, {:fn, _, [{:->, _, [_lhs_of_rhs, _]}]} = rhs},
         1
       ) do
    {fun, _} = Code.eval_quoted(rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({lhs_conditions, rhs} = _expression, 1)
       when is_list(lhs_conditions) do
    quoted_rhs = {:fn, [], [{:->, [], [[{:_any, [], nil}], rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({{:&, _, [{:/, _, _}]} = _captured_fun, rhs} = _expression, 1) do
    quoted_rhs = {:fn, [], [{:->, [], [[{:_, [], Elixir}], rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({lhs, rhs} = _expression, 1) do
    quoted_rhs = {:fn, [], [{:->, [], [[lhs], rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({_lhs, rhs}, arity) do
    quoted_rhs =
      {:fn, [], [{:->, [], [[Enum.map(1..arity, fn _arg_pos -> {:_, [], Elixir} end)], rhs]}]}

    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs(some_term, _arity) do
    quoted_rhs = {:fn, [], [{:->, [], [[], some_term]}]}
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp leaf_to_reaction_edges(g, arity_condition, reaction) do
    Graph.Reducers.Dfs.reduce(g, [], fn
      ^arity_condition, leaf_edges ->
        Graph.out_degree(g, arity_condition)
        {:next, leaf_edges}

      %Dagger.Workflow.Root{}, leaf_edges ->
        {:next, leaf_edges}

      v, leaf_edges ->
        Graph.out_degree(g, v)

        if Graph.out_degree(g, v) == 0 do
          {:next, [Graph.Edge.new(v, reaction, label: {v.hash, reaction.hash}) | leaf_edges]}
        else
          {:next, leaf_edges}
        end
    end)
  end

  defp post_extract_guarded_into_workflow(
         {:when, _meta, _guarded_expression},
         %{
           workflow: wrk,
           arity_condition: arity_condition,
           reaction: reaction,
           conditions: conditions
         } = wrapped_wrk
       ) do
    flow =
      Enum.reduce(conditions, wrk.flow, fn
        {lhs_of_or, rhs_of_or} = _or, g ->
          g
          |> Graph.add_vertex(lhs_of_or, to_string(lhs_of_or.hash))
          |> Graph.add_vertex(lhs_of_or, to_string(lhs_of_or.hash))
          |> Graph.add_edges([
            Graph.Edge.new(arity_condition, lhs_of_or,
              label: {arity_condition.hash, lhs_of_or.hash}
            ),
            Graph.Edge.new(arity_condition, rhs_of_or,
              label: {arity_condition.hash, rhs_of_or.hash}
            )
          ])

        condition, g ->
          g
          |> Graph.add_vertex(condition, to_string(condition.hash))
          |> Graph.add_edge(
            Graph.Edge.new(arity_condition, condition,
              label: {arity_condition.hash, condition.hash}
            )
          )
      end)

    wrk = %Workflow{
      wrk
      | flow:
          flow
          |> Graph.add_vertex(reaction, [
            reaction.hash,
            reaction.name,
            function_name(reaction.work)
          ])
          |> Graph.add_edges(leaf_to_reaction_edges(flow, arity_condition, reaction))
    }

    %{wrapped_wrk | workflow: wrk}
  end

  defp post_extract_guarded_into_workflow(
         {:or, _meta, [lhs_of_or | [rhs_of_or | _]]} = ast,
         %{
           possible_children: possible_children
         } = wrapped_wrk
       ) do
    lhs_child_cond = Map.fetch!(possible_children, lhs_of_or)
    rhs_child_cond = Map.fetch!(possible_children, rhs_of_or)

    wrapped_wrk
    |> Map.put(
      :possible_children,
      Map.put(possible_children, ast, {lhs_child_cond, rhs_child_cond})
    )
  end

  defp post_extract_guarded_into_workflow(
         {:and, _meta, [lhs_of_and | [rhs_of_and | _]]} = ast,
         %{workflow: wrk, possible_children: possible_children} = wrapped_wrk
       ) do
    lhs_child_cond = Map.fetch!(possible_children, lhs_of_and)
    rhs_child_cond = Map.fetch!(possible_children, rhs_of_and)

    conditions = [lhs_child_cond, rhs_child_cond]

    conjunction = Conjunction.new(conditions)

    wrapped_wrk
    |> Map.put(:workflow, %Workflow{
      wrk
      | flow:
          Enum.reduce(conditions, wrk.flow, fn
            {lhs_of_or, rhs_of_or} = _or, g ->
              g
              |> Graph.add_vertex(lhs_of_or, to_string(lhs_of_or.hash))
              |> Graph.add_vertex(lhs_of_or, to_string(lhs_of_or.hash))
              |> Graph.add_vertex(conjunction, [
                conjunction.hash,
                "conjunction : #{conditions |> Enum.map(& &1.hash) |> Enum.join(" AND ")}"
              ])
              |> Graph.add_edges([
                Graph.Edge.new(lhs_of_or, conjunction, label: {lhs_of_or.hash, conjunction.hash}),
                Graph.Edge.new(rhs_of_or, conjunction, label: {rhs_of_or.hash, conjunction.hash})
              ])

            condition, g ->
              g
              |> Graph.add_vertex(conjunction, [
                conjunction.hash,
                "conjunction : #{conditions |> Enum.map(& &1.hash) |> Enum.join(" AND ")}"
              ])
              |> Graph.add_vertex(condition, condition.hash)
              |> Graph.add_edge(condition, conjunction, label: {condition.hash, conjunction.hash})
          end)
    })
    |> Map.put(:possible_children, Map.put(possible_children, ast, conjunction))
  end

  defp post_extract_guarded_into_workflow(
         {expr, _meta, children} = expression,
         %{workflow: wrk, binds: binds, arity_condition: arity_condition, arity: arity} =
           wrapped_wrk
       )
       when is_atom(expr) and not is_nil(children) do
    if expr in @boolean_expressions or binary_part(to_string(expr), 0, 2) === "is" do
      match_fun_ast =
        {:fn, [],
         [
           {:->, [],
            [
              [
                {:when, [], binds ++ [expression]}
              ],
              true
            ]},
           {:->, [],
            [Enum.map(binds, fn {bind, _meta, cont} -> {:"_#{bind}", [], cont} end), false]}
         ]}

      match_fun =
        match_fun_ast
        |> Code.eval_quoted()
        |> elem(0)

      condition = Condition.new(match_fun, arity)

      wrapped_wrk
      |> Map.put(:wrk, Workflow.add_step(wrk, arity_condition, condition))
      |> Map.put(:conditions, [condition | wrapped_wrk.conditions])
      |> Map.put(
        :possible_children,
        Map.put(wrapped_wrk.possible_children, expression, condition)
      )
    else
      wrapped_wrk
    end
  end

  defp post_extract_guarded_into_workflow(
         _some_other_ast,
         acc
       ) do
    acc
  end

  defp function_name(fun), do: Function.info(fun, :name) |> elem(1)
end
