defmodule Dagger.Workflow.StateReactor do
  @moduledoc """
  A step which knows its last state from memory defaulting to an initial value.

  The initial state isn't stored as a fact in the workflow until the first activation.

  Upon first activation this will first log a fact indicating the initial state, then the
  result of running the state reactor's as the next state produced fact.
  """
  alias Dagger.Workflow.Steps
  defstruct reactor: nil, init: nil, hash: nil

  def new(reactor, init \\ nil) do
    %__MODULE__{reactor: reactor, init: init, hash: Steps.work_hash(reactor)}
  end
end
