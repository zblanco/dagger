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

  def next_match_runnables(%__MODULE__{runnables: runnables}) do
    runnables
    |> Map.values()
    |> Enum.filter(&is_match_runnable?/1)
  end

  defp runnable_key(node, fact), do: {node.hash, fact.hash}

  def any_runnables_for_next_cycle?(%__MODULE__{runnables: runnables}) do
    not Enum.empty?(runnables)
  end

  def any_match_phase_runnables?(%__MODULE__{runnables: runnables}) do
    Enum.any?(runnables, &is_match_runnable?/1)
  end

  defp is_match_runnable?({_key, {%Dagger.Workflow.Step{}, _fact}}), do: false
  defp is_match_runnable?({_key, {_any_other_vertex, _fact}}), do: true
  defp is_match_runnable?({%Dagger.Workflow.Step{}, _fact}), do: false
  defp is_match_runnable?({_any_other_vertex, _fact}), do: true
end
