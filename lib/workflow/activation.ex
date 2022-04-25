defprotocol Dagger.Workflow.Activation do
  @moduledoc """
  Protocol enforcing how an operation/step/node within a workflow can always be activated in context of a workflow.

  The return of an implementation's `activate/3` should always return a new workflow.

  `activate/3`

  The activation protocol invokes the runnable protocol to evaluate valid steps in that cycle starting with conditionals.
  """
  def activate(node, workflow, fact)
  def match_or_execute(node)

  # def runnable_connection(node)
  # def resolved_connection(node)
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Root do
  alias Dagger.Workflow.Root
  alias Dagger.Workflow.Fact
  alias Dagger.Workflow

  def activate(%Root{}, workflow, %Fact{ancestry: {parent_hash, _parent_fact_hash}} = fact) do
    workflow
    |> Workflow.log_fact(fact)
    # |> Workflow.prepare_next_generation(fact)
    |> Workflow.prepare_next_runnables(Map.get(workflow.flow.vertices, parent_hash), fact)
  end

  def activate(%Root{} = root, workflow, fact) do
    workflow
    |> Workflow.log_fact(fact)
    |> Workflow.prepare_next_generation(fact)
    |> Workflow.prepare_next_runnables(root, fact)
  end

  def match_or_execute(_root), do: :match
  # def runnable_connection(_root), do: :root
  # def resolved_connection(_root), do: :root
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Condition do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Condition,
    Steps
  }

  @spec activate(Dagger.Workflow.Condition.t(), Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Condition{} = condition,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    if try_to_run_work(condition.work, fact.value, condition.arity) do
      workflow
      |> Workflow.prepare_next_runnables(condition, fact)
      |> Workflow.draw_connection(fact, condition.hash, :satisfied)
      |> Workflow.mark_runnable_as_ran(condition, fact)
    else
      Workflow.mark_runnable_as_ran(workflow, condition, fact)
    end
  end

  # def runnable_connection(_condition), do: :matchable
  # def resolved_connection(_condition), do: :satisfied

  def match_or_execute(_condition), do: :match

  defp try_to_run_work(work, fact_value, arity) do
    try do
      run_work(work, fact_value, arity) |> IO.inspect(label: "run work attempt")
    rescue
      FunctionClauseError -> false
    catch
      true ->
        true

      any ->
        IO.inspect(any,
          label: "something other than FunctionClauseError happened in try_to_run_work/3"
        )

        false
    end
  end

  defp run_work(work, fact_value, 1) when is_list(fact_value) do
    apply(work, fact_value)
  end

  defp run_work(work, fact_value, arity) when arity > 1 and is_list(fact_value) do
    Steps.run(work, fact_value)
  end

  defp run_work(_work, _fact_value, arity) when arity > 1 do
    false
  end

  defp run_work(work, fact_value, _arity) do
    Steps.run(work, fact_value)
  end

  # defp satisfied_fact(%Condition{} = condition, %Fact{} = fact) do
  #   Fact.new(
  #     value: :satisfied,
  #     ancestry: {condition.hash, fact.hash},
  #     runnable: {condition, fact}
  #   )
  # end
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Step do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Step,
    Steps
  }

  @spec activate(%Dagger.Workflow.Step{}, Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Step{} = step,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    result = Steps.run(step.work, fact.value, Steps.arity_of(step.work))

    result_fact = Fact.new(value: result, ancestry: {step.hash, fact.hash})
    # Fact.new(value: result, ancestry: {step.hash, fact.hash}, runnable: {step, fact})

    workflow
    |> Workflow.draw_connection(step.hash, result_fact, :produced)
    |> Workflow.log_fact(result_fact)
    |> Workflow.prepare_next_runnables(step, result_fact)
    |> Workflow.mark_runnable_as_ran(step, fact)
  end

  def match_or_execute(_step), do: :execute
  # def runnable_connection(_step), do: :runnable
  # def resolved_connection(_step), do: :ran
  # def causal_connection(_step), do: :produced
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Conjunction do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Conjunction
  }

  @spec activate(%Dagger.Workflow.Conjunction{}, Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Conjunction{} = conj,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    satisfied_conditions =
      Workflow.satisfied_conditions(workflow, fact) |> IO.inspect(label: "satisfied_conditions")

    IO.inspect(conj.condition_hashes, label: "required to activate #{conj.hash}")

    if conj.hash not in satisfied_conditions and
         Enum.all?(conj.condition_hashes, &(&1 in satisfied_conditions)) do
      IO.inspect(conj.hash, label: "conjunction is satisfied")

      workflow
      |> Workflow.prepare_next_runnables(conj, fact)
      |> Workflow.draw_connection(fact, conj.hash, :satisfied)
      |> Workflow.mark_runnable_as_ran(conj, fact)
    else
      IO.inspect(conj.hash, label: "conjunction not satisfied")
      Workflow.mark_runnable_as_ran(workflow, conj, fact)
    end
  end

  def match_or_execute(_conjunction), do: :match
  # def runnable_connection(_conjunction), do: :matchable
  # def resolved_connection(_conjunction), do: :satisfied
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.MemoryAssertion do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    MemoryAssertion
  }

  @spec activate(
          %Dagger.Workflow.MemoryAssertion{},
          Dagger.Workflow.t(),
          Dagger.Workflow.Fact.t()
        ) :: Dagger.Workflow.t()
  def activate(
        %MemoryAssertion{} = ma,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    if ma.memory_assertion.(workflow.memory) do
      workflow
      |> Workflow.prepare_next_runnables(ma, fact)
      |> Workflow.draw_connection(fact, ma.hash, :satisfied)
      |> Workflow.mark_runnable_as_ran(ma, fact)
    else
      Workflow.mark_runnable_as_ran(workflow, ma, fact)
    end
  end

  def match_or_execute(_memory_assertion), do: :match
  # def runnable_connection(_memory_assertion), do: :matchable
  # def resolved_connection(_memory_assertion), do: :satisfied
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.StateCondition do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    StateCondition
  }

  @spec activate(
          %Dagger.Workflow.StateCondition{},
          Dagger.Workflow.t(),
          Dagger.Workflow.Fact.t()
        ) :: Dagger.Workflow.t()
  def activate(
        %StateCondition{} = sc,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    # get last known state or the init of the accumulator
    last_known_state = last_known_state(sc.state_hash, workflow)
    # check
  end

  defp last_known_state(state_hash, workflow) do
    workflow.memory
    |> Graph.out_edges(state_hash)
    |> Enum.filter(&(&1.label == :state_produced and &1.v1.generation == workflow.generation - 1))
    |> List.first(%{})
    |> Map.get(:v1)
  end

  def match_or_execute(_state_condition), do: :match
  # def runnable_connection(_state_condition), do: :matchable
  # def resolved_connection(_state_condition), do: :satisfied
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Accumulator do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Steps,
    Accumulator
  }

  @spec activate(%Dagger.Workflow.Accumulator{}, Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Accumulator{} = acc,
        %Workflow{} = workflow,
        %Fact{} = fact
      ) do
    last_known_state = last_known_state(workflow, acc)

    unless is_nil(last_known_state) do
      next_state = apply(acc.reducer, [fact.value, last_known_state.value])

      next_state_produced_fact = Fact.new(value: next_state, ancestry: {acc.hash, fact.hash})

      workflow
      |> Workflow.prepare_next_runnables(acc, fact)
      |> Workflow.log_fact(next_state_produced_fact)
      |> Workflow.draw_connection(acc.hash, fact, :state_produced)
      |> Workflow.mark_runnable_as_ran(acc, fact)
    else
      init_fact = init_fact(acc)

      next_state = apply(acc.reducer, [fact.value, init_fact.value])

      next_state_produced_fact = Fact.new(value: next_state, ancestry: {acc.hash, fact.hash})

      workflow
      |> Workflow.log_fact(init_fact)
      |> Workflow.draw_connection(acc.hash, init_fact, :state_produced)
      |> Workflow.prepare_next_runnables(acc, fact)
      |> Workflow.log_fact(next_state_produced_fact)
      |> Workflow.draw_connection(acc.hash, next_state_produced_fact, :state_produced)
      |> Workflow.mark_runnable_as_ran(acc, fact)
    end
  end

  def match_or_execute(_state_reactor), do: :execute

  # def runnable_connection(_state_condition), do: :runnable
  # def resolved_connection(_state_condition), do: :state_produced

  defp last_known_state(workflow, accumulator) do
    workflow.memory
    |> Graph.out_edges(accumulator.hash)
    # we might want generational nodes ? maybe a property on the edge label of a state produced connection?
    |> Enum.filter(&(&1.label == :state_produced and &1.v1.generation == workflow.generation - 1))
    |> List.first(%{})
    |> Map.get(:v1)
  end

  defp init_fact(%Accumulator{init: init, hash: hash}),
    do: Fact.new(value: init, ancestry: {hash, Steps.fact_hash(init)})
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Join do
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Join
  }

  @spec activate(%Dagger.Workflow.Join{}, Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
          Dagger.Workflow.t()
  def activate(
        %Join{} = join,
        %Workflow{} = workflow,
        %Fact{ancestry: {_parent_hash, _value_hash}} = fact
      ) do
    # a join has n parents that must have produced a fact
    # a join's parent steps are either part of a runnable (for a partially satisfied join)
    # or each step has a produced edge to a new fact for whom the current fact is the ancestor

    workflow = Workflow.draw_connection(workflow, fact, join.hash, :joined)

    possible_priors =
      workflow.memory
      |> Graph.in_edges(join.hash)
      |> Enum.filter(&(&1.label == :joined))
      |> Enum.map(& &1.v1.value)

    if Enum.count(join.joins) == Enum.count(possible_priors) do
      join_bindings_fact = Fact.new(value: possible_priors, ancestry: {join.hash, fact.hash})

      workflow =
        workflow
        |> Workflow.log_fact(join_bindings_fact)
        |> Workflow.prepare_next_runnables(join, join_bindings_fact)

      workflow.memory
      |> Graph.in_edges(join.hash)
      |> Enum.reduce(workflow, fn
        %{v1: v1, label: :runnable}, wrk ->
          Workflow.mark_runnable_as_ran(wrk, join, v1)

        %{v1: v1, v2: v2, label: :joined}, wrk ->
          %Workflow{
            wrk
            | memory:
                wrk.memory |> Graph.update_labelled_edge(v1, v2, :joined, label: :join_satisfied)
          }
      end)
      |> Workflow.draw_connection(join.hash, join_bindings_fact, :produced)
    else
      workflow
    end
  end

  # defp from_same_ancestor(memory, parent_hash, %Graph.Edge{label: :produced} = produced_edge) do
  #   memory
  #   |> Graph.in_edges(produced_edge.v1)
  #   |> Enum.any?(&(&1.label == :ran and &1.v2 == parent_hash))
  # end
  # def runnable_connection(_state_condition), do: :runnable
  # def resolved_connection(_state_condition), do: :join_satisfied

  def match_or_execute(_join), do: :execute
end
