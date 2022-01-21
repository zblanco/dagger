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

  Data structures following the Runnable protocol have to convert into a something ready for execution i.e. something that
    has both a function and the data to feed into it.

  Step dependencies are modeled in a Workflow Graph as a tuple of the parent node's hash and the step's hash.

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

  Instead of a :condition type we have a Condition data structure that knows how to convert itself into a step.

  The conflicting ideas of what Runnable is:

  * an actionable pair of a function and the data to execute it with. (name suits this better)
  * A model that can be fed facts and produce reactions
  """
  alias Dagger.Workflow.{Step, Fact, Steps}

  defstruct name: nil,
            work: nil,
            hash: nil

  def new(params) do
    struct!(__MODULE__, params)
    |> hash_work()
    |> maybe_set_name()
  end

  defp maybe_set_name(%__MODULE__{name: nil, hash: hash, work: work} = step) do
    fun_name = work |> Function.info(:name) |> elem(0)
    %__MODULE__{step | name: "#{fun_name}-#{hash}"}
  end

  defp maybe_set_name(%__MODULE__{name: nil, hash: hash} = step),
    do: %__MODULE__{step | name: to_string(hash)}

  defp maybe_set_name(%__MODULE__{name: name} = step) when not is_nil(name), do: step

  defp hash_work(%Step{work: work} = step), do: Map.put(step, :hash, Steps.work_hash(work))

  def run(%__MODULE__{} = step, input) when not is_struct(input, Fact) do
    Steps.run(step.work, input)
  end

  # todo: inject hashing method as dependency
  # consider forking libgraph to allow for user-defined node hashing/id functions

  # def run(%Step{work: {m, f}} = step, %Fact{} = fact) do
  #   result_value = apply(m, f, [fact.value])
  #   Fact.new(
  #     value: result_value,
  #     # hash: fact_hash(work, result_value),
  #     type: step.type,
  #     runnable: {step, fact}
  #   )
  # end

  # def run(%Step{work: work} = step, %Fact{} = fact) when is_function(work) do
  #   result_value = work.(fact.value)
  #   Fact.new(
  #     value: result_value,
  #     # hash: fact_hash(work, result_value),
  #     type: step.type,
  #     runnable: {step, fact}
  #   )
  # end

  # defimpl Dagger.Workflow.Runnable do
  #   alias Dagger.Workflow.{
  #     Fact,
  #     Step,
  #     Steps
  #   }

  #   def run(%Step{work: work, hash: work_hash} = step, %Fact{value: value, hash: fact_hash} = fact) do
  #     result = Steps.run(work, value)

  #     Fact.new(
  #       value: result,
  #       ancestry: {work_hash, fact_hash},
  #       runnable: {step, fact}
  #     )
  #   end

  #   def to_runnable(%Step{} = step, %Fact{} = fact) do
  #     {%Step{} = step, %Fact{} = fact}
  #   end
  # end
end
