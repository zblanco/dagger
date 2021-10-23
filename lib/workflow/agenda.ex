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
          runnables: map(),
          cycles: pos_integer()
        }
  defstruct runnables: %{},
            cycles: 0

  def new, do: struct(__MODULE__, runnables: %{}, cycles: 0)

  def next_cycle(%__MODULE__{cycles: c} = agenda) do
    %__MODULE__{agenda | cycles: c + 1}
  end

  def add_runnable(%__MODULE__{runnables: runnables} = agenda, {node, fact} = runnable) do
    %__MODULE__{agenda | runnables: Map.put_new(runnables, runnable_key(node, fact), runnable)}
  end

  def prune_runnable(%__MODULE__{runnables: runnables} = agenda, node, fact) do
    %__MODULE__{agenda | runnables: Map.delete(runnables, runnable_key(node, fact))}
  end

  def next_runnables(%__MODULE__{runnables: runnables}), do: Map.values(runnables)

  defp runnable_key(node, fact), do: {node.hash, fact.hash}

  def any_runnables_for_next_cycle?(%__MODULE__{runnables: runnables}) do
    not Enum.empty?(runnables)
  end
end
