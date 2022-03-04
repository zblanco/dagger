defmodule Dagger.Workflow.MemoryAssertion do
  @moduledoc """
  A stateful condition is a match on a past generation's facts where to pass a prior reaction must've occurred.

  Stateful conditions match on facts of an ancestor or a set of ancestor's hashes - they operate as a sort of explicit
  cyclic dependency but one where the runner can choose how to proceed.

  When activated for a given fact a stateful condition will assess its set of required ancestors for which
  the given fact must have been produced by or by which must be in memory.
  """
  defstruct memory_assertion: nil, hash: nil

  alias Dagger.Workflow.Steps

  def new(memory_assertion) do
    %__MODULE__{memory_assertion: memory_assertion, hash: Steps.work_hash(memory_assertion)}
  end
end
