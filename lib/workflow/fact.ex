defmodule Dagger.Workflow.Fact do
  @moduledoc """
  A hashed representation of an input to a workflow wrapping a `value` of any kind of data.

  Every fact contains a hash of the {work, input_value, result_value} that produced the value contained in the fact.

  This hash is used to find the next steps in the workflow that need to be fed this fact.
  """
  # import Norm
  defstruct value: nil,
            hash: nil,
            type: :reaction,
            runnable: nil

  def new(params) do
    struct!(__MODULE__, params)
  end

  @typedoc """
  A fact is a determinstic representation of a model's reaction to some other input.
  """
  @type t() :: %__MODULE__{
    value: value(),
    hash: hash(),
    type: :reaction | :accumulation | :condition,
    runnable: {Dagger.Workflow.Step.t(), __MODULE__.t()} | nil
  }

  @typedoc """
  The result of running a `work` function with the value of another fact.
  """
  @type value() :: term()

  @typedoc """
  A hash is a combination of the stream identities of prior facts and the workflow definition that handled the stream.

  From the hash we can infer what runtime processes for a workflow should be fed this fact, if prior executions were invalid or out of date.
  """
  @type hash() :: binary()
end
