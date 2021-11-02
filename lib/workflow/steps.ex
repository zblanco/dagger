defmodule Dagger.Workflow.Steps do
  @doc false

  def work_hash({m, f}),
    do: work_hash({m, f, 1})

  def work_hash({m, f, a}),
    do: :erlang.phash2(:erlang.term_to_binary(Function.capture(m, f, a)))

  def work_hash(work) when is_function(work),
    do: :erlang.phash2(:erlang.term_to_binary(work))

  def fact_hash(value), do: :erlang.phash2(value)

  def join_hash(left, right),
    do: :erlang.phash2(:erlang.term_to_binary({left, right}))

  def run({m, f}, [] = fact_value), do: apply(m, f, fact_value)
  def run({m, f}, fact_value), do: apply(m, f, [fact_value])

  def run(work, fact_value) when is_function(work), do: apply(work, [fact_value])

  def next_steps(flow, parent_step), do: Graph.out_neighbors(flow, parent_step)

  def arity_of(fun) when is_function(fun), do: Function.info(fun, :arity) |> elem(1)

  def arity_of([
        {:->, _meta, [[{:when, _when_meta, lhs_expression}] | _rhs]} | _
      ]) do
    lhs_expression
    |> Enum.reject(&(not match?({_arg_name, _meta, nil}, &1)))
    |> length()
  end

  def arity_of([{:->, _meta, [lhs | _rhs]} | _]), do: arity_of(lhs)

  def arity_of(args) when is_list(args), do: length(args)

  def arity_of(_term), do: 1

  def is_of_arity?(arity) do
    fn
      args when is_list(args) ->
        if(arity == 1, do: true, else: false)

      args ->
        arity_of(args) == arity
    end
  end

  def always_true(_anything), do: true

  def returns_whatever(whatever), do: {__MODULE__, whatever}

  def whatever(whatever), do: whatever
end
