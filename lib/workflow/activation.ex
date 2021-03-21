defprotocol Dagger.Workflow.Activation do
  @moduledoc """
  Protocol enforcing how an operation/step/node within a workflow can always be activated in context of the workflow.

  Activation protocol permits only serial state transformations of a workflow, i.e. the return of activating a node is always a new Workflow.

  Activation is used for varying types of nodes within a workflow to know how
    to "activate" by preparing an agenda and maintain state for partially satisfied conditions.

  The activation protocol's goal is to extract the runnables of the next cycle and prepare that in the agenda in the minimum amount of work.

  The activation protocol invokes the runnable protocol to evaluate valid steps in that cycle starting with conditionals.
  """
  def activate(workflow, node, fact)
end

defimpl Dagger.Workflow.Activation, for: :root do
  def activate(workflow, :root, fact) do
    next_runnables =
      workflow
      |> Dagger.Workflow.next_steps(:root)
      |> Enum.map(&Runnable.to_runnable(&1, fact))

    workflow
    |> Dagger.Workflow.log_fact(fact)
    |> Dagger.Workflow.add_to_agenda(next_runnables)
  end
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Condition do
  alias Dagger.Workflow
  alias Dagger.Workflow.{
    Fact,
    Condition,
    Runnable,
    Step,
    Steps
  }

  @spec activate(Dagger.Workflow.t(), Dagger.Workflow.Condition.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Workflow{} = workflow,
        %Condition{} = condition,
        %Fact{} = fact
      ) do
    with runnable_condition <- Runnable.to_runnable(condition, fact),
         true               <- Runnable.run(runnable_condition)
    do
      satisfied_fact = satisfied_fact(condition, fact)
      children_steps = Workflow.next_steps(workflow, condition)
      next_runnables =
        children_steps
        |> Enum.filter(&match?(%Step{}, &1))
        |> Enum.map(&Runnable.to_runnable(&1, fact))

      workflow
      |> Workflow.log_fact(satisfied_fact)
      |> Workflow.add_to_agenda(next_runnables)
    else
      false -> workflow
    end
  end

  # defp maybe_activate_joins(workflow, %Fact{value: satisfied})

  defp satisfied_fact(%Condition{} = condition, %Fact{} = fact) do
    condition =
      unless is_nil(condition.runnable) do
        # to ensure nested runnables in facts don't accumulate indefinitely
        Map.delete(condition, :runnable)
      end

    Fact.new(
      value: :satisfied,
      ancestry: {condition.hash, fact.hash},
      runnable: {condition, fact}
    )
  end
end
