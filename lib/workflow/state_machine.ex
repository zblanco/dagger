defmodule Dagger.Workflow.StateMachine do
  @moduledoc """
  An accumulator is a series of reducers consuming facts of a workflow graph that reacts by producing state change events as facts.

  At least one step in an accumulation initiates the state by consuming a fact from another step

  An accumulator essentially a set of rules that serialize against external facts and its own `state_produced` events.

  The natural analog to an accumulator is a genserver where each callback returns the state for the next receive loop.

  So for any rule to be an accumulator it has to only react with `state_produced` events. Any other kind of reaction
    is against its contract.

  An accumulator is used in workflows where you want to collect many facts in a unified state in order to make a decision.

  The decisions made as a result of an Accumulator's `state_produced` events aren't actually part of an accumulator's set of `Steps`.

  Reactions are made with rules that react with state_produced facts of an Accumulator.

  For example in DDD terms both Aggregates and Process Managers are combinations of an accumulator with rules for when to react with events or commands.

  So we could say an Aggregate | Process Manager = Accumulator + Rules.

  Where the Accumulator doesn't have to know about the rules reacting without state_produced events.

  This separation of accumulation from further rule reactions allows for more runtime flexibility and optimizations of process topologies.
  ```

  init: literal | fun/0 | fun/1

  reducer: (input, acc) -> acc - like a reduce but iterates per fact fed to workflow
  reactors: a list of
  ```
  """

  # alias Dagger.Workflow.Rule
  alias Dagger.Workflow
  alias Dagger.Workflow.Steps
  alias Dagger.Workflow.Step
  alias Dagger.Workflow.Condition
  alias Dagger.Workflow.MemoryAssertion
  alias Dagger.Workflow.StateCondition
  # alias Dagger.Workflow.Fact
  alias Dagger.Workflow.Accumulator

  defstruct [
    :name,
    # literal or function to return first state to act on
    :init,
    :reducer,
    :reactors,
    :workflow
  ]

  # Build conditionals for each clause in the reducer
  # conjoin any conditional that could activate toward the accumulator
  # for every reactor build some kind of condition to check if the fact is from the accumulator's hash and the reactor's state matches its condition
  # use whichever left hand side
  def new(init, reducer, opts \\ []) do
    name = Keyword.get(opts, :name) || Steps.name_of_expression(reducer)
    reactors = Keyword.get(opts, :reactors)
    workflow = workflow_of_state_machine_ast(init, reducer, reactors)
    IO.inspect(reducer, label: "reducer")
    IO.inspect(init, label: "init")
    IO.inspect(opts, label: "opts")

    %__MODULE__{
      name: name,
      init: init,
      reducer: reducer,
      workflow: workflow
    }
  end

  defp workflow_of_state_machine_ast(init, reducer, reactors) do
    accumulator = accumulator_of(init, reducer)

    reducer
    |> Steps.name_of_expression()
    |> Workflow.new()
    |> merge_into_workflow(reducer, accumulator)
    |> add_reactors(reactors, accumulator)
  end

  defp merge_into_workflow(workflow, {:fn, _, clauses} = _reducer, accumulator) do
    Enum.reduce(
      clauses,
      workflow,
      fn
        {:->, _meta, [lhs, _rhs]} = _clause, wrk ->
          # we need to build a node here that grabs last known state of the accumulator to match against in conjunction with the input command
          # state condition: "is the input and state what I want for this clauses' rhs?"
          state_cond_quoted =
            {:fn, [],
             [
               {:->, [], [lhs, true]},
               # anything otherwise: false
               {:->, [], [[{:_, [], Elixir}, {:_, [], Elixir}], false]}
             ]}

          IO.inspect(Macro.to_string(state_cond_quoted), label: "state_cond as string")

          {state_cond_fun, _} = Code.eval_quoted(state_cond_quoted)

          state_cond = StateCondition.new(state_cond_fun, accumulator.hash)

          arity_check = Steps.is_of_arity?(1)
          arity_condition = Condition.new(arity_check)

          wrk
          |> Workflow.add_step(arity_condition)
          |> Workflow.add_step(arity_condition, state_cond)
          |> Workflow.add_step(state_cond, accumulator)
      end
    )
  end

  defp add_reactors(workflow, nil, _accumulator), do: workflow

  defp add_reactors(workflow, reactors, accumulator) do
    Enum.reduce(reactors, workflow, fn
      {:fn, _meta, [{:->, _, [lhs, _rhs]}]} = reactor, wrk ->
        memory_assertion_fn = fn memory ->
          last_known_state =
            memory
            |> Graph.out_edges(accumulator.hash)
            |> Enum.filter(
              &(&1.label == :state_produced and &1.v1.generation == workflow.generation - 1)
            )
            |> List.first(%{})
            |> Map.get(:v1)

          {check_fn, _} =
            Code.eval_quoted(
              {:fn, [],
               [
                 {:->, [], [lhs, true]},
                 {:->, [], [[{:_otherwise, [], Elixir}], false]}
               ]}
            )

          check_fn.(last_known_state)
        end

        memory_assertion = MemoryAssertion.new(memory_assertion_fn)

        {reactor_fn, _} = Code.eval_quoted(reactor)
        reaction = Step.new(work: reactor_fn)

        wrk
        |> Workflow.add_step(memory_assertion)
        |> Workflow.add_step(memory_assertion, reaction)
    end)
  end

  defp accumulator_of(init, reducer) do
    init_fun =
      if Macro.quoted_literal?(init) do
        fn ->
          Code.eval_quoted(init) |> elem(0)
        end
      else
        init
        |> Code.eval_quoted()
        |> elem(0)
      end

    Accumulator.new(reducer, init_fun)
  end
end
