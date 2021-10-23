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
  alias Dagger.Workflow.{Rule, Fact}

  defstruct [
    :name,
    # rule where the condition consumes a fact that isn't a `state_produced` of this accumulator and returns the initial `state_produced` fact.
    :init,
    # rules where the condition matches on an external fact and a state_produced fact of this accumulator.
    :reducers
  ]

  @doc """
  Initialize a new Accumulator with just an Initializer Rule.

  This results in only a single `state_produced` reaction which means you'll want to use `add_accumulator_rule/2` or use `new/2` to do anything interesting.

  Initializer rules of an accumulator must have a condition reacting to an external fact.
  In addition the initializer reactions must always return a `state_produced` fact.
  """
  def new(%Rule{} = init) do
    %__MODULE__{init: init}
  end

  def new(%Rule{} = init, [] = reducers) do
    # todo: ensure rule reactions always return a `state_produced` event/fact representing the accumulator definition.
    %__MODULE__{init: init, reducers: reducers}
  end

  def add_state_reactor_rule(
        %__MODULE__{reducers: [] = reducers} = accumulator,
        %Rule{} = state_reactor
      ) do
    # todo: validate state_reactors meet contract of an AND
    %__MODULE__{accumulator | reducers: [reducers | state_reactor]}
  end

  defimpl Dagger.Flowable do
    alias Dagger.Workflow.{Rule, Accumulator}
    alias Dagger.Workflow

    def to_workflow(%Accumulator{init: %Rule{} = init, reducers: reducers} = acc)
        when is_list(reducers) do
      Enum.reduce(
        reducers,
        Workflow.merge(Workflow.new(acc.name), Dagger.Flowable.to_workflow(init)),
        fn reducer, wrk ->
          Workflow.merge(wrk, Dagger.Flowable.to_workflow(reducer))
        end
      )
    end
  end
end
