defmodule Dagger.Workflow do
  @moduledoc """
  Dagger Workflows model dataflow dependencies between steps of lambda functions.

  Dagger Workflows support both logical and data-input dependencies.

  Workflows are modeled as a directed acyclic graph of `%Step{}` structs where the `work` field of the Step is a function
  that takes a `%Fact{}` as input and returns a `%Fact{}` as output.

  You can think of Dagger Workflows as a recipe of rules that when fed a stream of facts may react.

  Instead of the dependencies modeled on the level of Elixir code compiled to AST (Abstract Syntax Tree)
  we're using a graph data structure and passing lambda functions around. The trade-off is that we can
  support modification of these constraints at runtime without going through a compilation phase however
  we now have to enforce invariants that the compiler normally would.

  A big advantage to specifying the flow of data through dependencies in a graph is we have a model of possible
  paralellism between steps. This is essentially a runtime behaviour contract that we can use to generate
  a topology of processes without developer intervention. In many ways this is similar to how the `Flow`
  library works where a datastructure modeling the flow of data is used to generate an optimized GenStage topology
  that runs the Flow pipeline concurrently. The difference is that to get the ability to modify that flow pipeline
  at runtime we have to also lift what would normally be elixir control flow code into the datastructure as well.

  This makes Dagger workflows good for use cases where the volume of domain constraints to model is too great
  for the usual Business -> Developer -> Code cycle. Here we can use Dagger to as the base for a DSL or UI
  that lets the Business users input the rules without a developer. So while Dagger isn't a full-blown
  workflow engine like Airflow nor an Rules Engine like Drools or Camunda it can be used to build systems like that
  without coupling the runtime concerns in the tool. At least that's the goal.

  Additionally most tools in the Workflow/Rules-Engine domain aren't made for streaming data but rather etl/batch/scheduled/periodic
  processing. When both the Workflow of computation and the data are separate but also transportable and specified
  for parallel processing we can transport both easily across machines in a cloud. Instead of moving the input data to a server
  we move the operations to run on the data to where the input data is already.

  The developer is still involved but they aren't hard coding business logic in compiled code but instead
  setting up and configuring Dagger to be constrained only to the dynamicism the domain requires. Code is
  still written but for the 'tricky bits' like making an abstraction on top of Dagger Workflow components
  (Rules, Conditions, Accumulators, etc) that lets the business express domain knowledge using domain language.

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

  ### Steps - pipeline (data flow dependency) construct

  A Step accepts an input of a fact stream transforms and returns a new fact.

  If a developer/user is writing a function that doesn't return a fact but just some other term, Dagger should wrap it to return a Fact anyway.

  Most Steps should be deterministic, pure, functions. External side effects can be wrapped in a Runnable for ack, consume once guarantees.

  input :: Stream<Fact>(id: hash-of-parent-work-function <> hash-of-data-produced)

  ## Facts

  All Steps added to a Workflow are wrapped to return Facts.

  Facts are used as Tokens to activate nodes in a workflow.

  ## Rules

  At least two steps where the first returns a boolean expression fact

  ## Accumulators

  Returns a :state_produced type fact.

  ** should we enforce a fact protocol? **

  Workflow.new()
  |> Workflow.add_step(my_rule)
  """
  alias Dagger.Workflow.{Rule, Accumulator, Step, Fact}

  @type t() :: %__MODULE__{
          name: String.t(),
          flow: Graph.t(),
          hash: binary()
        }

  # | %Runnable{}
  @type runnable() :: {fun(), term()}

  @enforce_keys [:name]

  defstruct name: nil,
            hash: nil,
            flow: nil

  @typedoc """
  Discrimination network of rules, actions, and accumulations organized as steps of functions.
  """
  @type flow() :: Graph.t()

  def new(name) when is_binary(name) do
    new(name: name)
  end

  def new(params) do
    struct!(__MODULE__, params)
    |> Map.put(:flow, Graph.new() |> Graph.add_vertex(root()))
  end

  defp root(), do: :root

  # @spec react(Workflow.t(), input :: term() | Enumerable.t()) :: Enumerable.t() | list(Fact.t())
  @doc """
  Returns signed runnables that when executed may result in side effects.

  A runnable holds everything necessary for a "reaction" or potential side effect to occur without actually executing the operation.

  Reactions in a workflow are two-phase. Exposing intentions of some action using a `value` fact paired with the work function to apply it to.

  Atomic runnables are a function and a an arbitrary term to feed into it.

  Functions can be MFA tuples, or elixir functions using the `&MyModule.my_func/arity` syntax.

  Runnables are compiled into Workflows as Steps (for functions) which produce additional Facts (for terms)
    that also include ancestral hashes to connect it to a path of execution.

  Any individual atomic runnable executed might return another runnable containing
    either a workflow (a composite set of steps) or simply a step with the next fact to feed it.

  Runnable Layers of Abstraction:

  Workflows & Streams -> Steps & Facts -> Functions & Terms (Atomic)

  Steps and Facts represent the execution in context of it's parent ancestors that produced it.

  Workflows and Streams are composites representing a network of dependent steps and a stream that can be pulled from.

  This execution flow means that it's possible to write an infinite loop.

  But it's also powerful for dynamically reacting to infinite streams of data
    and scalable if we have a dynamic task graph describing paralellization opportunities.

  The purpose of a workflow reaction is to break down the composite runnables into atomic runnables.

  This is done by returning a stream which represents the progress of the workflow as a fact produces more facts.

  This is meant to be an API for a Dagger Runtime implementation so we want the results from enumerating the stream to
    contain metadata needed to orchestrate the parallellism opportunities available.
  """
  def react(workflow, facts) when is_list(facts) do
    Stream.resource(
      initial_reaction(workflow, facts),
      fn
        %{runnables: nil, facts: facts} ->
          {:halt, facts}

        %{runnables: runnables, facts: facts} = acc ->
          %{runnables: next_runnables, facts: new_facts} =
            runnables
            |> Enum.map(&do_react(workflow, &1))
            |> Enum.reduce(%{facts: [], runnables: []}, fn
              {fact, runnables}, acc ->
                %{acc | facts: [fact | acc.facts], runnables: [runnables | acc.runnables]}
            end)

          next_runnables_or_nil =
            case Enum.empty?(next_runnables |> List.flatten) do
              true -> nil
              _ -> next_runnables
            end

          facts_so_far = [new_facts | facts] |> List.flatten()

          {facts_so_far,
           %{
             acc
             | facts: facts_so_far,
               runnables: next_runnables_or_nil
           }}
      end,
      fn acc -> acc end
    )
  end

  def react(workflow, fact), do: react(workflow, [fact])

  # common runnable activations always return {fact, next_runnables}
  def do_react(%__MODULE__{flow: flow}, {%Step{} = step, %Fact{} = fact}) do
    case Step.run(step, fact) do
      %Fact{type: :condition, runnable: {ancestor_step, ancestor_fact}, value: true} = fact ->
        next_runnables =
          flow
          |> next_steps(ancestor_step)
          |> Enum.map(&{&1, %Fact{ancestor_fact | runnable: nil}})

        {fact, next_runnables}

      # conditions that do not return true don't have any child runnables
      %Fact{type: :condition} = fact ->
        {fact, nil}

      %Fact{type: :reaction, runnable: {ancestor_step, _ancestor_fact}} = fact ->
        next_runnables =
          flow
          |> next_steps(ancestor_step)
          |> Enum.map(&{&1, %Fact{fact | runnable: nil}})

        {fact, next_runnables}
    end
  end

  # initial pass through conditions
  def do_react(%__MODULE__{flow: flow} = workflow, %Fact{} = fact) do
    flow
    |> next_steps(:root)
    |> Enum.map(&{&1, fact})
    |> Enum.map(&do_react(workflow, &1))
    |> Enum.reduce(
      %{runnables: [], facts: []},
      fn
        {new_fact, nil}, %{facts: facts} = acc ->
          %{acc | facts: [new_fact | facts]}

        {new_fact, new_runnables}, %{facts: facts} = acc ->
          %{acc | runnables: new_runnables, facts: [new_fact | facts]}
      end
    )
  end

  defp initial_reaction(workflow, raw_facts) do
    fn ->
      facts = Enum.map(raw_facts, &Fact.new(value: &1))

      %{facts: new_facts} =
        initial_reaction =
        facts
        |> Enum.map(&do_react(workflow, &1))
        |> Enum.reduce(
          %{facts: [], runnables: []},
          fn reaction, %{facts: facts, runnables: runnables} = acc ->
            %{acc | facts: [reaction.facts | facts], runnables: [reaction.runnables | runnables]}
          end
        )
        |> Enum.map(fn {k, v} -> {k, List.flatten(v)} end)
        |> Map.new()

      %{initial_reaction | facts: [new_facts | facts] |> List.flatten}
    end
  end

  defp next_steps(flow, parent_step) do
    Graph.out_neighbors(flow, parent_step)
  end

  def show(%__MODULE__{flow: flow} = workflow) do
    with {:ok, graph} <- Graph.to_dot(flow) do
      IO.write("\n")
      IO.write("\n")
      IO.puts(graph)
      IO.write("\n")
      IO.write("\n")
    end

    workflow
  end

  @doc """
  Adds a rule to the workflow. Rules are converted into individual steps where the condition step
  is attached to the root. The parent is almost always the root node unless it's a duplicate
  in which case the reaction is attached to the existing condition step.

  In some cases the condition is in multiple parts and some of the conditional clauses already exist as steps
  in which case we add the sub-clause(s) of the condition that don't exist as a dependent step to the conditions
  that do exist and add the reaction step to the sub-conditions.
  """
  def add_rule(%__MODULE__{flow: flow} = workflow, %Rule{} = rule) do
    condition_step = Step.of_condition(rule)
    reaction_step = Step.of_reaction(rule)

    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(condition_step, [condition_step.hash, condition_step.name])
          |> Graph.add_vertex(reaction_step, [reaction_step.hash, reaction_step.name])
          |> Graph.add_edge(root(), condition_step, label: {:root, condition_step.hash})
          |> Graph.add_edge(condition_step, reaction_step,
            label: {condition_step.hash, reaction_step.hash}
          )
    }
  end

  def add_rule(workflow, opts) when is_map(opts) or is_list(opts) do
    add_rule(workflow, Rule.new(opts))
  end

  @doc """
  Adds a dependent step to some other step in a workflow by name.

  The dependent step is fed signed facts produced by the parent step during a reaction.

  Adding dependent steps is the most low-level way of building a dataflow execution graph as it assumes no conditional, branching logic.

  If you're just building a pipeline, dependent steps can be sufficient, however you might want Rules for conditional branching logic.
  """
  def add_step(%__MODULE__{flow: flow} = workflow, :root, %Step{} = child_step) do
    %__MODULE__{
      workflow
      | flow:
          flow
          |> Graph.add_vertex(child_step, [child_step.hash, child_step.name])
          |> Graph.add_edge(:root, child_step, label: {:root, child_step.hash})
    }
  end

  def add_step(%__MODULE__{flow: flow} = workflow, parent_step_name, %Step{} = child_step) do
    case get_step_by_name(workflow, parent_step_name) do
      {:ok, parent_step} ->
        %__MODULE__{
          workflow
          | flow:
              flow
              |> Graph.add_vertex(child_step, [child_step.hash, child_step.name])
              |> Graph.add_edge(parent_step, child_step,
                label: {parent_step.hash, child_step.hash}
              )
        }

      {:error, :step_not_found} ->
        {:error, "A step named #{parent_step_name} was not found"}
    end
  end

  # def add_workflow(%__MODULE__{flow: flow} = parent_workflow, parent_connector_step_or_hash_or_step_name, %__MODULE__{flow: child_flow} = child_workflow) do
  #   # how would we merge two workflow graphs? do we have to?
  #   #
  # end

  @doc """
  Fetches a step from the workflow provided the unique name.

  Returns an error if a step by the name given is not found.
  """
  def get_step_by_name(_workflow, :root), do: {:ok, :root}

  def get_step_by_name(%__MODULE__{flow: flow}, step_name) do
    case flow
         # todo: think about a cheaper way to do this...
         |> Graph.vertices()
         |> Enum.find(
           {:error, :step_not_found},
           fn
             %Step{name: name} -> step_name == name
             :root -> false
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
    %Accumulator{initializer: initializer, state_reactors: state_reactors} = accumulator

    Enum.reduce(state_reactors, add_rule(workflow, initializer), fn reactor, workflow ->
      add_rule(workflow, reactor)
    end)
  end
end
