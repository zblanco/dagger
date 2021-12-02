defmodule Dagger.Workflow.Rule do
  @moduledoc """
  A Dagger Rule is a user-facing component to a workflow that is evaluated as a set of conditions that if true prepare a reaction.

  A rule is a the pair of a condition (otherwise known as the left hand side: LHS) and a reaction (right hand side: RHS)

  Like how a function in Elixir/Erlang has a head with a pattern for parameters and a body (the reaction) a rule is similar except
    these components are separate and modeled as data we can compose at runtime rather than compile time.

  A rule added to a workflow is a way to compose many patterns/conditionals that can be evaluated like
    a bunch of overloaded functions being matched against.

  Instead of a function we might make Condition a Runnable by following a protocol so abstractions of conditional logic
    can be extended upon more naturally. Ultimately Conditions and Reactions become steps, the protocol would just
    convert a more complex condition into many dependent steps in the case that reactions to specific clauses are added.

  Rules are useful constructs to have persisted and indexed for runtime addition to an existing workflow.
  """
  alias Dagger.Workflow
  alias Dagger.Workflow.Condition
  alias Dagger.Workflow.Step
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
          # condition: any(),
          # reaction: any(),
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

  def new(expression, opts \\ []) do
    name = Keyword.get(opts, :name) || Steps.name_of_expression(expression)
    description = Keyword.get(opts, :description)
    arity = Steps.arity_of(expression)
    workflow = workflow_of_expression(expression, arity)

    %__MODULE__{
      name: name,
      description: description,
      arity: arity,
      expression: expression,
      workflow: workflow
    }
  end

  @doc """
  Checks a rule's left hand side .
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
    |> Workflow.next_runnables()
    |> Enum.map(fn {step, fact} -> Dagger.Runnable.run(step, fact) end)
    |> List.first()
    |> case do
      nil -> {:error, :no_conditions_satisfied}
      %{value: value} -> value
    end
  end

  defp workflow_of_expression({:fn, _, [{:->, _, [[], rhs]}]} = expression, 0 = arity) do
    reaction = reaction_step_of_rhs(expression, arity)

    Steps.name_of_expression(rhs)
    |> Workflow.new()
    |> Workflow.add_step(reaction)
  end

  defp workflow_of_expression({lhs, rhs}, arity) when lhs in [true, nil] do
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
         arity
       ) do
    condition = Condition.new(Steps.work_of_lhs(captured_function_lhs), arity)

    reaction = reaction_step_of_rhs({captured_function_lhs, rhs}, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> Workflow.with_rule(condition, reaction)
  end

  defp workflow_of_expression(
         {{:fn, _, [{:->, _, [[{term, _meta, _context}], true]}]}, rhs},
         arity
       )
       when is_atom(term) do
    if term |> to_string() |> String.first() == "_" do
      workflow_of_expression({nil, rhs}, arity)
    end
  end

  defp workflow_of_expression(
         {{:fn, _, [{:->, _, [[{_term, _meta, _context}], true]}]} = lhs, rhs} = expression,
         arity
       ) do
    condition = Condition.new(Steps.work_of_lhs(lhs), arity)

    reaction = reaction_step_of_rhs(rhs, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> Workflow.with_rule(condition, reaction)
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
         arity
       ) do
    {lhs, rhs} =
      expression = Steps.expression_of(captured_function) |> IO.inspect(label: "expression_of")

    conditions =
      Enum.map(lhs, fn condition ->
        Condition.new(Steps.work_of_lhs(condition), arity)
      end)

    reaction = reaction_step_of_rhs(rhs, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> Workflow.with_rule(conditions, reaction)
  end

  defp workflow_of_expression({[_first | _rest] = lhs_conditions, _rhs} = expression, arity) do
    conditions =
      Enum.map(lhs_conditions, fn condition ->
        Condition.new(Steps.work_of_lhs(condition), arity)
      end)

    reaction = reaction_step_of_rhs(expression, arity)

    expression
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> Workflow.with_rule(conditions, reaction)
  end

  defp workflow_of_expression(
         {:fn, _meta, [{:->, _, [[lhs], _rhs]}]} = quoted_fun_expression,
         arity
       ) do
    conditions =
      lhs
      |> match_functions_of_lhs()
      |> Enum.map(&Condition.new(&1, arity))

    reaction = reaction_step_of_rhs(quoted_fun_expression, arity)

    quoted_fun_expression
    |> Steps.fact_hash()
    |> to_string()
    |> Workflow.new()
    |> Workflow.with_rule(conditions, reaction)
  end

  defp workflow_of_expression({:fn, _meta, [_first_clause | _remaining_clauses]}, _arity) do
    throw("A rule can have only one clause")
    # {:error, "A rule can have only one clause"}
  end

  defp reaction_step_of_rhs(
         {:fn, _meta, [{:->, _, [_lhs, _rhs]}]} = quoted_fun_expression,
         _arity
       ) do
    IO.inspect(Macro.to_string(quoted_fun_expression), label: "quoted_fun_expression rhs")
    {fun, _} = Code.eval_quoted(quoted_fun_expression)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({_lhs, rhs}, _arity) when is_function(rhs), do: Step.new(work: rhs)

  defp reaction_step_of_rhs({_lhs, rhs}, 0) do
    quoted_rhs = {:fn, [], [{:->, [], [[{:_, [], Elixir}], rhs]}]}

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for 0 arity rewrite")
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

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for arity 1 rewrite")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({nil, {:fn, _, [{:->, _, [_lhs_of_rhs, _]}]} = rhs} = expression, 1) do
    IO.inspect(expression, label: "expression")

    IO.inspect(Macro.to_string(rhs), label: "rhs as string for arity 1 rewrite")
    {fun, _} = Code.eval_quoted(rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({nil, rhs} = expression, 1) do
    IO.inspect(expression, label: "expression")
    quoted_rhs = {:fn, [], [{:->, [], [[{:_any, [], nil}], rhs]}]}

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for arity 1 rewrite")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs(
         {[] = _lhs_conditions, {:fn, _, [{:->, _, [_lhs_of_rhs, _]}]} = rhs},
         1
       ) do
    IO.inspect(Macro.to_string(rhs), label: "rhs as string for arity 1 rewrite")
    {fun, _} = Code.eval_quoted(rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({lhs_conditions, rhs} = expression, 1) when is_list(lhs_conditions) do
    IO.inspect(expression, label: "expression for list of conditions")
    quoted_rhs = {:fn, [], [{:->, [], [[{:_any, [], nil}], rhs]}]}

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for arity 1 rewrite")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({{:&, _, [{:/, _, _}]} = _captured_fun, rhs} = expression, 1) do
    IO.inspect(expression, label: "expression")
    quoted_rhs = {:fn, [], [{:->, [], [[{:_, [], Elixir}], rhs]}]}

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for arity 1 rewrite!")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({lhs, rhs} = expression, 1) do
    IO.inspect(expression, label: "expression")
    quoted_rhs = {:fn, [], [{:->, [], [[lhs], rhs]}]}

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for arity 1 rewrite!")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs({_lhs, rhs}, arity) do
    quoted_rhs =
      {:fn, [], [{:->, [], [[Enum.map(1..arity, fn _arg_pos -> {:_, [], Elixir} end)], rhs]}]}

    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for n arity rewrite")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp reaction_step_of_rhs(some_term, _arity) do
    quoted_rhs = {:fn, [], [{:->, [], [[], some_term]}]}
    IO.inspect(Macro.to_string(quoted_rhs), label: "rhs as string for arbitrary term")
    {fun, _} = Code.eval_quoted(quoted_rhs)
    Step.new(work: fun)
  end

  defp match_functions_of_lhs({:when, _, _guard_expressions} = when_ast) do
    IO.inspect(when_ast, label: "when_ast")

    Macro.prewalk(when_ast, %{match_functions: [], binds: []}, fn
      {:not, _meta, _} = negation, %{binds: binds, match_functions: match_funs} = acc ->
        match_fun =
          {:fn, [],
           [
             {:->, [],
              [
                [
                  {:when, [],
                   [
                     binds,
                     negation
                   ]}
                ],
                true
              ]}
           ]}
          |> Code.eval_quoted()
          |> elem(0)

        {negation, %{acc | match_functions: [match_fun | match_funs]}}

      {:and, _meta, _and_clauses} = conjunction, %{} = acc ->
        # todo: extract out condition(s)
        IO.inspect(conjunction, label: "conjunction in ast")
        {conjunction, acc}

      {_guard_name, _meta, [{_bind, _, Elixir}]} = guard_statement,
      %{binds: binds, match_functions: match_funs} = acc ->
        match_fun =
          {:fn, [],
           [
             {:->, [],
              [
                [
                  {:when, [], [binds, guard_statement]}
                ],
                true
              ]},
             {:->, [],
              [
                [
                  Enum.map(binds, fn {bind, _meta, Elixir} -> {:"_#{bind}", [], Elixir} end)
                ],
                true
              ]}
           ]}
          |> Code.eval_quoted()
          |> elem(0)

        {guard_statement, %{acc | match_functions: [match_fun | match_funs]}}

      {bind_var, _meta, Elixir} = bind, %{binds: binds} = acc when is_atom(bind_var) ->
        {bind, %{acc | binds: [bind | binds]}}
    end)

    # guard_expressions
    # |> Enum.reduce(%{match_functions: [], binds: []}, fn
    #   {:not, _meta, _} = negation, %{binds: binds, match_functions: match_funs} = acc ->
    #     match_fun =
    #       {:fn, [],
    #        [
    #          {:->, [],
    #           [
    #             [
    #               {:when, [],
    #                [
    #                  binds,
    #                  negation
    #                ]}
    #             ],
    #             true
    #           ]}
    #        ]}
    #       |> Code.eval_quoted()
    #       |> elem(0)

    #     %{acc | match_functions: [match_fun | match_funs]}

    #   {:and, _meta, _and_clauses} = conjunction, %{} = acc ->
    #     # todo: extract out condition(s)
    #     IO.inspect(conjunction, label: "conjunction in ast")
    #     acc

    #   {_guard_name, _meta, [{_bind, _, Elixir}]} = guard_statement,
    #   %{binds: binds, match_functions: match_funs} = acc ->
    #     match_fun =
    #       {:fn, [],
    #        [
    #          {:->, [],
    #           [
    #             [
    #               {:when, [], [binds, guard_statement]}
    #             ],
    #             true
    #           ]},
    #          {:->, [],
    #           [
    #             [
    #               Enum.map(binds, fn {bind, _meta, Elixir} -> {:"_#{bind}", [], Elixir} end)
    #             ],
    #             true
    #           ]}
    #        ]}
    #       |> Code.eval_quoted()
    #       |> elem(0)

    #     %{acc | match_functions: [match_fun | match_funs]}

    #   {_bind, _meta, _Elixir} = bind, %{binds: binds} = acc ->
    #     %{acc | binds: [bind | binds]}
    # end)
    |> elem(1)
    |> Map.get(:match_functions)
  end

  defp match_functions_of_lhs(term_otherwise) do
    [{:fn, [], [{:->, [], [[term_otherwise], true]}]} |> Code.eval_quoted() |> elem(0)]
  end



  # defimpl Dagger.Flowable do
  #   alias Dagger.Workflow.{Step, Steps, Condition, Rule}
  #   alias Dagger.Workflow

  #   def to_workflow(%Rule{expression: expression, arity: arity} = rule) do
  #     IO.inspect(expression, label: "expression")

  #     Enum.reduce(expression, Workflow.new(rule.name), fn
  #       {lhs, rhs}, wrk when is_function(lhs) ->
  #         condition = Condition.new(lhs, arity)
  #         reaction = Step.new(work: work_of_rhs(lhs, rhs))

  #         rule_wrk =
  #           Workflow.new("#{condition.hash}-#{reaction.hash}")
  #           |> Workflow.with_rule(condition, reaction)

  #         Workflow.merge(wrk, rule_wrk)

  #       {true = lhs, rhs}, wrk ->
  #         condition = Condition.new(&Steps.always_true/1, arity)
  #         reaction = Step.new(work: work_of_rhs(lhs, rhs))

  #         rule_wrk =
  #           Workflow.new("#{condition.hash}-#{reaction.hash}")
  #           |> Workflow.with_rule(condition, reaction)

  #         Workflow.merge(wrk, rule_wrk)

  #       {[] = lhs, rhs}, wrk ->
  #         IO.inspect(lhs, label: "lhs")
  #         condi = work_of_lhs([{:_anything, [], nil}])
  #         IO.inspect(Macro.to_string(condi), label: "condition built")

  #         condition =
  #           condi
  #           |> Condition.new(arity)
  #           |> IO.inspect(label: "condition")

  #         reaction = Step.new(work: work_of_rhs([{:_anything, [], nil}], rhs))

  #         rule_wrk =
  #           Workflow.new("#{condition.hash}-#{reaction.hash}")
  #           |> Workflow.with_rule(condition, reaction)

  #         Workflow.merge(wrk, rule_wrk)

  #       {lhs, rhs}, wrk ->
  #         IO.inspect(lhs, label: "lhs")

  #         condi = work_of_lhs(lhs) |> IO.inspect(label: "condi")

  #         IO.inspect(Macro.to_string(condi), label: "condition built")

  #         # {cond_funq, _} = Code.eval_quoted(condi)

  #         condition =
  #           condi
  #           |> Condition.new(arity)
  #           |> IO.inspect(label: "condition")

  #         reaction = Step.new(work: work_of_rhs(lhs, rhs))

  #         rule_wrk =
  #           Workflow.new("#{condition.hash}-#{reaction.hash}")
  #           |> Workflow.with_rule(condition, reaction)

  #         Workflow.merge(wrk, rule_wrk)
  #     end)
  #   end

  #   defp work_of_lhs({lhs, _meta, nil}) do
  #     work_of_lhs(lhs)
  #   end

  #   defp work_of_lhs(lhs) do
  #     false_branch = false_branch_for_lhs(lhs)
  #     # false_branch = {:->, [], [[{:_, [], Elixir}], false]}

  #     branches =
  #       [false_branch | [check_branch_of_expression(lhs)]]
  #       |> Enum.reverse()

  #     check = {:fn, [], branches}

  #     IO.inspect(Macro.to_string(check), label: "check")
  #     {fun, _} = Code.eval_quoted(check)
  #     fun
  #   end

  #   defp work_of_rhs(lhs, [rhs | _]) do
  #     work_of_rhs(lhs, rhs)
  #   end

  #   defp work_of_rhs(lhs, rhs) when is_function(lhs) do
  #     IO.inspect(rhs, label: "workofrhs")

  #     rhs =
  #       {:fn, [],
  #        [
  #          {:->, [], [[{:_, [], Elixir}], rhs]}
  #        ]}

  #     IO.inspect(Macro.to_string(rhs), label: "rhs as string")
  #     {fun, _} = Code.eval_quoted(rhs)
  #     fun
  #   end

  #   defp work_of_rhs(lhs, rhs) do
  #     IO.inspect(rhs, label: "workofrhs")

  #     rhs =
  #       {:fn, [],
  #        [
  #          {:->, [], [lhs, rhs]}
  #        ]}

  #     IO.inspect(Macro.to_string(rhs), label: "rhs as string")
  #     {fun, _} = Code.eval_quoted(rhs)
  #     fun
  #   end

  #   defp false_branch_for_lhs([{:when, _meta, args} | _]) do
  #     arg_false_branches =
  #       args
  #       |> Enum.reject(&(not match?({_arg_name, _meta, nil}, &1)))
  #       |> Enum.map(fn _ -> {:_, [], Elixir} end)

  #     {:->, [], [arg_false_branches, false]}
  #   end

  #   defp false_branch_for_lhs(lhs) when is_list(lhs) do
  #     # we may need to do an ast traversal here
  #     {:->, [], [Enum.map(lhs, fn _ -> {:_, [], Elixir} end), false]}
  #   end

  #   # defp check_branch_of_expression(lhs) when is_function(lhs) do
  #   #   # quote bind_quoted: [lhs: lhs] do
  #   #   #   fn lhs
  #   #   # end

  #   #   wrapper =
  #   #     quote bind_quoted: [lhs: lhs] do
  #   #       fn input ->
  #   #         try do
  #   #           IO.inspect(apply(lhs, input), label: "application")
  #   #         rescue
  #   #           true -> true
  #   #           otherwise ->
  #   #             IO.inspect(otherwise, label: "otherwise")
  #   #             false
  #   #         end
  #   #       end
  #   #     end

  #   #   IO.inspect(Macro.to_string(wrapper), label: "wrapper")

  #   #   {:->, [], [[:_], wrapper]}
  #   # end

  #   defp check_branch_of_expression(lhs) when is_list(lhs) do
  #     IO.inspect(lhs, label: "lhx in check_branch_of_expression/1")
  #     {:->, [], [lhs, true]}
  #   end

  #   # defp check_branch_of_expression(lhs), do: {:->, [], [[lhs], true]}
  # end
end
