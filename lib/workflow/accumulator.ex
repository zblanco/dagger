defmodule Dagger.Workflow.Accumulator do
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
  step_work :: fn any() -> %Fact{}

  condition :: func -> bool | boolean_clause

  init: Rule :: { Condition(any), Reaction(Step(fn _ -> Fact{type: :state_produced}))}

  reducer: Rule :: %{
    condition: AND(Fact{type: :state_produced}, Condition(any)),
    reaction: fn Fact{value: any()} -> Fact{type: :state_produced, value: any())
  }

  ```
  """
  alias Dagger.Workflow.Rule

  defstruct [
    # rule where the condition consumes a fact that isn't a `state_produced` of this accumulator and returns the initial `state_produced` fact.
    :init,
    # rules where the condition matches on an external fact and a state_produced fact of this accumulator.
    :reducers
  ]

  def new(opts) do
    __MODULE__
    |> struct!(opts)

    # |> normalize()
  end

  def new(%Rule{} = init, [] = reducers) do
    # todo: ensure rule reactions always return a `state_produced` event/fact representing the accumulator definition.
    %__MODULE__{init: init, reducers: reducers}
  end

  def add_reducer(
        %__MODULE__{reducers: [] = reducers} = accumulator,
        %Rule{} = state_reactor
      ) do
    # todo: validate state_reactors meet contract of an AND
    %__MODULE__{accumulator | reducers: [reducers | [state_reactor]]}
  end
end
