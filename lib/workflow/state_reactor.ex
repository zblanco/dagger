defmodule Dagger.Workflow.StateReactor do
  @moduledoc """
  A step which knows its last state from memory defaulting to an initial value
  """
  alias Dagger.Workflow.Steps
  defstruct reactor: nil, init: nil, hash: nil

  def new(reactor, init \\ nil) do
    %__MODULE__{reactor: reactor, init: init, hash: Steps.work_hash(reactor)}
  end
end
