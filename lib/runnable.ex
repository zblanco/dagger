defprotocol Dagger.Runnable do
  @doc """
  Protocol that enforces the runnability of a data structure.

  This dispatches the `to_step/1` transformation function required by the runnable protocol.

  `to_step/1` implementations are required to return `{:ok, %Step{}} | {:error, any}`.

  It isn't necessary to use runnable to use Dagger.
  You can just use functions like `Step.new` and `Step.add_dependent_job` in your business logic.
  However the `Runnable` protocol allows further decoupling and removal of implementation details to your code.

  It is recommended to use the Runnable protocol as a way of first validating your inputs before executing `work` in a step.
  """
  def to_step(maybe_runnable_data)
end
