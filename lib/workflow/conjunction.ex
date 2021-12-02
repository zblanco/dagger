defmodule Dagger.Workflow.Conjunction do
  @moduledoc """
  Represents a logical conjunction of n conditions where all n conditions must be satisfied
  for the conjunction to be satisfied.
  """
  defstruct hash: nil, condition_hashes: nil

  alias Dagger.Workflow.Steps

  def new(conditions) do
    condition_hashes = conditions |> MapSet.new(& &1.hash)

    %__MODULE__{
      hash: condition_hashes |> Steps.fact_hash(),
      condition_hashes: condition_hashes
    }
  end
end
