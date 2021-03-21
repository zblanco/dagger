defprotocol Dagger.Workflow.Runnable do
  def to_runnable(operation, input) # goal? support polymorphism by decomposing into work, input_data pairs until atomic of {fun, term} is reached
  def run(runnable, input) # can we just run a runnable by giving it an input?
  def run(runnable)
  # a runnable will always return a fact or another runnable who's contract is to conform to the parent's contracts eventually also returning a runnable or a fact.
  # a runnable's set of cycles - depending on the context - may be eagerly or lazily evaluated.
end

defimpl Dagger.Workflow.Runnable, for: Dagger.Workflow.Condition do
  # a condition always runs to return a
  def to_runnable(condition, fact) do
    {condition.work, fact.value}
  end

  def run({work, value}) do
    Dagger.Workflow.Steps.run(work, value)
  end

  # def run(condition, %Fact{} = fact) do
  #   with true <- Dagger.Workflow.Steps.run(condition.work, fact.value)
  # end

end

defimpl Dagger.Workflow.Runnable, for: Dagger.Workflow.Step do
  def to_runnable(step, fact) do
    {step.work, fact.value}
  end

  def run({work, value}) do
    Dagger.Workflow.Steps.run(work, value)
  end
end

# defimpl Dagger.Workflow.Runnable, for: {%Dagger.Workflow.Step{}, %Dagger.Workflow.Fact{}} do
#   def to_runnable(step, fact) do
#     {step.work, fact.value}
#   end

#   def run({work, value}) do
#     Dagger.Workflow.Steps.run(work, value)
#   end
# end
