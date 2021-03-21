defmodule Dagger.Workflow.Steps do
  @moduledoc """
  Common helpers for working with steps of any kind.
  """

  def work_hash({m, f}),
    do: :erlang.phash2(:erlang.term_to_binary(Function.capture(m, f, 1)))

  def work_hash(work) when is_function(work, 1),
    do: :erlang.phash2(:erlang.term_to_binary(work))

  def fact_hash(value), do: :erlang.phash2(value)

  def join_hash(left, right),
    do: :erlang.phash2(:erlang.term_to_binary({left, right}))

  def run({m, f}, fact_value), do: apply(m, f, [fact_value])

  def run(work, fact_value) when is_function(work), do: work.(fact_value)

  def next_steps(flow, parent_step), do: Graph.out_neighbors(flow, parent_step)

  def always_true(_anything), do: true

  def returns_whatever(whatever), do: {__MODULE__, whatever}

  def whatever(whatever), do: whatever
end
