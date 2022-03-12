defprotocol Dagger.Workflow.Activation do
  @moduledoc """
  Protocol enforcing how an operation/step/node within a workflow can always be activated in context of a workflow.

  Activation protocol permits only serial state transformations of a workflow, i.e. the return of activating a node is always a new Workflow.

  Activation is used for varying types of nodes within a workflow to know how
    to "activate" by preparing an agenda and maintaining state for partially satisfied conditions.

  The activation protocol's goal is to extract the runnables of the next cycle and prepare that in the agenda in the minimum amount of work.

  The activation protocol invokes the runnable protocol to evaluate valid steps in that cycle starting with conditionals.
  """
  def activate(node, workflow, fact)
end

defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.Root do
  alias Dagger.Workflow.Root

  def activate(%Root{} = root, workflow, fact) do
    next_runnables =
      workflow
      |> Dagger.Workflow.next_steps(root)
      |> Enum.map(&{&1, fact})

    workflow
    |> Dagger.Workflow.log_fact(fact)
    |> Dagger.Workflow.add_to_agenda(next_runnables)
  end
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
    with true <-
           try_to_run_work(condition.work, fact.value, condition.arity)
           |> IO.inspect(label: "did condition work pass for #{condition.hash} : #{fact.hash}?") do
      satisfied_fact = satisfied_fact(condition, fact)

      next_runnables =
        workflow
        |> Workflow.next_steps(condition)
        |> Enum.map(&{&1, fact})

      workflow
      |> Workflow.log_fact(satisfied_fact)
      |> Workflow.add_to_agenda(next_runnables)
      |> Workflow.prune_activated_runnable(condition, fact)
    else
      _anything_otherwise ->
        Workflow.prune_activated_runnable(workflow, condition, fact)
    end
  end

  def try_to_run_work(work, fact_value, arity) do
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

  defp satisfied_fact(%Condition{} = condition, %Fact{} = fact) do
    Fact.new(
      value: :satisfied,
      ancestry: {condition.hash, fact.hash},
      runnable: {condition, fact}
    )
  end
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
    result = Steps.run(step.work, fact.value)

    result_fact =
      Fact.new(value: result, ancestry: {step.hash, fact.hash}, runnable: {step, fact})

    next_runnables =
      workflow
      |> Workflow.next_steps(step)
      |> Enum.map(&{&1, result_fact})

    workflow
    |> Workflow.log_fact(result_fact)
    |> Workflow.add_to_agenda(next_runnables)
    |> Workflow.prune_activated_runnable(step, fact)
  end
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
      Map.get(workflow.activations, fact.hash) |> IO.inspect(label: "activations so far")

    IO.inspect(conj.condition_hashes, label: "required to activate #{conj.hash}")

    if Enum.all?(conj.condition_hashes, &(&1 in satisfied_conditions)) do
      IO.inspect(conj.hash, label: "is satisfied")

      conjunction_satisfied_fact =
        Fact.new(value: :satisfied, ancestry: {conj.hash, fact.hash}, runnable: {conj, fact})

      next_runnables =
        workflow
        |> Workflow.next_steps(conj)
        |> Enum.map(&{&1, fact})

      workflow
      |> Workflow.log_fact(conjunction_satisfied_fact)
      |> Workflow.add_to_agenda(next_runnables)
      |> Workflow.prune_activated_runnable(conj, fact)
    else
      Workflow.prune_activated_runnable(workflow, conj, fact)
    end
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
      with true <- ma.memory_assertion.(workflow.memory) do
        memory_assertion_satisfied_fact =
          Fact.new(value: :satisfied, ancestry: {ma.hash, fact.hash}, runnable: {ma, fact})

        next_runnables =
          workflow
          |> Workflow.next_steps(ma)
          |> Enum.map(&{&1, fact})

        workflow
        |> Workflow.log_fact(memory_assertion_satisfied_fact)
        |> Workflow.add_to_agenda(next_runnables)
        |> Workflow.prune_activated_runnable(ma, fact)
      else
        _anything_otherwise -> Workflow.prune_activated_runnable(workflow, ma, fact)
      end
    end
  end

  defimpl Dagger.Workflow.Activation, for: Dagger.Workflow.StateReactor do
    alias Dagger.Workflow

    alias Dagger.Workflow.{
      Fact,
      Steps,
      StateReactor
    }

    @spec activate(%Dagger.Workflow.StateReactor{}, Dagger.Workflow.t(), Dagger.Workflow.Fact.t()) ::
            Dagger.Workflow.t()
    def activate(
          %StateReactor{} = sr,
          %Workflow{} = workflow,
          %Fact{} = fact
        ) do
      # get last known state of this reactor or use init
      last_known_state = last_known_state(workflow, sr) || init_fact(sr)

      next_state = apply(sr.reactor, [fact.value, last_known_state.value])

      next_state_produced_fact =
        Fact.new(value: next_state, ancestry: {sr.hash, fact.hash}, runnable: {sr, fact})

      next_runnables =
        workflow
        |> Workflow.next_steps(sr)
        |> Enum.map(&{&1, next_state_produced_fact})

      workflow
      |> Workflow.log_fact(next_state_produced_fact)
      |> Workflow.add_to_agenda(next_runnables)
      |> Workflow.prune_activated_runnable(sr, fact)
    end

    defp last_known_state(workflow, state_reactor) do
      workflow.memory
      |> Graph.out_edges(state_reactor.hash)
      |> Enum.filter(&(&1.label == :produced and &1.generation == workflow.generation - 1))
      |> List.first(%{})
      |> Map.get(:v1)
    end

    defp init_fact(%StateReactor{init: init, hash: hash}),
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
          %Fact{ancestry: {parent_hash, _value_hash}} = fact
        ) do
      with true <- Enum.all?(join.joins, &(&1 in Graph.neighbors(workflow.memory, join.hash))) do
        # for each required parent in :joins build a map of `parent -> fact` by grabbing the
        # facts for the current generation
        join_bindings =
          Enum.reduce(join.joins, %{parent_hash => fact}, fn step_hash, acc ->
            Map.put_new(acc, step_hash, Workflow.get_current_generation_fact(workflow, step_hash))
          end)

        join_bindings_fact =
          Fact.new(value: join_bindings, ancestry: {join.hash, fact.hash}, runnable: {join, fact})

        next_runnables =
          workflow
          |> Workflow.next_steps(join)
          |> Enum.map(&{&1, fact})

        workflow
        |> Workflow.log_fact(join_bindings_fact)
        |> Workflow.add_to_agenda(next_runnables)
        |> Workflow.prune_activated_runnable(join, fact)
      else
        _otherwise ->
          Workflow.prune_activated_runnable(workflow, join, fact)
      end
    end
  end
end
