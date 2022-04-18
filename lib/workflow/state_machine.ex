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
    wrk = Workflow.new(Steps.name_of_expression(reducer))

    accumulator = accumulator_of(init, reducer)

    wrk
    |> Workflow.add_step()
  end

  defp reducer_workflows({:fn, _, clauses} = _reducer, accumulator) do
    Enum.map(
      clauses,
      fn
        {:->, _meta, [[input_command_pattern, state_pattern | _rest] = _lhs, _rhs]} ->
          # we need to build a node here that grabs last known state of the accumulator to match against in conjunction with the input command
          cmd_match_ast =
            {:fn, [],
             [
               {:->, [], [[input_command_pattern], true]},
               {:->, [], [[{:_otherwise, [if_undefined: :apply], Elixir}], false]}
             ]}

          state_pattern_ast =
            {:fn, [],
             [
               {:->, [], [[state_pattern], true]},
               {:->, [], [[{:_otherwise, [if_undefined: :apply], Elixir}], false]}
             ]}
      end
    )
  end

  defp accumulator_of(init, reducer) do
    init_fun =
      if Macro.quoted_literal?(init) do
        fn -> init end
      else
        init
        |> Code.eval_quoted()
        |> elem(0)
      end

    Accumulator.new(reducer, init_fun)
  end

  # defp workflow_of_reducer(
  #        init,
  #        {:fn, [],
  #         [
  #           {:->, [],
  #            [
  #              [{_input_arg_bind, _, _} = input_arg, {_acc_bind, _, _} = acc_arg], rhs
  #            ]}
  #         ]}
  #      ) do
  #   StateReactor.new()
  # end

  # def new(init, reducers) when is_list(reducers) do
  #   new(init_of_accumulator(ast_init), Enum.map(reducers, &reducer_to_state_reactor/1))
  # end

  # def new(%Rule{} = init, [%Rule{} | _] = reducers) do
  #   # todo: ensure rule reactions always return a `state_produced` event/fact representing the accumulator definition.
  #   %__MODULE__{init: init, reducers: reducers}
  # end

  # defp reducers_to_state_reactor(reducer) do

  # end

  # def add_reducer(
  #       %__MODULE__{reducers: [] = reducers} = accumulator,
  #       %Rule{} = state_reactor
  #     ) do
  #   # todo: validate state_reactors meet contract of an AND
  #   %__MODULE__{accumulator | reducers: [reducers | [state_reactor]]}
  # end
end
