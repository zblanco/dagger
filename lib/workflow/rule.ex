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

  defstruct name: nil,
            description: nil,
            condition: nil,
            reaction: nil,
            expression: []

  @typedoc """
  A rule.
  """
  @type t() :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          condition: any(),
          reaction: any(),
          expression: [{lhs(), rhs()}]
        }

  @typedoc """
  A list of clauses or branches of the rule where each item is a tuple containing the lhs, rhs
  of the function/rule.
  """
  @type expression() :: [{lhs(), rhs()}]

  @typedoc """
  The left hand side of a clause correlating with the pattern or condition of a function.
  """
  @type lhs() :: any()

  @typedoc """
  The right hand side of a clause correlating with the block or reaction of a function.
  """
  @type rhs() :: any()

  # def new(fun) when is_function(fun, 0) do
  #   Rule.new(condition: fn _ -> true end, reaction: fun)
  # end

  # def new(fun) when is_function(fun, 1) do
  #   Rule.new(condition: fn _ -> true end, reaction: fun)
  # end

  # def new(params) do
  #   struct(__MODULE__, params)
  #   |> prepare_lhs()
  #   |> prepare_rhs()
  # end

  # def check(%__MODULE__{} = rule, input) do
  #   rule
  #   |> Runnable.to_workflow()
  #   |> IO.inspect(label: workflow)
  #   |> Workflow.next_runnables?(input)
  # end

  # def check(%__MODULE__{} = rule, input) do
  #   # left_hand_sides = Enum.map(rule.expression, &elem(&1, 0))
  #   # true_branches = for clause <- left_hand_sides, do: {:->, [], [[clause], true]}
  #   false_branch = {:->, [], [[{:_, [], Elixir}], false]}

  #   branches =
  #     [false_branch | Enum.map(rule.expression, &check_branch_of_expression/1)]
  #     |> Enum.reverse()

  #   check = {:fn, [], branches}

  #   IO.inspect(Macro.to_string(check), label: "check")
  #   {fun, _} = Code.eval_quoted(check)
  #   fun.(input)
  # end

  # defp check_branch_of_expression({lhs, _rhs}) when is_function(lhs) do
  #   wrapper =
  #     quote bind_quoted: [lhs: lhs] do
  #       fn input ->
  #         try do
  #           IO.inspect(apply(lhs, input), label: "application")
  #         rescue
  #           true -> true
  #           otherwise ->
  #             IO.inspect(otherwise, label: "otherwise")
  #             false
  #         end
  #       end
  #     end

  #   IO.inspect(Macro.to_string(wrapper), label: "wrapper")

  #   {:->, [], [[:_], wrapper]}
  # end

  # defp check_branch_of_expression({lhs, _rhs}), do: {:->, [], [[lhs], true]}

  # def run(%__MODULE__{} = rule, input) do
  #   action_branches =
  #     Enum.map(rule.expression, fn
  #       {lhs, rhs} when is_function(lhs) ->
  #         wrapper = quote(do: fn input -> apply(lhs, input) end)

  #         IO.inspect(Macro.to_string(wrapper), label: "wrapper")

  #         {:->, [], [[:_], rhs]}

  #       {lhs, rhs} ->
  #         {:->, [], [[lhs], rhs]}
  #     end)

  #   false_branch = {:->, [], [[{:_, [], Elixir}], false]}
  #   branches = [false_branch | action_branches] |> Enum.reverse()

  #   {fun, _} = Code.eval_quoted({:fn, [], branches})
  #   fun.(input)
  # end

  def check(%__MODULE__{} = rule, input) do
    Dagger.Flowable.to_workflow(rule)
    |> Workflow.plan(input)
    |> Workflow.is_runnable?()
  end

  def run(%__MODULE__{} = rule, input) do
    Dagger.Flowable.to_workflow(rule)
    |> Workflow.plan(input)
    |> Workflow.next_runnables()
    |> Enum.map(fn {step, fact} -> Dagger.Runnable.run(step, fact) end)
    |> List.first()
    |> Map.get(:value)
  end

  # defimpl Dagger.Runnable do
  #   alias Dagger.Workflow.{Step, Steps, Condition, Rule}
  #   alias Dagger.Workflow

  #   def run({%Rule{} = rule, input}) do
  #     Dagger.Flowable.to_workflow(rule)
  #     |> Workflow.plan(input)
  #     |> Workflow.run()
  #   end
  # end

  defimpl Dagger.Flowable do
    alias Dagger.Workflow.{Step, Steps, Condition, Rule}
    alias Dagger.Workflow

    def to_workflow(%Rule{expression: expression} = rule) do
      Enum.reduce(expression, Workflow.new(rule.name), fn

        {lhs, rhs}, wrk when is_function(lhs) ->
          condition = Condition.new(lhs)
          reaction = Step.new(work: work_of_rhs(lhs, rhs))

          rule_wrk =
            Workflow.new("#{condition.hash}-#{reaction.hash}")
            |> Workflow.with_rule(condition, reaction)

          Workflow.merge(wrk, rule_wrk)

        {true = lhs, rhs}, wrk ->
          condition = Condition.new(&Steps.always_true/1)
          reaction = Step.new(work: work_of_rhs(lhs, rhs))

          rule_wrk =
            Workflow.new("#{condition.hash}-#{reaction.hash}")
            |> Workflow.with_rule(condition, reaction)

          Workflow.merge(wrk, rule_wrk)

        {[] = _lhs, rhs}, wrk ->
          condi = work_of_lhs([{:_anything, [], nil}])
          IO.inspect(Macro.to_string(condi), label: "condition built")
          condition =
            condi
            |> Condition.new()
            |> IO.inspect(label: "condition")

          reaction = Step.new(work: work_of_rhs([{:_anything, [], nil}], rhs))

          rule_wrk =
            Workflow.new("#{condition.hash}-#{reaction.hash}")
            |> Workflow.with_rule(condition, reaction)

          Workflow.merge(wrk, rule_wrk)

        {lhs, rhs}, wrk ->
          IO.inspect(lhs, label: "lhs")

          condi = work_of_lhs(lhs) |> IO.inspect(label: "condi")

          IO.inspect(Macro.to_string(condi), label: "condition built")

          # {cond_funq, _} = Code.eval_quoted(condi)

          condition =
            condi
            |> Condition.new()
            |> IO.inspect(label: "condition")

          reaction = Step.new(work: work_of_rhs(lhs, rhs))

          rule_wrk =
            Workflow.new("#{condition.hash}-#{reaction.hash}")
            |> Workflow.with_rule(condition, reaction)

          Workflow.merge(wrk, rule_wrk)
      end)
    end

    defp work_of_lhs({lhs, _meta, nil}) do
      work_of_lhs(lhs)
    end

    defp work_of_lhs(lhs) do
      false_branch = {:->, [], [[{:_, [], Elixir}], false]}

      branches =
        [false_branch | Enum.map(lhs, &check_branch_of_expression/1)]
        |> Enum.reverse()

      check = {:fn, [], branches}

      IO.inspect(Macro.to_string(check), label: "check")
      {fun, _} = Code.eval_quoted(check)
      fun
    end

    defp work_of_rhs(lhs, [rhs | _]) do
      work_of_rhs(lhs, rhs)
    end

    defp work_of_rhs(lhs, rhs) when is_function(lhs) do
      IO.inspect(rhs, label: "workofrhs")
      rhs = {:fn, [], [
        {:->, [], [[{:_, [], Elixir}], rhs]}
      ]}

      IO.inspect(Macro.to_string(rhs), label: "rhs as string")
      {fun, _} = Code.eval_quoted(rhs)
      fun
    end

    defp work_of_rhs(lhs, rhs) do
      IO.inspect(rhs, label: "workofrhs")
      rhs = {:fn, [], [
        {:->, [], [lhs, rhs]}
      ]}

      IO.inspect(Macro.to_string(rhs), label: "rhs as string")
      {fun, _} = Code.eval_quoted(rhs)
      fun
    end

    # defp check_branch_of_expression(lhs) when is_function(lhs) do
    #   # quote bind_quoted: [lhs: lhs] do
    #   #   fn lhs
    #   # end

    #   wrapper =
    #     quote bind_quoted: [lhs: lhs] do
    #       fn input ->
    #         try do
    #           IO.inspect(apply(lhs, input), label: "application")
    #         rescue
    #           true -> true
    #           otherwise ->
    #             IO.inspect(otherwise, label: "otherwise")
    #             false
    #         end
    #       end
    #     end

    #   IO.inspect(Macro.to_string(wrapper), label: "wrapper")

    #   {:->, [], [[:_], wrapper]}
    # end

    defp check_branch_of_expression(lhs), do: {:->, [], [[lhs], true]}
  end
end
