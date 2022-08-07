defmodule Dagger.Workflow.StateReaction do
  alias Dagger.Workflow.Steps
  defstruct hash: nil, state_hash: nil, work: nil, arity: nil, ast: nil

  def new(work, state_hash, ast) do
    %__MODULE__{
      state_hash: state_hash,
      ast: ast,
      work: work,
      hash: Steps.fact_hash({work, state_hash}),
      arity: Steps.arity_of(work)
    }
  end
end
