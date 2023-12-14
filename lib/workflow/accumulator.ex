defmodule Dagger.Workflow.Accumulator do
  @moduledoc """
  A step which knows its last state from memory defaulting to an initial value.

  The initial state isn't stored as a fact in the workflow until the first activation.

  Upon first activation this will first log a fact indicating the initial state, then the
  result of running the state reactor's as the next state produced fact.
  """
  alias Dagger.Workflow.Steps
  defstruct reducer: nil, init: nil, hash: nil

  def new(reducer, init \\ nil)

  def new(reducer, init) when is_function(reducer) do
    %__MODULE__{reducer: reducer, init: init, hash: Steps.work_hash(reducer)}
  end

  def new({:fn, _, _} = reducer_ast, init) do
    Macro.to_string(reducer_ast)

    reducer_ast
    |> Code.eval_quoted([], __ENV__)
    |> elem(0)
    |> new(init)
  end
end
