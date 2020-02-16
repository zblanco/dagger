defmodule Dagger.Workflow.Step do
  @moduledoc """
  An individual node in the workflow connected by parent-child dependencies.

  A step always has one parent. A step can have many children.

  Steps are connected in a workflow through dataflow dependencies meaning the parent's output is fed the dependent step.

  A step's `work` field is a function that always accepts facts and returns a fact.

  Any children are fed the parent's fact.

  A `:condition` type step always returns a boolean fact.

  A `:reaction` type step always returns either a fact, or a data structure that conforms to the Runnable protocol.

  An `:accumulation` type step always returns a fact of a `state_produced` type.

  The Runnable protocol allows irreversable side-effects to be protected with only-once execution by breaking up
    the execution into two parts.

  Step dependencies are modeled in a Workflow Graph as the tuple of the parent node's hash and the step's hash.

  i.e. `( hash(parent_step), hash(child_step) )`.

  Edges between vertices in the graph are the hash of this tuple.

  Logical constraints might be expressed as boolean expressions in parent steps.

  Error handling is just a reaction to a fact that matches a case that is expressed as the
  `work` function recognizing an error by returning another fact.

  A rule compiles to steps connected by AND | OR as conditions to facts that activate
    further step work functions for reactions.

  An accumulator compiles to steps that always end in a `state-changed` event.

  Some `work` functions are just command intents representing an imperative coordination with the outside world ('e.g. database record inserted').

  Adding a rule is just constraining how a set of steps are connected by validating their input-output contracts.

  Notes:

  Types of steps will eventually just be Data Structure that follow the runnable protocol.
  Instead of a :condition type we have a Condition data structure that knows how to convert itself into a step.
  """
  alias Dagger.Workflow.{Rule, Step, Fact}

  @type type() ::
    :reaction
    | :condition
    | :accumulation

  defstruct name: nil,
            work: nil,
            type: nil,
            hash: nil

  def new(params) do
    struct!(__MODULE__, params)
  end

  # FYI, these are protocol impls in disguise, todo: convert to formal structs that implement runnable protocol.
  def of_condition(%Rule{} = rule) do
    %__MODULE__{
      name: rule.name,
      work: rule.condition,
      type: :condition,
      hash: work_hash(rule.condition),
    }
  end

  def of_reaction(%Rule{} = rule) do
    %__MODULE__{
      name: rule.name,
      work: rule.reaction,
      type: :reaction,
      hash: work_hash(rule.reaction),
    }
  end

  # todo: inject hashing method as dependency
  defp work_hash({m, f}),
    do: :erlang.phash2(:erlang.term_to_binary(Function.capture(m, f, 1)))
  defp work_hash(work) when is_function(work, 1),
    do: :erlang.phash2(:erlang.term_to_binary(work))

  defp fact_hash({m, f}, value),
    do: :erlang.phash2(:erlang.term_to_binary({Function.capture(m, f, 1), value}))
  defp fact_hash(work, value) when is_function(work, 1),
    do: :erlang.phash2(:erlang.term_to_binary({work, value}))

  def run(%Step{work: {m, f} = work}, %Fact{} = fact) do
    result_value = apply(m, f, [fact.value])
    Fact.new(value: result_value, hash: fact_hash(work, result_value))
  end

  def run(%Step{work: work}, %Fact{} = fact) when is_function(work) do
    result_value = work.(fact.value)
    Fact.new(value: result_value, hash: fact_hash(work, result_value))
  end
end
