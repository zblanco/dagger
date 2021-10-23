defprotocol Dagger.Workflow.Activation do
  @moduledoc """
  Protocol enforcing how an operation/step/node within a workflow can always be activated in context of the workflow.

  Activation protocol permits only serial state transformations of a workflow, i.e. the return of activating a node is always a new Workflow.

  Activation is used for varying types of nodes within a workflow to know how
    to "activate" by preparing an agenda and maintain state for partially satisfied conditions.

  The activation protocol's goal is to extract the runnables of the next cycle and prepare that in the agenda in the minimum amount of work.

  The activation protocol invokes the runnable protocol to evaluate valid steps in that cycle starting with conditionals.
  """
  def activate(node, workflow, fact)
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Root do
  alias Dagger.Workflow.Root

  def activate(%Root{} = root, workflow, fact) do
    next_runnables =
      workflow
      |> Dagger.Workflow.next_steps(root)
      |> Enum.map(&{&1, fact})

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
    Steps
  }

  @spec activate(Dagger.Workflow.Condition.t(), Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Condition{} = condition,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    IO.inspect(condition)
    IO.inspect(fact)
    with true <- try_to_run_work(condition.work, fact.value, condition.arity) do
      satisfied_fact = satisfied_fact(condition, fact)

      next_runnables =
        workflow
        |> Workflow.next_steps(condition)
        |> Enum.map(&{&1, fact})

      workflow
      |> Workflow.log_fact(satisfied_fact)
      |> Workflow.add_to_agenda(next_runnables)
      |> Workflow.prune_activated_runnable(condition, fact)
    else
      _anything_otherwise ->
        Workflow.prune_activated_runnable(workflow, condition, fact)
    end
  end

  def try_to_run_work(work, fact_value, arity) do
    try do
      run_work(work, fact_value, arity)
    rescue
      _anything -> false
    end
  end

  defp run_work(work, fact_value, 1) when is_list(fact_value) do
    apply(work, fact_value)
  end

  defp run_work(work, fact_value, arity) when arity > 1 and is_list(fact_value) do
    Steps.run(work, fact_value)
  end

  defp run_work(_work, _fact_value, arity) when arity > 1 do
    false
  end

  defp run_work(work, fact_value, _arity) do
    Steps.run(work, fact_value)
  end

  defp satisfied_fact(%Condition{} = condition, %Fact{} = fact) do
    Fact.new(
      value: :satisfied,
      ancestry: {condition.hash, fact.hash},
      runnable: {condition, fact}
    )
  end
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Step do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Step,
    Steps
  }

  def activate(
        %Step{} = step,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    result = Steps.run(step.work, fact.value)

    result_fact =
      Fact.new(value: result, ancestry: {step.hash, fact.hash}, runnable: {step, fact})

    next_runnables =
      workflow
      |> Workflow.next_steps(step)
      |> Enum.map(&{&1, result_fact})

    workflow
    |> Workflow.log_fact(result_fact)
    |> Workflow.add_to_agenda(next_runnables)
    |> Workflow.prune_activated_runnable(step, fact)
  end
end
