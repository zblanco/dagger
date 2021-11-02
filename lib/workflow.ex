defmodule Dagger.Workflow do
  @moduledoc """
  Dagger Workflows are used to compose many branching steps, rules and accumuluations/reductions
  at runtime for lazy or eager evaluation.

  You can think of Dagger Workflows as a recipe of rules that when fed a stream of facts may react.

  A Workflow is usually made out of one or more Rules or other datastructures which implement the `Dagger.Runnable` protocol.

  The Dagger.Runnable protocol facilitates a `to_workflow` transformation such that expressions like a
    Rule or an Accumulator may be composed into a single evaluatable datastructure (a %Workflow{}).

  Any Workflow can be merged into another Workflow and evaluated together. This allows for extension
  of domain specific entities which can simply implement the Runnable protocol to be composed with other
  runnables at runtime.

  Dagger Workflows are intended for use cases where constraints, rules, and or a "workflow" must be
  constructed and evaluated at runtime. If your use case can be modeled upfront in compiled code using
  the usual control flow and concurrency tools available in Elixir/Erlang - Dagger Workflows are not the tool
  to reach for. There are performance trade-offs of doing more compilation and evaluation at runtime.

  Dagger Workflows are useful for building complex data dependent pipelines, expert systems, and user defined
  logical systems. If you do not need that level of dynamicism - Dagger Workflows are not for you.

  A Dagger Workflow supports lazy evaluation of both conditional (left hand side) and steps (right hand side).
  This allows a runtime implementation to distribute work to infrastructure specific to their needs
  independently of the model expressed. For example a Runner implementation may want to use a Dynamically Supervised
  GenServer, with cluster-aware registration for a given workflow, then execute conditionals eagerly, but
  execute actual steps with side effects lazily as a GenStage pipeline with backpressure has availability.

  <!-- rewrite -->
  While the abstraction isn't entirely clear yet, execution of a Dagger Runnable by a Dagger.Runner could perform
  a two-step, acknowledgement flow transaction on the Workflow graph to protect against double execution for imperative side effects.

  In the case that another process with the same workflow identity, or an older version of the workflow
    is providing a command we don't want to run - we can react as needed.

  We can do this by deterministically signing the reaction by a combination of the stream version of the state its
    consumed and the hash of the workflow's definition. This allows the execution / runner side of the
    workflow an option to handle distributed issues custom to its environment.

  Facts might be reactions in the model that are added to the Workflow Stream to again trigger potentially more reactions.

  Facts might also be external inputs that may trigger additional reactions.

  A Dagger Runnable is protocol implementing Step or Pipeline (no conditional branching) that runs in some step-wise fashion provided an input stream.

  Using Dagger Runnables inside a Dagger Workflow enables conditional, branching logic in the stream processing pipeline.
  Workflows are implemented as a Directed Acyclic Graph constrained with and/or nodes.

  Because something like a Dagger workflow is so abstract, use it only when you need that runtime
    configurability of an operation. This is usually in cases where non-developers need to make
    decisions of the execution path to follow. If it's a requirement to take developer 'need-to-know'
    out of the equation it might be worth considering some of these patterns. Otherwise you're
    better off with the expressiveness of vanilla elixir for that feature.

  ## API Goals

  * Don't expose that the underlying structure is a graph
    * It should feel like business logic with introspective/query properties of the graph
    * We can use LibGraph to export to a readable graph format for visualization though.
      * That means include labels/descriptions in nodes.
  * Clearly describe what the workflow will proceed like through a pipeline constructor of the Workflow

  ## Possible API?

  ```elixir
  alias Dagger.{Workflow, Step}

  params = "%{key: "value"}"

  workflow =
    Workflow.new(name: "example")
    |> Workflow.add_rule() # sets the root condition
    |> Workflow.add_rule(name: "", reaction: MyRunnableCommand.new(params))
  ```

  ## Notes

  The graph structure doesn't have to correlate to the API or the business logic visibly.
  For example a rule is a predicate of which may be a few conditions bound by AND/OR connections that evaluate to a reaction.
  The structure of the graph is made for evaluation of facts in the workflow at runtime. Read models of the graph shouldn't impose
  on the runtime evaluation. One potential optimization we don't want to accidentally prevent signed substructures of the graph.
  As the flow graph is given facts it might produce signed evaluations of the parent structure such that only the child nodes need evaluation
  because the parents have been consumed. That way we only need a hashed version of the parent in addition to just the necessary network of
  evaluatable nodes for inputs. The idea being we only build the needed pieces of the network in memory. Essentially we're introducing Merkle-DAG properties
  to a rule-based knowledge workflow.

  What we want is that given an event stream for the construction of the workflow and an event stream for the facts all reactions from the
  workflow are deterministic. This is a challenging abstraction in many ways because we're attempting to encapsulate interactions of both
  state accumulations, rules, step-wise job dependencies, and eventsourcing.

  A runtime layer might dynamically spin up processes responsible for a subset of a graph that branch into patterns that consume subsets of facts
    or for each accumulation. It's possible a single GenServer could operate the whole graph in a naive runtime.

  ## Workflow Composition and Abstraction

  In most cases a user won't really be writing individual rules by hand, but composing high level sets of rules, accumulators,
   and step pipelines together. For example for a business process you probably don't want to hand-write an approval process every time.
   Just fill out a wizard that builds an approval process into your model for you.

  From a DDD perspective both Commands and Events are Facts fed into a workflow. Process Managers and Aggregates are accumulators with rules
    that react by publishing commands or events in response to changes in state and external events.

  * Event-Handling:
    * An event is a fact representing a conclusion made in the network.
      Like all facts it is signed based on the fact-stream consumed and the workflow definition.
    * The reaction of an event handler can be a Command (Signed intent to cause additional reactions in a workflow) or a side-effect to a query model.
    * In many cases the event handling rules are an `IS A` form where you're matching on the Struct/Module name of the event.
  * Command-Handling:
    * Command handling is done in a two-step transaction phase so any accumulations or facts generated from a command can be rejected if the
      model the command was evaluated with is an old or invalid version of the workflow.
  * State Accumulation:
    * Facts of any kind (events or commands) can be used to accumulate state that can then be used to evaluate into more reactions.
    * State accumulation is a set of patterns matched to facts that are reduced with prior state and result in `state-produced` events/reactions.
    * Events of accumulated state are then matched on additional rules.

  The above capabilities allow for all design patterns used in a CQRS + EventSourcing architecture such as Aggregates and Process Managers.

  An Aggregate is a transaction boundary that consumes commands, might accumulate state, and reacts with serialized domain events.

  The transactional boundary capabilities of an aggregate are usually AND connections between a `state-produced` event and a `command` fact
    for a given identity.

  On the other side we have Process Managers which handle events, accumulate state, and react with signed commands.

  So a stateless pattern is simply an ISA match on a fact and a stateful pattern is two ISA matches connected via an AND clause.
  i.e. we want the current state to be X and for Y fact to have occured for Z reaction to be produced.

  Side effects such as an email notification of a successful payment transaction that need 'only-once' delivery with a guarantee
    occur in a two step procedure requiring acknowledgement. Acknowledgement requires state of some kind which also allows retry
    capabilities. So a simple side-effect workflow is a notification delivery without state (weaker guarantees) wheras a something like a
    financial transaction necessitates state control. The idea of using workflow graphs is that we can lift these simple capabilities
    into general patterns that can be composed together without programmer -> compiler interactions.

  For the trickier bits a programmer can still write their own workflows and functions while making them available to non-programmers.

  In most cases these Workflow abstractions are a building block for a programmer to set constraints as to what non-programmers can do themselves.

  This isn't a "no-code" tool. This is a "some-no-code-when-needed-by-the-business-requirements" tool. Usually that's when the domain knowledge
  that has to be represented is so extensive that any developer would be a bottleneck trying to convert rules into code.

  ## Facts

  Any reaction produced by a workflow graph must follow a `to_fact` protocol. The `to_fact` protocol requires a conversion from whatever
  data produced from running an input against some function in the workflow into a `%Fact{}` struct. Fact structs must have keys
  such as the hash representation of the subset workflow that produced it as well as the stream(s) of events that contributed to its state.

  The point of hashing facts is that it's deterministic about its result. **Given access to the data streams and workflow definition
    we can take a fact and reverse the steps that produced it to see what a state is at any given time.**

  ## Rules and Logic

  Rules are a set of conditions that match to facts and connect to actions that can trigger further reactions. ~~Rules and conditions with connections
   made with AND/OR clauses by default require some accumulation of state for each separate fact.
   When a workflow with AND/OR connections is being compiled into a runtime
   representation a rule with a variety of AND/OR conditions will turn into an Accumulator definition that has a series of matches on raw facts
   as well as `state-produced` facts of its own accumulator.~~

  ** NOTE `state-changed` or `state-produced` ?

  ## Patterns of workflows

  As we mentioned all of "components" that one might work with in DDD can be modeled as a workflow graph.

  As programmers we don't always want to rewrite the specifics of our code. We want to lift common patterns and abstractions out so they're
  re-usable. Dagger Workflows are intended to do just that by separating out the workflow definition into data and making the execution identity
  arbitrary in both location and time.

  What this means is that we can build higher level APIs for the composition of a pattern like an Aggregate where the constraints of what an
  Aggregate must contain is enforced. The actual wiring of connecting some stream of `state-produced` events to conditions of more subsequent
  command facts is handled for you under the hood. You just have to meet some the constraints expressed by an aggregate's contract.

  Okay, this sounds familiar. Why can't we just use behaviours and inject common capabilities through a `__using__` macro? We could. But if
  we want to write an aggregate at runtime, enforce its constraints and run it against live data without involving a programmer; requiring
  code compilation won't suffice. There are many business rules/scenarios/use-cases where involving a programmer's time is much too costly.

  So at the bottom layer of the abstraction we have facts that feed into a model at runtime and produce reactions.

  At a another level we have abstract patterns of how different subsets of conditions, accumulations, and reactions fit together like an
  Aggregate or a Process Manager.

  Finally we might have even higher level abstractions that could be shared and re-used across different workflows such as "approval processes"
  where some authorized individual has to acknowledge a step before it can proceed. A business user building out a new procedure doesn't have
  to wire together low-level concerns like fact streams and identities of a model, but instead just point and clicks together existing components
  that are just workflow specifications that fit together into a larger model.

  This compositionality extending into a declarative, point-and-click space lets programmers build base domain abstractions like file-management
  and business users can compose that functionality to do things like requiring a contract document to be uploaded and approved by someone prior
  to some costly fulfillment process of that contract.

  Especially in Service industries where the product sold is a specification for skilled labor (like an Electrician installing some equipment)
  the specification of work is highly variable. A tool like Dagger could be useful in specifying the procedures and contraints to prevent mistakes.

  ## Runtime Optimizations

  The runtime execution is separate from the specification of Workflows. Combined with merkle properties of hashing together
  definitions and subsets of a workflow we can enable quite a few optimizations at runtime. For example in most rule-based expert systems
  the performance bottlenecks comes from evaluating matching conditions against new facts. The state space of potentially matching
  conditions can grow quite a bit and become a performance concern in both evaluation and memory usage.

  By hashing a workflow node as a composition of its children we might do things like exclude already executed or "will-never-execute"
  paths from evaluation. In addition since we have the runtime expressivity of the BEAM we could spin up processes which can run concurrently
  to match different subsets of facts and feed into already active processes for accumulation and reactions. In a way a workflow definition
  is a contract of runtime behaviours separate from the runtime model so whatever topology of processes works best for a given system
  architecture or scale can be used.

  Granted there is so many stateful behaviors happening at runtime Dagger Workflows and Runners are likely to need a lot of generative testing.

  Finally in many cases rules have the same conditions as other rules. In those cases you don't want separate processes handling the same fact
  as that results in unecessary copying of data, instead you want one process handling a fact, matching the shared condition and activating
  the separate reactions.

  As far as implementation goes I expect the generated runtime topologies to look a lot like what the [Flow]() library produces. In fact I suspect
  generating a Flow from a Workflow specification could be a good way to get highly optimized topologies without building the Genstage pipelines
  by hand for something so abstract.

  ## Notes and Possible Implementation Details:

  * We need to work on the Workflow Specification and base APIs for defining them first.
    * That means Steps and Facts, then Rules, then Accumulators in that order.

  * We also need to find a way to enforce contracts of the functions used in both conditions and reaction contexts.
    * Something like [Norm]() where we invoke `Norm.conform!` on the different pieces put together at runtime is a potential solution.
    * Essentially we need to make sure that the arrows of input -> output -> another_input -> another_output could possibly execute.
      * Spidey sense says there's a mountain of "you don't know what you don't know" in the compiler space and this is a hard problem

  ## Building a workflow

  Define the workflow

  Add rules to the workflow.

  Rules in a workflow match to Fact Streams.

  Fact Stream conditions are connected or grouped in the graph network to enable optimizations in process topology.

  The runtime layer can spawn processes of varying behaviours dynamically based on the dataflow of a fact stream and the topology of a workflow.

  Workflow rules, reactions, and accumulators can all publish facts. In a network of workflows others can subscribe to a stream.

  A stream is an identifier that can be used to get an ordered, immutable, stream of facts that a workflow has consumed or produced.

  A rule can subscribe to any number of fact streams of some subset of the workflow graph.

  A rule definition produces a fact stream identified by a hash of its conditions and reactions packaged with the data stream it consumes.

  A condition is a boolean expression that reacts to facts.

  ## Workflows are built with:

  ### Steps - pipeline / data flow dependency construct

  A Step accepts an input of a fact and returns a new fact.

  Developer's using Dagger write logic based on the data and Dagger wraps the inputs and outputs in Steps and Facts to handle Dagger specific plumbing.

  Most Steps should be deterministic, pure, functions whenever possible.

  It's recommended to put Condityions which provide checks prior to a non-deterministic step that may have side effects such as interacting with an external API.

  All potential side effects, pure or impure are returned  in the stream first as a Runnable so that a Runner might decide how or what guarantee to
    process the job with.

  input :: Stream<Fact>(id: hash-of-parent-work-function <> hash-of-data-produced)

  ## Facts

  When a step is given a fact, the return is always wrapped in a new Fact with metadata referencing the Runnable ancestry that produced it.

  Facts are used as Tokens to identify further activations in a workflow.

  ## Rules

  A pairing of one or more Conditions and dependent steps that are to be triggered when all the conditions are met.

  ## Accumulators

  Returns a :state_produced type fact.

  ** should we enforce a fact protocol? **

  Workflow.new()
  |> Workflow.add_step(my_rule)


  ## Network layers

  %Root{}
    - conditions
      - joins
        - steps

  Each node follows Runnable protocol. Runnables produce facts with ancestry or another runnable.

  Runnable Protocol: how a fact or more runnables are produced

  Activation Protocol: how a node in a workflow interacts during evaluation
  """
  alias Dagger.Workflow.{
    Rule,
    Accumulator,
    Step,
    Steps,
    Fact,
    Activation,
    Agenda,
    Runnable,
    Condition,
    Root
  }

  @type t() :: %__MODULE__{
          name: String.t(),
          flow: Graph.t(),
          hash: binary(),
          activations: any(),
          facts: list(),
          agenda: Agenda.t()
        }

  @type runnable() :: {fun(), term()}

  @enforce_keys [:name]

  defstruct name: nil,
            hash: nil,
            flow: nil,
            activations: nil,
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
    struct!(__MODULE__, params)
    |> Map.put(:flow, Graph.new() |> Graph.add_vertex(root(), :root))
    |> Map.put(:activations, %{})
    |> Map.put(:agenda, Agenda.new())
  end

  def new(params) when is_map(params) do
    new(Map.to_list(params))
  end

  defp root(), do: %Root{}

  # plan: cycle through a single phase of match/lhs/conditionals
  # plan_eagerly: cycle through matches until only step/rhs runnables are ready

  # react: plan_eagerly through lhs, then do one phase of rhs runnables
  # react_eagerly: cycle through lhs eagerly like react, but also any subsequent phases of rhs runnables

  @doc """
  Cycles eagerly through a prepared agenda in the match phase.
  """
  def react(%__MODULE__{agenda: %Agenda{cycles: cycles}} = wrk) when cycles > 0 do
    Enum.reduce(Map.values(wrk.agenda.runnables), wrk, fn {node, fact}, wrk ->
      Activation.activate(node, wrk, fact)
    end)
  end

  # def react(%__MODULE__{agenda: %Agenda{cycles: cycles}} = wrk) when cycles > 0 do
  #   Enum.reduce(Map.values(wrk.agenda.runnables), wrk, fn {node, fact}, wrk ->
  #     Activation.activate(node, wrk, fact)
  #   end)
  # end

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

  If your goal is to evaluate some non-terminating program to some finite number of cycles - wrapping
  `react/2` in a process that can track workflow evaluation cycles until some point is likely preferable.
  """
  def react_until_satisfied(%__MODULE__{} = wrk, %Fact{ancestry: nil} = fact) do
    wrk
    |> react(fact)
    |> react_until_satisfied()

    # react_until_satisfied(Activation.activate(root(), wrk, fact))
  end

  def react_until_satisfied(%__MODULE__{} = wrk, raw_fact) do
    react_until_satisfied(wrk, Fact.new(value: raw_fact))
  end

  def react_until_satisfied(%__MODULE__{} = workflow) do
    Enum.reduce_while(next_runnables(workflow), workflow, fn {node, fact} = _runnable, wrk ->
      wrk = Activation.activate(node, wrk, fact)

      if Agenda.any_runnables_for_next_cycle?(wrk.agenda) do
        {:cont, wrk}
      else
        {:halt, wrk}
      end
    end)
  end

  @doc """
  For a new set of inputs, `plan/2` prepares the workflow agenda for the next cycle of reactions by
  matching through left-hand-side conditions in the workflow network.

  For an inference engine's match -> select -> execute phase, this is the match phase.

  Dagger Workflow evaluation is forward chaining meaning from the root of the graph it starts
    by evaluating the direct children of the root node. If the workflow has any sort of
    conditions (from rules, etc) these conditions are prioritized in the agenda for the next cycle.
  """
  def plan(%__MODULE__{} = wrk, %Fact{} = fact) do
    Activation.activate(root(), wrk, fact)
  end

  # def plan(%__MODULE__{} = wrk, facts) when is_list(facts) do
  #   Enum.reduce(facts, wrk, fn fact, wrk ->
  #     plan(wrk, fact)
  #   end)
  # end

  def plan(%__MODULE__{} = wrk, raw_fact) do
    plan(wrk, Fact.new(value: raw_fact))
  end

  def plan(%__MODULE__{} = wrk) do
    wrk
    |> next_runnables()
    |> Enum.reduce(wrk, fn {node, fact}, wrk ->
      Activation.activate(node, wrk, fact)
    end)
  end

  @doc """
  What is the eager planning strategy?

  Cycle through the workflow activations until all conditional / lhs activate.

  Goal? To determine if the workflow is runnable once terminated to only Step runnables.
  """
  def plan_eagerly(%__MODULE__{} = wrk, %Fact{} = input_fact) do
    wrk = plan(wrk, input_fact)

    if Map.has_key?(wrk.activations, input_fact.hash) do
      plan(wrk)
    else
      wrk
    end
  end

  def plan_eagerly(%__MODULE__{} = wrk, raw_fact) do
    plan_eagerly(wrk, Fact.new(value: raw_fact))
  end

  def is_runnable?(%__MODULE__{agenda: agenda}) do
    Agenda.any_runnables_for_next_cycle?(agenda)
  end

  def prune_activated_runnable(%__MODULE__{agenda: agenda} = wrk, node, fact) do
    %__MODULE__{
      wrk
      | agenda: Agenda.prune_runnable(agenda, node, fact)
    }
  end

  def log_fact(
        %__MODULE__{activations: activations, facts: facts} = wrk,
        %Fact{value: :satisfied, ancestry: {condition_hash, fact_hash}} = fact
      ) do
    %__MODULE__{
      wrk
      | # do we ever want the inverse hash table (cond_hash, set<fact_hashe>) or both?
        activations: Map.put(activations, fact_hash, MapSet.new([condition_hash])),
        facts: [fact | facts]
    }
  end

  def log_fact(%__MODULE__{facts: facts} = wrk, %Fact{} = fact) do
    %__MODULE__{wrk | facts: [fact | facts]}
  end

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

  # @doc """
  # Runs a runnable workflow by executing steps ready in the agenda.

  # Appends resulting facts to the log.
  # """
  # def run(%__MODULE__{agenda: agenda} = wrk) do
  #   wrk =
  #     Enum.reduce(agenda.runnables, wrk, fn {_key, {step, fact}}, wrk ->
  #       Activation.activate(step, wrk, fact)
  #     end)

  #   %__MODULE__{wrk | agenda: Agenda.next_cycle(wrk.agenda)}
  # end

  @doc """
  Returns actual side effects of the workflow - i.e. facts resulting from the execution of a step.
  """
  def reactions(%__MODULE__{} = wrk) do
    wrk.facts
    |> Enum.filter(fn %Fact{} = fact ->
      fact.value != :satisfied and not is_nil(fact.ancestry)
    end)
    |> Enum.map(& &1.value)
  end

  @doc """
  Returns a list of the next {node, fact} i.e "runnable" pairs ready for activation in the next cycle.

  All Runnables returned are independent and can be run in parallel then fed back into the Workflow
  without wait or delays to get the same results.
  """
  def next_runnables(%__MODULE__{agenda: agenda}), do: Agenda.next_runnables(agenda)

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

  def with_rule(
        %__MODULE__{flow: flow} = workflow,
        %Condition{} = condition,
        %Step{} = reaction_step
      ) do
    arity_check = Steps.is_of_arity?(condition.arity)
    arity_condition = Condition.new(arity_check)

    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(arity_condition, [arity_condition.hash, "is_of_arity_#{condition.arity}"])
          |> Graph.add_vertex(condition, [condition.hash, function_name(condition.work)])
          |> Graph.add_vertex(reaction_step, [reaction_step.hash, reaction_step.name, function_name(reaction_step.work)])
          |> Graph.add_edge(root(), arity_condition, label: {%Root{}, arity_condition.hash})
          |> Graph.add_edge(arity_condition, condition, label: {%Root{}, condition.hash})
          |> Graph.add_edge(condition, reaction_step, label: {condition.hash, reaction_step.hash})
    }
  end

  defp function_name(fun), do: Function.info(fun, :name) |> elem(1)

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

  defp do_merge(into_flow, from_flow, step, parent) do
    into_flow
    |> Graph.add_vertex(step, [step.hash])
    |> Graph.add_edge(parent, step, label: {%Root{}, step.hash})
    |> do_merge(from_flow, next_steps(from_flow, step), step)
  end

  @doc """
  Adds a step to the root of the workflow that is always evaluated with a new fact.
  """
  def add_step(%__MODULE__{} = workflow, %Step{} = child_step) do
    add_step(workflow, %Root{}, child_step)
  end

  @doc """
  Adds a dependent step to some other step in a workflow by name.

  The dependent step is fed signed facts produced by the parent step during a reaction.

  Adding dependent steps is the most low-level way of building a dataflow execution graph as it assumes no conditional, branching logic.

  If you're just building a pipeline, dependent steps can be sufficient, however you might want Rules for conditional branching logic.
  """
  def add_step(%__MODULE__{flow: flow} = workflow, %Root{}, %Step{} = child_step) do
    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(child_step, [child_step.hash, child_step.name])
          |> Graph.add_edge(%Root{}, child_step, label: {%Root{}, child_step.hash})
    }
  end

  def add_step(%__MODULE__{flow: flow} = workflow, %Step{} = parent_step, %Step{} = child_step) do
    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(child_step, [child_step.hash, child_step.name])
          |> Graph.add_edge(parent_step, child_step, label: {parent_step.hash, child_step.hash})
    }
  end

  def add_step(%__MODULE__{} = workflow, parent_step_name, %Step{} = child_step) do
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

  @doc """
  Adds an accumulator to a Workflow.

  `Dagger.Accumulators` are used to collect some state for which to make further decision upon.

  You can think of an accumulator as a set of reducer functions that react over a shared state.

  See the `Dagger.Accumulator module` for more details.
  """
  def add_accumulator(%__MODULE__{} = workflow, accumulator) do
    %Accumulator{init: init, reducers: reducers} = accumulator

    Enum.reduce(reducers, add_rule(workflow, init), fn reducer, workflow ->
      add_rule(workflow, reducer)
    end)
  end

  # defp workflow_hash(%__MODULE__{flow: flow} = workflow) do

  # end

  # defimpl Runnable do
  #   alias Dagger.Workflow
  #   alias Dagger.Workflow.{
  #     Fact,
  #     Step,
  #     Steps,
  #   }

  #   # workflow + fact, worfklow + facts, workflow + raw_input, workflow + raw_inputs (list)

  #   def runnable(%Workflow{} = wrk, %Fact{ancestry: {work_hash, _fact_hash}} = fact) do
  #     next_steps = Workflow.next_steps(wrk, work_hash)
  #   end

  #   def runnable(%Workflow{} = wrk, facts) when is_list(facts) do

  #   end

  #   def runnable(%Workflow{} = wrk, fact_stream) do

  #   end

  #   # @spec run(Workflow.t(), fact :: term()) :: Workflow.t()
  #   def run(%Workflow{} = wrk, %Fact{} = fact) do

  #     wrk
  #   end
  # end
end
