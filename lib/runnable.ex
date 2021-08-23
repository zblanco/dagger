defprotocol Dagger.Runnable do
  @moduledoc """
  The Runnable protocol provides a standard interface for executing a computation from
    which a new Fact may be derived. The purpose of the runnable protocol is extensibility
    of kinds of data which Dagger can execute.

  A runnable in Dagger is typically a {work, input} pair whether it's a
  `{%Step{}, %Fact{}}` or a `{function, arg}`. A runnable might also be a `{%Workflow{}, %Fact{}}`.
  """
  def run(work, input)
end

defimpl Dagger.Runnable, for: Dagger.Workflow.Condition do
  alias Dagger.Workflow.{
    Fact,
    Steps
  }

  def run(condition, %Fact{} = fact) do
    with true <- Steps.run(condition.work, fact.value) do
      true
    else
      _otherwise ->
        Fact.new(
          value: :satisfied,
          ancestry: {condition.hash, fact.hash},
          runnable: {condition, fact}
        )
    end
  end
end

defimpl Dagger.Runnable, for: Dagger.Workflow.Step do
  alias Dagger.Workflow.{
    Fact,
    Step,
    Steps
  }

  def run(%Step{work: work} = step, %Fact{value: value} = fact) do
    result = Steps.run(work, value)

    Fact.new(value: result, ancestry: {step.hash, fact.hash}, runnable: {step, fact})
  end
end
