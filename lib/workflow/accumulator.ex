defmodule Dagger.Workflow.Accumulator do
  @moduledoc """
  An accumulator is a series of reducers consuming facts of a workflow graph that reacts by producing state change events as facts.

  At least one step in an accumulation initiates it by consuming a fact from another step

  It's essentially a set of rules that serialize against external facts and its own `state-changed` events.

  So for any rule to be an accumulator it has to only react with `state-changed` events. Any other kind of reaction
    is against its contract.

  An accumulator is used in workflows where you want to collect many facts in a unified state in order to make a decision.

  The decisions made as a result of an Accumulator's `state-changed` events aren't actually part of an accumulator's set of `Steps`.

  Reactions are made with rules that react with state-changed facts of an Accumulator.

  For example in DDD terms both Aggregates and Process Managers are combinations of an accumulator with rules for when to react with events or commands.

  So we could say an Aggregate | Process Manager = Accumulator + Rules.

  Where the Accumulator doesn't have to know about the rules reacting without state-changed events.

  This separation of accumulation from further rule reactions allows for more runtime flexibility and optimizations of process topologies.
  ```
  step_work :: fn any() -> %Fact{}

  condition :: func -> bool | boolean_clause

  init: Rule :: { Condition(any), Reaction(Step(fn _ -> Fact{type: :state_changed}))}

  state_reactions: Rule :: %{
    condition: AND(Fact{type: :state_changed}, Condition(any)),
    reaction: fn Fact{value: any()} -> Fact{type: :state_changed, value: any())
  }

  ```
  """
  alias Dagger.Workflow.Rule

  defstruct [
    :initializer, # rule where the condition consumes a fact that isn't a `state_changed` of this accumulator
    :state_reactors, # rules where the condition matches on an external fact and a state_changed fact of this accumulator.
  ]

  @doc """
  Initialize a new Accumulator with just an Initializer Rule.

  This results in only a single `state_changed` reaction which means you'll want to use `add_accumulator_rule/2` or use `new/2` to do anything interesting.

  Initializer rules of an accumulator must have a condition reacting to an external fact.
  In addition the initializer reactions must always return a `state_changed` fact.

  """
  def new(%Rule{} = initializer) do

  end

  def new(initializer, state_reactors) do
    # ensure rule reactions always return a `state-changed` event/fact representing the accumulator definition.
  end

  def add_accumulator_rule() do

  end
end
