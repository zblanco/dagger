defprotocol Dagger.Flowable do
  @moduledoc """
  The Flowable protocol is implemented by datastructures which know how to become a Dagger Workflow
    by implementing the `to_workflow/1` transformation.
  """
  def to_workflow(flowable)
end
