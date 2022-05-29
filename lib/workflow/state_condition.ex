defmodule Dagger.Workflow.StateCondition do
  @moduledoc """
  An activateable step in a workflow for checking a condition in conjunction with a check/work/boolean-fun against an
  accumulator's prior state in memory.
  """
  alias Dagger.Workflow.Steps
  defstruct hash: nil, state_hash: nil, work: nil

  def new(work, state_hash) do
    %__MODULE__{state_hash: state_hash, work: work, hash: Steps.fact_hash({work, state_hash})}
  end
end
