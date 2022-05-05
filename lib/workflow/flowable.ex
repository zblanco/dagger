defprotocol Dagger.Flowable do
  @moduledoc """
  The Flowable protocol is implemented by datastructures which know how to become a Dagger Workflow
    by implementing the `to_workflow/1` transformation.
  """
  @fallback_to_any true
  def to_workflow(flowable)
end

defimpl Dagger.Flowable, for: List do
  alias Dagger.Workflow

  def to_workflow([first_flowable | remaining_flowables]) do
    Enum.reduce(remaining_flowables, Dagger.Flowable.to_workflow(first_flowable), fn flowable,
                                                                                     wrk ->
      Workflow.merge(wrk, Dagger.Flowable.to_workflow(flowable))
    end)
  end
end

defimpl Dagger.Flowable, for: Dagger.Workflow do
  def to_workflow(wrk), do: wrk
end

defimpl Dagger.Flowable, for: Dagger.Workflow.Rule do
  def to_workflow(rule), do: rule.workflow
end

defimpl Dagger.Flowable, for: Dagger.Workflow.Step do
  alias Dagger.Workflow
  require Dagger

  def to_workflow(step),
    do: step.hash |> to_string() |> Workflow.new() |> Workflow.add_step(step)
end

defimpl Dagger.Flowable, for: Tuple do
  alias Dagger.Workflow.Rule

  def to_workflow({:fn, _meta, _clauses} = quoted_anonymous_function) do
    Dagger.Flowable.to_workflow(Rule.new(quoted_anonymous_function))
  end
end

defimpl Dagger.Flowable, for: Function do
  alias Dagger.Workflow

  def to_workflow(fun) do
    fun |> Function.info(:name) |> elem(1) |> Workflow.new() |> Workflow.add_step(fun)
  end
end

defimpl Dagger.Flowable, for: Any do
  alias Dagger.Workflow

  def to_workflow(anything_else) do
    work = fn _anything -> anything_else end

    work
    |> Dagger.Workflow.Steps.work_hash()
    |> to_string()
    |> Workflow.new()
    |> Workflow.add_step(work)
  end
end

defimpl Dagger.Flowable, for: Dagger.Workflow.StateMachine do
  def to_workflow(%Dagger.Workflow.StateMachine{} = fsm) do
    fsm.workflow
  end

  # def to_workflow(%Dagger.Workflow.Accumulator{
  #       init: init,
  #       reducers: reducers
  #     })
  #     when is_list(reducers) do
  #   Enum.reduce(
  #     reducers,
  #     Dagger.Workflow.merge(Dagger.Workflow.new(UUID.uuid4()), Dagger.Flowable.to_workflow(init)),
  #     fn reducer, wrk ->
  #       Dagger.Workflow.merge(wrk, Dagger.Flowable.to_workflow(reducer))
  #     end
  #   )
  # end
end
