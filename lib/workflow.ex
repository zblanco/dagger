defmodule Dagger.Workflow do
  @moduledoc """
  Dagger Workflows are used to compose many branching steps, rules and accumuluations/reductions
  at runtime for lazy or eager evaluation.

  You can think of Dagger Workflows as a recipe of rules that when fed a stream of facts may react.

  The Dagger.Flowable protocol facilitates a `to_workflow` transformation so expressions like a
    Rule or an Accumulator may become a Workflow we can evaluate and compose with other workflows.

  Any Workflow can be merged into another Workflow and evaluated together. This gives us a lot of flexibility
  in expressing abstractions on top of Dagger workflow constructs.

  Dagger Workflows are intended for use cases where your program is built or modified at runtime. If model can be expressed in advance with compiled code using
  the usual control flow and concurrency tools available in Elixir/Erlang - Dagger Workflows are not the tool
  to reach for. There are performance trade-offs of doing more compilation and evaluation at runtime.

  Dagger Workflows are useful for building complex data dependent pipelines, expert systems, and user defined
  logical systems. If you do not need that level of dynamicism - Dagger Workflows are not for you.

  A Dagger Workflow supports lazy evaluation of both conditional (left hand side) and steps (right hand side).
  This allows a runtime implementation to distribute work to infrastructure specific to their needs
  independently of the model expressed. For example a Dagger "Runner" implementation may want to use a Dynamically Supervised
  GenServer, with cluster-aware registration for a given workflow, then execute conditionals eagerly, but
  execute actual steps with side effects lazily as a GenStage pipeline with backpressure has availability.
  """
  alias Dagger.Workflow.{
    Rule,
    Step,
    Steps,
    Fact,
    Activation,
    Agenda,
    Condition,
    Root
  }

  @type t() :: %__MODULE__{
          name: String.t(),
          flow: Graph.t(),
          hash: binary(),
          activations: any(),
          facts: list(),
          agenda: Agenda.t(),
          steps_executed: integer(),
          phases: integer(),
          generations: integer(),
          epochs: integer()
        }

  @type runnable() :: {fun(), term()}

  @enforce_keys [:name]

  defstruct name: nil,
            steps_executed: 0,
            phases: 0,
            generations: 0,
            epochs: 0,
            hash: nil,
            flow: nil,
            activations: nil,
            memory: nil,
            runnables: %{},
            facts: [],
            agenda: nil

  @typedoc """
  A discrimination network of conditions, and steps, built from composites such as rules and accumulations.
  """
  @type flow() :: Graph.t()

  @doc """
  Constructor for a new Dagger Workflow.
  """
  def new(name) when is_binary(name) do
    new(name: name)
  end

  def new(params) when is_list(params) do
    flow =
      Graph.new(vertex_identifier: &Steps.vertex_id_of/1)
      |> Graph.add_vertex(root(), :root)

    struct!(__MODULE__, params)
    |> Map.put(:flow, flow)
    |> Map.put(:activations, %{})
    |> Map.put(:memory, Graph.new(vertex_identifier: &Steps.vertex_id_of/1))
    |> Map.put(:agenda, Agenda.new())
  end

  def new(params) when is_map(params) do
    new(Map.to_list(params))
  end

  def root(), do: %Root{}

  # plan: cycle through a single phase of match/lhs/conditionals
  # plan_eagerly: cycle through matches until only step/rhs runnables are ready

  # react: plan_eagerly through lhs, then do one phase of rhs runnables
  # react_eagerly: cycle through lhs eagerly like react, but also any subsequent phases of rhs runnables

  @doc """
  Cycles eagerly through a prepared agenda in the match phase.
  """
  def react(%__MODULE__{generations: generations} = wrk) when generations > 0 do
    Enum.reduce(next_runnables(wrk), wrk, fn {node, fact}, wrk ->
      Activation.activate(node, wrk, fact)
    end)
  end

  @doc """
  Plans eagerly through the match phase then executes a single cycle of right hand side runnables.
  """
  def react(%__MODULE__{} = wrk, %Fact{ancestry: nil} = fact) do
    react(Activation.activate(root(), wrk, fact))
  end

  def react(%__MODULE__{} = wrk, raw_fact) do
    react(wrk, Fact.new(value: raw_fact))
  end

  @doc """
  Cycles eagerly through runnables resulting from the input fact.

  Eagerly runs through the planning / match phase as does `react/2` but also eagerly executes
  subsequent phases of runnables until satisfied (nothing new to react to i.e. all
  terminating leaf nodes have been traversed to and executed) resulting in a fully satisfied agenda.

  `react_until_satisfied/2` is good for nested step -> [child_step_1, child_step2, ...] dependencies
  where the goal is to get to the results at the end of the pipeline of steps.

  One should be careful about using react_until_satisfied with infinite loops as evaluation will not terminate.

  If your goal is to evaluate some non-terminating program to some finite number of generations - wrapping
  `react/2` in a process that can track workflow evaluation livecycles until desired is recommended.
  """
  def react_until_satisfied(%__MODULE__{} = wrk, %Fact{ancestry: nil} = fact) do
    wrk
    |> react(fact)
    |> react_until_satisfied()
  end

  def react_until_satisfied(%__MODULE__{} = wrk, raw_fact) do
    react_until_satisfied(wrk, Fact.new(value: raw_fact))
  end

  def react_until_satisfied(%__MODULE__{} = workflow) do
    do_react_until_satisfied(workflow, is_runnable?(workflow))

    # Enum.reduce_while(next_runnables(workflow), workflow, fn {node, fact} = _runnable, wrk ->
    #   wrk = Activation.activate(node, wrk, fact)

    #   next_runnables(wrk) |> IO.inspect(label: "next_runnables inside reduce")
    #   is_runnable?(wrk) |> IO.inspect(label: "is_runnable?")

    #   if is_runnable?(wrk) do
    #     {:cont, wrk}
    #   else
    #     {:halt, wrk}
    #   end
    # end)
  end

  defp do_react_until_satisfied(%__MODULE__{} = workflow, true = _is_runnable?) do
    workflow =
      Enum.reduce(next_runnables(workflow), workflow, fn {node, fact} = _runnable, wrk ->
        Activation.activate(node, wrk, fact)
      end)

    do_react_until_satisfied(workflow, is_runnable?(workflow))
  end

  defp do_react_until_satisfied(%__MODULE__{} = workflow, false = _is_runnable?), do: workflow

  @doc """
  For a new set of inputs, `plan/2` prepares the workflow agenda for the next set of reactions by
  matching through left-hand-side conditions in the workflow network.

  For an inference engine's match -> select -> execute phase, this is the match phase.

  Dagger Workflow evaluation is forward chaining meaning from the root of the graph it starts
    by evaluating the direct children of the root node. If the workflow has any sort of
    conditions (from rules, etc) these conditions are prioritized in the agenda for the next cycle.

  Plan will always match through a single level of nodes and identify the next runnable activations
  available.
  """
  def plan(%__MODULE__{} = wrk, %Fact{} = fact) do
    Activation.activate(root(), wrk, fact)
  end

  def plan(%__MODULE__{} = wrk, raw_fact) do
    plan(wrk, Fact.new(value: raw_fact))
  end

  @doc """
  `plan/1` will, for all next left hand side / match phase runnables, activate the next layer - preparing the next layer if necessary.
  """
  def plan(%__MODULE__{} = wrk) do
    wrk
    |> next_match_runnables()
    |> Enum.reduce(wrk, fn {node, fact}, wrk ->
      Activation.activate(node, wrk, fact)
    end)
  end

  @doc """
  What is the eager planning strategy?

  Cycle through the workflow activations until all conditional / lhs activate.

  Goal? To determine if the workflow is runnable once terminated to only Step runnables.
  """
  def plan_eagerly(%__MODULE__{} = workflow, %Fact{} = input_fact) do
    workflow
    |> plan(input_fact)
    |> activate_through_possible_matches()
  end

  def plan_eagerly(%__MODULE__{} = wrk, raw_fact) do
    plan_eagerly(wrk, Fact.new(value: raw_fact))
  end

  defp activate_through_possible_matches(wrk) do
    activate_through_possible_matches(
      wrk,
      next_match_runnables(wrk),
      any_match_phase_runnables?(wrk)
    )
  end

  defp activate_through_possible_matches(
         wrk,
         next_match_runnables,
         _any_match_phase_runnables? = true
       ) do
    Enum.reduce(next_match_runnables, wrk, fn {node, fact}, wrk ->
      Activation.activate(node, wrk, fact)
      |> activate_through_possible_matches()
    end)
  end

  defp activate_through_possible_matches(
         wrk,
         _match_runnables,
         _any_match_phase_runnables? = false
       ) do
    # IO.inspect(conditions(wrk), label: "possible conditions")
    wrk
  end

  defp any_match_phase_runnables?(%__MODULE__{memory: memory, generations: generation}) do
    generation_fact = fact_for_generation(memory, generation)

    memory
    |> Graph.out_edges(generation_fact)
    |> Enum.any?(fn edge ->
      edge.label == :matchable
    end)
  end

  # def is_runnable?(%__MODULE__{agenda: agenda}) do
  #   Agenda.any_runnables_for_next_cycle?(agenda)
  # end

  def is_runnable?(%__MODULE__{memory: memory}) do
    # generation_fact = fact_for_generation(memory, generation)

    memory
    |> Graph.edges()
    |> Enum.any?(fn edge ->
      edge.label == :runnable
    end)

    # memory
    # |> Graph.out_edges(generation_fact)
    # |> Enum.any?(fn edge ->
    #   edge.label == :runnable and
    #     not Enum.any?(Graph.out_edges(memory, edge.v2), &(&1.label == :produced))
    # end)
  end

  def can_react?(%__MODULE__{memory: memory, generations: generation}) do
    generation_fact = fact_for_generation(memory, generation)

    memory
    |> Graph.out_edges(generation_fact)
    |> Enum.any?(fn edge ->
      (edge.label == :runnable or
         edge.label == :matchable) and
        not Enum.any?(
          Graph.out_edges(memory, edge.v2),
          &(&1.label == :produced or &1.label == :satisfied)
        )
    end)
  end

  def prune_activated_runnable(%__MODULE__{agenda: agenda} = wrk, node, fact) do
    %__MODULE__{
      wrk
      | agenda: Agenda.prune_runnable(agenda, node, fact)
    }
  end

  def draw_connection(%__MODULE__{memory: memory} = wrk, node_1, node_2, connection) do
    %__MODULE__{wrk | memory: Graph.add_edge(memory, node_1, node_2, label: connection)}
  end

  def log_fact(%__MODULE__{facts: facts, memory: memory} = wrk, %Fact{} = fact) do
    %__MODULE__{wrk | facts: [fact | facts], memory: Graph.add_vertex(memory, fact)}
  end

  @spec prepare_next_generation(Workflow.t(), Fact.t()) :: Workflow.t()
  @doc false
  def prepare_next_generation(%__MODULE__{} = workflow, fact) do
    next_generation = workflow.generations + 1

    workflow
    |> Map.put(:generations, next_generation)
    |> draw_connection(fact, next_generation, :generation)
  end

  @spec prepare_next_runnables(Workflow.t(), any(), Fact.t()) :: any
  @doc false
  def prepare_next_runnables(%__MODULE__{} = workflow, node, fact) do
    workflow
    |> next_steps(node)
    |> Enum.reduce(workflow, fn step, wrk ->
      draw_connection(wrk, fact, step.hash, connection_for_activatable(step))
    end)
  end

  # considering an alternate activation protocol that defers the connection labeling transitions to the implementer - this is just a "make it work" solution
  defp connection_for_activatable(step) do
    case Activation.match_or_execute(step) do
      :match -> :matchable
      :execute -> :runnable
    end
  end

  @doc false
  def mark_runnable_as_ran(%__MODULE__{memory: memory} = workflow, step, fact) do
    memory =
      case Graph.update_labelled_edge(memory, fact, step.hash, connection_for_activatable(step),
             label: :ran
           ) do
        %Graph{} = memory -> memory
        {:error, :no_such_edge} -> memory
      end

    %__MODULE__{
      workflow
      | memory: memory
    }
  end

  @doc false
  def satisfied_conditions(%__MODULE__{memory: memory}, %Fact{} = fact) do
    for %Graph.Edge{} = edge <- Graph.out_edges(memory, fact),
        edge.label == :satisfied,
        do: edge.v2
  end

  @spec add_to_agenda(Workflow.t(), maybe_improper_list) :: Workflow.t()
  def add_to_agenda(%__MODULE__{agenda: agenda} = wrk, runnables) when is_list(runnables) do
    %__MODULE__{
      wrk
      | agenda:
          Enum.reduce(runnables, agenda, fn runnable, agenda ->
            agenda
            |> Agenda.add_runnable(runnable)
            |> Agenda.next_cycle()
          end)
    }
  end

  @spec raw_reactions(Dagger.Workflow.t()) :: list(any())
  @doc """
  Returns raw (output value) side effects of the workflow - i.e. facts resulting from the execution of a Dagger.Step
  """
  def raw_reactions(%__MODULE__{} = wrk) do
    wrk
    |> reactions()
    |> Enum.map(& &1.value)
  end

  @spec reactions(Dagger.Workflow.t()) :: list(Dagger.Workflow.Fact.t())
  @doc """
  Returns raw (output value) side effects of the workflow - i.e. facts resulting from the execution of a Dagger.Step
  """
  def reactions(%__MODULE__{} = wrk) do
    wrk.facts
  end

  @spec facts(Dagger.Workflow.t()) :: list(Dagger.Workflow.Fact.t())
  @doc """
  Lists facts produced in the workflow so far.
  """
  def facts(%__MODULE__{} = wrk), do: wrk.facts

  @spec matches(Dagger.Workflow.t()) :: list(Dagger.Workflow.Fact.t())
  def matches(%__MODULE__{memory: memory, generations: generation}) do
    current_generation_fact = fact_for_generation(memory, generation)

    for %Graph.Edge{} = edge <- Graph.out_edges(memory, current_generation_fact),
        edge.label == :matchable do
      edge.v2
    end
  end

  @spec next_runnables(Dagger.Workflow.t()) :: list({any(), Dagger.Workflow.Fact.t()})
  @doc """
  Returns a list of the next {node, fact} i.e "runnable" pairs ready for activation in the next cycle.

  All Runnables returned are independent and can be run in parallel then fed back into the Workflow
  without wait or delays to get the same results.
  """
  def next_runnables(%__MODULE__{flow: flow, memory: memory}) do
    # we can't just traverse this far - we also need to traverse to the last fact
    # current_generation_fact = fact_for_generation(memory, generation)

    # for %Graph.Edge{} = edge <- Graph.out_edges(memory, current_generation_fact),
    # danger for big graphs - need a cursor left from last ops - some way to filter over less
    for %Graph.Edge{} = edge <- Graph.edges(memory),
        edge.label == :runnable do
      {Map.get(flow.vertices, edge.v2), edge.v1}
    end
  end

  defp next_match_runnables(%__MODULE__{flow: flow, memory: memory, generations: generation}) do
    current_generation_fact = fact_for_generation(memory, generation)

    for %Graph.Edge{} = edge <- Graph.out_edges(memory, current_generation_fact),
        edge.label == :matchable do
      {Map.get(flow.vertices, edge.v2), current_generation_fact}
    end
  end

  defp fact_for_generation(memory, generation) do
    memory
    |> Graph.in_neighbors(generation)
    |> List.first()
  end

  # def next_match_runnables(%__MODULE__{agenda: agenda}), do: Agenda.next_match_runnables(agenda)

  def next_steps(%__MODULE__{flow: flow}, parent_step) do
    next_steps(flow, parent_step)
  end

  def next_steps(%Graph{} = flow, parent_step) do
    Graph.out_neighbors(flow, parent_step)
  end

  @doc """
  Adds a rule to the workflow. A rule's left hand side (condition) is a runnable which should return booleans.

  In some cases the condition is in multiple parts and some of the conditional clauses already exist as steps
  in which case we add the sub-clause(s) of the condition that don't exist as a dependent step to the conditions
  that do exist and add the reaction step to the sub-conditions.
  """
  def add_rule(
        %__MODULE__{} = workflow,
        %Rule{} = rule
      ) do
    workflow_of_rule = Dagger.Flowable.to_workflow(rule)
    merge(workflow, workflow_of_rule)
  end

  @doc """
  Merges the second workflow into the first maintaining the name of the first.
  """
  def merge(%__MODULE__{flow: flow} = workflow, %__MODULE__{flow: flow2}) do
    %__MODULE__{
      workflow
      | flow:
          flow2
          |> Graph.out_neighbors(%Root{})
          |> Enum.reduce(flow, fn v, into_flow ->
            do_merge(into_flow, flow2, v, %Root{})
          end)
    }
  end

  defp do_merge(into_flow, from_flow, steps, parent) when is_list(steps) do
    Enum.reduce(steps, into_flow, fn step, flow ->
      do_merge(flow, from_flow, step, parent)
    end)
  end

  defp do_merge(into_flow, from_flow, step, %Root{} = parent) do
    into_flow
    |> Graph.add_vertex(step, Graph.vertex_labels(from_flow, step))
    |> Graph.add_edge(parent, step, label: {:root, step.hash})
    |> do_merge(from_flow, next_steps(from_flow, step), step)
  end

  defp do_merge(into_flow, from_flow, step, parent) do
    into_flow
    |> Graph.add_vertex(step, Graph.vertex_labels(from_flow, step))
    |> Graph.add_edge(parent, step, label: edge_label(from_flow, parent, step))
    |> do_merge(from_flow, next_steps(from_flow, step), step)
  end

  defp edge_label(g, v1, v2) do
    edge = Graph.edge(g, v1, v2)

    unless is_nil(edge) do
      edge |> Map.get(:label)
    else
      {v1.hash, v2.hash}
    end
  end

  @doc """
  Adds a step to the root of the workflow that is always evaluated with a new fact.
  """
  def add_step(%__MODULE__{} = workflow, child_step) when is_function(child_step) do
    add_step(workflow, %Root{}, Step.new(work: child_step))
  end

  def add_step(%__MODULE__{} = workflow, child_step) do
    add_step(workflow, %Root{}, child_step)
  end

  @doc """
  Adds a dependent step to some other step in a workflow by name.

  The dependent step is fed signed facts produced by the parent step during a reaction.

  Adding dependent steps is the most low-level way of building a dataflow execution graph as it assumes no conditional, branching logic.

  If you're just building a pipeline, dependent steps can be sufficient, however you might want Rules for conditional branching logic.
  """
  def add_step(%__MODULE__{flow: flow} = workflow, %Root{}, %{} = child_step) do
    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(child_step, child_step.hash)
          |> Graph.add_edge(%Root{}, child_step, label: {%Root{}, child_step.hash})
    }
  end

  def add_step(%__MODULE__{flow: flow} = workflow, %{} = parent_step, %{} = child_step) do
    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(child_step, to_string(child_step.hash))
          |> Graph.add_edge(parent_step, child_step,
            label: {to_string(parent_step.hash), to_string(child_step.hash)}
          )
    }
  end

  def add_step(%__MODULE__{} = workflow, parent_steps, %{} = child_step)
      when is_list(parent_steps) do
    Enum.reduce(parent_steps, workflow, fn parent_step, wrk ->
      add_step(wrk, parent_step, child_step)
    end)
  end

  def add_step(%__MODULE__{} = workflow, parent_step_name, child_step) do
    case get_step_by_name(workflow, parent_step_name) do
      {:ok, parent_step} ->
        add_step(workflow, parent_step, child_step)

      {:error, :step_not_found} ->
        {:error, "A step named #{parent_step_name} was not found"}
    end
  end

  @doc """
  Lists all steps in the workflow.
  """
  def steps(%__MODULE__{flow: flow}) do
    Enum.filter(Graph.vertices(flow), &match?(%Step{}, &1))
  end

  def conditions(%__MODULE__{flow: flow}) do
    Enum.filter(Graph.vertices(flow), &match?(%Condition{}, &1))
  end

  # def add_workflow(%__MODULE__{flow: flow} = parent_workflow, parent_connector_step_or_hash_or_step_name, %__MODULE__{flow: child_flow} = child_workflow) do
  #   # how would we merge two workflow graphs? do we have to?
  #   #
  # end

  @doc """
  Fetches a step from the workflow provided the unique name.

  Returns an error if a step by the name given is not found.
  """
  def get_step_by_name(_workflow, %Root{}), do: {:ok, %Root{}}

  def get_step_by_name(%__MODULE__{flow: flow}, step_name) do
    case flow
         # we'll want map access time index on work function hashes to make this fast
         |> Graph.vertices()
         |> Enum.find(
           {:error, :step_not_found},
           fn
             %Step{name: name} -> step_name == name
             %Root{} -> false
           end
         ) do
      {:error, _} = error -> error
      step -> {:ok, step}
    end
  end

  # @doc """
  # Adds an accumulator to a Workflow.

  # `Dagger.Accumulators` are used to collect some state for which to make further decision upon.

  # You can think of an accumulator as a set of reducer functions that react over a shared state.

  # See the `Dagger.Accumulator module` for more details.
  # """
  # def add_accumulator(%__MODULE__{} = workflow, accumulator) do
  #   %Accumulator{init: init, reducers: reducers} = accumulator

  #   Enum.reduce(reducers, add_rule(workflow, init), fn reducer, workflow ->
  #     add_rule(workflow, reducer)
  #   end)
  # end
end
