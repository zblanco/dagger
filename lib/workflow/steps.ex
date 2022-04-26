defmodule Dagger.Workflow.Steps do
  @doc false

  @max_phash 4_294_967_296

  def vertex_id_of(%{hash: hash}), do: hash
  def vertex_id_of(anything_otherwise), do: fact_hash(anything_otherwise)

  def memory_vertex_id(%{hash: hash}), do: hash
  def memory_vertex_id(hash) when is_integer(hash), do: hash
  def memory_vertex_id(anything_otherwise), do: fact_hash(anything_otherwise)

  def work_hash({m, f}),
    do: work_hash({m, f, 1})

  def work_hash({m, f, a}),
    do: fact_hash(:erlang.term_to_binary(Function.capture(m, f, a)))

  def work_hash(work) when is_function(work),
    do: fact_hash(:erlang.term_to_binary(work))

  def fact_hash(value), do: :erlang.phash2(value, @max_phash)

  def join_hash(left, right),
    do: fact_hash(:erlang.term_to_binary({left, right}))

  def run({m, f}, fact_value) when is_list(fact_value), do: run({m, f}, fact_value, 1)

  # def run({m, f}, [] = fact_value), do: apply(m, f, fact_value)
  # def run({m, f}, fact_value), do: apply(m, f, [fact_value])

  def run(work, fact_value) when is_function(work), do: run(work, fact_value, arity_of(work))

  def run({m, f}, [] = fact_value, a) do
    work = Function.capture(m, f, a)
    run(work, fact_value, arity_of(work))
  end

  def run(work, _fact_value, 0) when is_function(work), do: apply(work, [])

  def run(work, fact_value, 1) when is_function(work) and is_list(fact_value),
    do: apply(work, [fact_value])

  def run(work, fact_value, _arity) when is_function(work) and is_list(fact_value),
    do: apply(work, fact_value)

  def run(work, fact_value, _arity) when is_function(work), do: apply(work, [fact_value])

  def next_steps(flow, parent_step), do: Graph.out_neighbors(flow, parent_step)

  def arity_of({:fn, _, [{:->, _, [lhs, _rhs]}]}), do: Enum.count(lhs)

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

  def name_of_expression(work) when is_function(work) do
    name_of_expression(work, work_hash(work))
  end

  def name_of_expression(_anything_else), do: UUID.uuid4()

  def name_of_expression(work, hash) do
    fun_name = work |> Function.info(:name) |> elem(1)
    "#{fun_name}-#{hash}"
  end

  def ast_of_compiled_function(module, function_name) do
    with {_, accumulation_of_ast} <-
           module.__info__(:compile)[:source]
           |> to_string()
           |> File.read!()
           |> Code.string_to_quoted!()
           |> Macro.prewalk([], fn
             matching_fun = {:def, _, [{^function_name, _, _} | _]}, acc ->
               {matching_fun, [matching_fun | acc]}

             segment, acc ->
               {segment, acc}
           end) do
      accumulation_of_ast |> IO.inspect(label: "accumulation_of_ast")
    end
  end

  def expression_of({:fn, _meta, clauses}) do
    Enum.map(clauses, &expression_of_clauses/1)
  end

  def expression_of(function_as_string) when is_binary(function_as_string) do
    with {:ok, {:fn, _meta, _clauses} = quoted_func} <- Code.string_to_quoted(function_as_string) do
      quote bind_quoted: [quoted_func: quoted_func] do
        expression_of(quoted_func)
      end
    end
  end

  def expression_of(
        {:&, _capture_meta,
         [
           {:/, _arity_meta,
            [
              {{:., _dot_meta, [{:__aliases__, aliasing_opts, aliases}, function_name]},
               _dot_opts, _dot_etc}
              | [_arity]
            ]}
         ]} = captured_function
      ) do
    IO.inspect(captured_function, label: "captured_function")
    IO.inspect(Macro.to_string(captured_function), label: "to_string captured_function")

    root_module =
      case Keyword.fetch(aliasing_opts, :counter) do
        {:ok, {root_module, _}} -> root_module
        :error -> List.first(aliases)
      end
      |> IO.inspect(label: "root_module")

    captured_function_module_string =
      [root_module | aliases]
      |> Enum.map(fn module ->
        module_string = to_string(module)
        String.replace(module_string, "Elixir.", "")
      end)
      |> Enum.uniq()
      |> Enum.join(".")

    "Elixir.#{captured_function_module_string}"
    |> String.to_atom()
    |> ast_of_compiled_function(function_name)
    |> expression_of_clauses()
  end

  # def expression_of(
  #       {:&, _capture_meta,
  #        [
  #          {:/, _arity_meta,
  #           [
  #             {{:., _dot_meta, [{:__aliases__, aliasing_opts, aliases}, function_name]},
  #              _dot_opts, _dot_etc}
  #             | [_arity]
  #           ]}
  #        ]} = captured_function
  #     ) do
  #   IO.inspect(captured_function, label: "captured_function")
  #   IO.inspect(Macro.to_string(captured_function), label: "to_string captured_function")

  #   root_module = Keyword.get(aliasing_opts, :counter) |> elem(0)

  #   captured_function_module_string =
  #     [root_module | aliases]
  #     |> Enum.map(fn module ->
  #       module_string = to_string(module)
  #       String.replace(module_string, "Elixir.", "")
  #     end)
  #     |> Enum.uniq()
  #     |> Enum.join(".")

  #   captured_function_module =
  #     "Elixir.#{captured_function_module_string}"
  #     |> String.to_atom()

  #   with {:ok, function_ast} <- ast_of_compiled_function(captured_function_module, function_name) do
  #     expression_of_clauses(function_ast)
  #   end
  # end

  def expression_of_clauses({:->, _meta, [lhs, rhs]}) do
    {lhs, rhs}
  end

  def expression_of_clauses({:->, _meta, [[], rhs]}) do
    {&always_true/1, rhs}
  end

  def expression_of_clauses(
        [{:def, _meta, [{_function_name, _clause_meta, _lhs}, [do: rhs]]} | _rest] = clauses
      ) do
    if Enum.all?(clauses, &is_rhs_same?(&1, rhs)) do
      lhs_conditions =
        clauses
        |> Enum.map(fn {:def, _meta, [{_function_name, _clause_meta, clause_lhs}, _clause_rhs]} ->
          # ast = {:fn, [], [{:->, [], clause_lhs}, [do: true]]}
          ast = {:fn, [], [{:->, [], [clause_lhs, true]}]}

          IO.inspect(Macro.to_string(ast), label: "ast of def function rewrite")
          ast
        end)

      # workflow vs rule?
      {lhs_conditions, rhs} |> IO.inspect(label: "our weird ass def rewrite")
    end
  end

  def expression_of_clauses(clauses) when is_list(clauses) do
    clauses
    |> IO.inspect(label: "clauses")
    |> Enum.map(&expression_of_clauses/1)
    |> List.flatten()
  end

  def expression_of_clauses({:def, _meta, [{_function_name, _clause_meta, lhs}, [do: rhs]]}) do
    {lhs, rhs}
  end

  defp is_rhs_same?({:def, _meta, [{_function_name, _clause_meta, _lhs}, [do: rhs]]}, other_rhs) do
    rhs === other_rhs
  end

  def work_of_lhs({lhs, _meta, nil}) do
    work_of_lhs(lhs)
  end

  def work_of_lhs({:fn, meta, clauses} = lhs) do
    IO.inspect(lhs, label: "work_of_lhs input")
    false_branch = false_branch_for_lhs(lhs)

    branches = [false_branch | clauses] |> Enum.reverse()

    check = {:fn, meta, branches}

    Macro.prewalk(lhs, fn
      ast -> IO.inspect(ast, label: "ast of anonymous fun")
    end)

    IO.inspect(Macro.to_string(check), label: "check of anonymous function")
    {fun, _} = Code.eval_quoted(check)
    fun
  end

  # def work_of_lhs(
  #       {:&, _,
  #        [
  #          {:/, _,
  #           [
  #             {{:., _,
  #               [
  #                 {:__aliases__, _alias_meta, _aliases} = alias_opts | _rest
  #               ]}, _, []},
  #             _
  #           ]}
  #        ]} = captured_function
  #     ) do
  #   aliases = Macro.expand(alias_opts, __ENV__) |> IO.inspect(label: "alias_opts expanded")

  #   IO.inspect(captured_function, label: "quoted captured_function")
  #   IO.inspect(Macro.to_string(captured_function), label: "captured_function")
  #   {fun, _} = Code.eval_quoted(captured_function, [], aliases: [aliases])
  #   fun
  # end

  def work_of_lhs({:&, _, [{:/, _, _}]} = captured_function) do
    IO.inspect(captured_function, label: "quoted captured_function")
    IO.inspect(Macro.to_string(captured_function), label: "captured_function")

    {fun, _} = Code.eval_quoted(captured_function)

    fun
  end

  def work_of_lhs(lhs) do
    IO.inspect(lhs, label: "lhs in catch all")
    false_branch = false_branch_for_lhs(lhs)
    # false_branch = {:->, [], [[{:_, [], Elixir}], false]}

    branches =
      [false_branch | [check_branch_of_expression(lhs)]]
      |> Enum.reverse()

    check = {:fn, [], branches}

    IO.inspect(Macro.to_string(check), label: "check")
    {fun, _} = Code.eval_quoted(check)
    fun
  end

  def work_of_rhs(lhs, [rhs | _]) do
    work_of_rhs(lhs, rhs)
  end

  def work_of_rhs(lhs, rhs) when is_function(lhs) do
    IO.inspect(rhs, label: "workofrhs")

    rhs =
      {:fn, [],
       [
         {:->, [], [[{:_, [], Elixir}], rhs]}
       ]}

    IO.inspect(Macro.to_string(rhs), label: "rhs as string when is_function")
    {fun, _} = Code.eval_quoted(rhs)
    fun
  end

  def work_of_rhs(lhs, rhs) do
    IO.inspect(rhs, label: "workofrhs")

    rhs =
      {:fn, [],
       [
         {:->, [], [lhs, rhs]}
       ]}

    IO.inspect(Macro.to_string(rhs), label: "rhs as string for arbitrary lhs/rhs")
    {fun, _} = Code.eval_quoted(rhs)
    fun
  end

  def false_branch_for_lhs([{:when, _meta, args} | _]) do
    arg_false_branches =
      args
      |> Enum.reject(&(not match?({_arg_name, _meta, nil}, &1)))
      |> Enum.map(fn _ -> {:_, [], Elixir} end)

    {:->, [], [arg_false_branches, false]}
  end

  def false_branch_for_lhs(lhs) when is_list(lhs) do
    # we may need to do an ast traversal here
    {:->, [], [Enum.map(lhs, fn _ -> {:_, [], Elixir} end), false]}
  end

  def false_branch_for_lhs(_lhs_otherwise) do
    {:->, [], [[{:_, [], Elixir}], false]}
  end

  # defp check_branch_of_expression(lhs) when is_function(lhs) do
  #   # quote bind_quoted: [lhs: lhs] do
  #   #   fn lhs
  #   # end

  #   wrapper =
  #     quote bind_quoted: [lhs: lhs] do
  #       fn input ->
  #         try do
  #           IO.inspect(apply(lhs, input), label: "application")
  #         rescue
  #           true -> true
  #           otherwise ->
  #             IO.inspect(otherwise, label: "otherwise")
  #             false
  #         end
  #       end
  #     end

  #   IO.inspect(Macro.to_string(wrapper), label: "wrapper")

  #   {:->, [], [[:_], wrapper]}
  # end

  def check_branch_of_expression(lhs) when is_list(lhs) do
    IO.inspect(lhs, label: "lhx in check_branch_of_expression/1")
    {:->, [], [lhs, true]}
  end

  def check_branch_of_expression(lhs), do: lhs
end
