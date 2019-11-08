defmodule Dagger.TestRunner do
  @moduledoc """
  A simple job runner implementation for test contexts.
  """
  @behaviour Dagger.Runner
  alias Dagger.Step

  def squareaplier(num), do: {:ok, num * num}

  @impl true
  def run(%Step{} = step) do
    Step.run(step)
  end

  @impl true
  def ack(%Step{} = _step) do
    :ok
  end

  @impl true
  def cancel(_step_identifiers) do
    :ok
  end
end
