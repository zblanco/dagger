defmodule Dagger.Workflow.Fact do
  @moduledoc """
  A hashed representation of an input to a workflow wrapping a `value` of any kind of data.

  Every fact contains a hash of the {work, input_value, result_value} that produced the value contained in the fact.

  This hash is used to find the next steps in the workflow that need to be fed this fact.
  """

  alias Dagger.Workflow.Steps
  # import Norm
  defstruct value: nil,
            ancestry: nil,
            runnable: nil,
            hash: nil

  def new(params) do
    struct!(__MODULE__, params)
    |> maybe_set_hash()
  end

  defp maybe_set_hash(%__MODULE__{value: value, hash: nil} = fact) do
    %__MODULE__{fact | hash: Steps.fact_hash(value)}
  end

  defp maybe_set_hash(%__MODULE__{hash: hash} = fact)
       when not is_nil(hash),
       do: fact

  @typedoc """
  A fact is a determinstic representation of a model's reaction to some other input.
  """
  @type t() :: %__MODULE__{
          value: value(),
          ancestry: {hash(), hash()},
          runnable: {any(), __MODULE__.t()} | nil
        }

  @typedoc """
  The result of running a `work` function with the value of another fact.
  """
  @type value() :: term()

  @typedoc """
  A hash of some work function that produced or might produce a fact.
  """
  @type hash() :: binary()

  @typedoc """

  """
  @type ancestry() :: {hash(), hash()}
end
