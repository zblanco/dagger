defmodule Dagger.Workflow.Agenda do
  @moduledoc """
  The agenda is a workflow's to do list.

  The `generation` field is incremented during each generational cycle of runnables.

  Each generation has a set of runnables that can be executed in parallel.

  Once all of a generation's runnables are executed the next generation can proceed.

  For lazy evaluation we need to store
  """
  # consider using a PriorityQueue
  @type t() :: %__MODULE__{
    runnables: list(),
    generation: pos_integer(),
  }
  defstruct runnables: [],
            generation: 0

  def new, do: struct(__MODULE__, runnables: [], generation: 0)

  def next_generation(%__MODULE__{generation: g} = agenda) do
    %__MODULE__{agenda | generation: g + 1, runnables: []}
  end

  def add_runnable(%__MODULE__{runnables: runnables} = agenda, {_step, _fact} = runnable) do
    %__MODULE__{agenda | runnables: [runnable | runnables]}
  end
end
