defmodule Dagger.Workflow.Join do
  @moduledoc """
  A join is a step which requires all of its parent step's facts for a generation to have been produced
  so it may join them into a single joined-fact.
  """
  alias Dagger.Workflow.Steps

  defstruct joins: [], hash: nil

  def new(joins) when is_list(joins) do
    %__MODULE__{joins: joins, hash: Steps.fact_hash(joins)}
  end
end
