defmodule Dagger do
  @moduledoc """
  Dagger is a tool for modeling your workflows as data that can be composed together at runtime.

  Dagger constructs can be integrated into a Dagger.Workflow and evaluated lazily in concurrent contexts.

  Dagger Workflows are a decorated dataflow graph (a DAG - "directed acyclic graph") of your code that can model your rules, pipelines, and state machines.

  Basic data flow dependencies such as in a pipeline are modeled as %Step{} structs (nodes/vertices) in the graph with directed edges (arrows) between steps.

  Steps can be thought of as a simple input -> output lambda function.

  As Facts are fed through a workflow, various steps are traversed to as needed and activated producing more Facts.

  Beyond steps, Dagger has support for Rules and Accumulators for conditional and stateful evaluation.

  Together this enables Dagger to express complex decision trees, finite state machines, data pipelines, and more.

  The Dagger.Flowable protocol is what allows for extension of Dagger and composability of structures like Workflows, Steps, Rules, and Accumulators by allowing user defined structures to be integrated into a `Dagger.Workflow`.

  See the Dagger.Workflow module for more information.

  This top level module provides high level functions and macros for building Dagger Flowables
    such as Steps, Rules, Workflows, and Accumulators.

  This core library is responsible for modeling Workflows with Steps, enforcing contracts of Step functions,
    and defining the contract of Runners used to execute Workflows.

  Dagger was designed to be used with custom process topologies and/or libraries such as GenStage, Broadway, and Flow.

  Dagger is meant for dynamic runtime modification of a workflow where you might want to compose pieces of a workflow together.

  These sorts of use cases are common in expert systems, user DSLs (e.g. Excel, low-code tools) where a developer cannot know
    upfront the logic or data flow to be expressed in compiled code.

  If the runtime modification of a workflow isn't something your use case requires - don't use Dagger.

  There are performance trade-offs in doing highly optimized things such as pattern matching and compilation at runtime.

  But if you do have complex user defined workflow, a database of things such as "rules" that have context-dependent
  composition at runtime - Dagger may be the right tool for you.

  ## Installation and Setup
  """
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Step,
    Condition,
    Steps,
    StateMachine,
    Rule
  }

  defp maybe_expand(condition, context) when is_list(condition) do
    Enum.map(condition, &maybe_expand(&1, context))
  end

  defp maybe_expand({:&, _, [{:/, _, _}]} = captured_function_ast, context) do
    Macro.prewalk(captured_function_ast, fn
      {:__aliases__, _meta, _aliases} = alias_ast ->
        Macro.expand(alias_ast, context)

      ast_otherwise ->
        ast_otherwise
    end)
  end

  # defp maybe_expand({name, meta, context} = ast, _context)
  # when is_atom(name) and is_list(meta) and is_atom(context) do

  # end

  defp maybe_expand(condition, _context), do: condition

  @doc """
  Defines a rule with specific key value params.
  """
  defmacro rule(opts) when is_list(opts) do
    rule_name = Keyword.get(opts, :name)

    condition =
      Keyword.get(opts, :condition)
      |> maybe_expand(__CALLER__)

    # should we instead build the quoted anonymous function all the way here?

    reaction =
      Keyword.get(opts, :reaction) || raise ArgumentError, "Defining a rule requires a reaction"

    arity = Steps.arity_of(reaction)

    quote bind_quoted: [
            condition: Macro.escape(condition),
            reaction: Macro.escape(reaction),
            arity: arity,
            rule_name: rule_name,
            context: Macro.escape(__CALLER__)
          ] do
      expression = {condition, reaction}

      Rule.new(
        expression,
        arity: arity,
        name: rule_name,
        context: context
      )
    end
  end

  defmacro rule(_, opts \\ [])

  @doc """
  Defines a Rule with an anonymous function and additional options.
  """
  defmacro rule({:fn, _meta, _clauses} = expression, opts) do
    rule_name = Keyword.get(opts, :name)

    quote bind_quoted: [
            expression: Macro.escape(expression),
            rule_name: rule_name,
            context: Macro.escape(__CALLER__)
          ] do
      Rule.new(
        expression,
        name: rule_name,
        context: context
      )
    end
  end

  defmacro rule(function_as_string, opts) when is_binary(function_as_string) do
    with {:ok, {:fn, _meta, _clauses} = quoted_func} <- Code.string_to_quoted(function_as_string) do
      quote bind_quoted: [quoted_func: quoted_func, opts: opts] do
        rule(quoted_func, opts)
      end
    end
  end

  defmacro rule(
             {:&, _capture_meta,
              [
                {:/, _arity_meta,
                 [
                   {{:., _dot_meta, [{:__aliases__, _aliasing_opts, _aliases}, _function_name]},
                    _dot_opts, _dot_etc}
                   | [_arity]
                 ]}
              ]} = expression,
             opts
           ) do
    rule_name = Keyword.get(opts, :name)

    quote bind_quoted: [
            expression: Macro.escape(expression),
            rule_name: rule_name,
            context: Macro.escape(__CALLER__)
          ] do
      Rule.new(
        expression,
        name: rule_name,
        context: context
      )
    end
  end

  defmacro rule(func, opts) do
    IO.inspect(func, label: "func")
    IO.inspect(opts, label: "opts")

    func
  end

  def workflow(opts \\ []) do
    name = Keyword.get(opts, :name) || raise ArgumentError, "Defining a workflow requires a name"
    steps = Keyword.get(opts, :steps)
    rules = Keyword.get(opts, :rules)

    Workflow.new(name)
    |> add_steps(steps)
    |> add_rules(rules)
  end

  @doc """
  A macro for expressing a state machine which can be composed within Dagger workflows.
  """
  defmacro state_machine(opts \\ []) do
    init =
      Keyword.get(opts, :init) ||
        raise ArgumentError, "Defining an accumulator requires an initiator function or value"

    reducer =
      Keyword.get(opts, :reducer) ||
        raise ArgumentError, "Defining an accumulator a reducer"

    reactors = Keyword.get(opts, :reactors)

    name = Keyword.get(opts, :name)

    quote bind_quoted: [
            init: Macro.escape(init),
            reducer: Macro.escape(reducer),
            reactors: Macro.escape(reactors),
            name: Macro.escape(name)
          ] do
      StateMachine.new(init, reducer, reactors: reactors, name: name)
    end
  end

  defmacro state_machine(init, reducer, opts) do
    quote bind_quoted: [
            init: Macro.escape(init),
            reducer: Macro.escape(reducer),
            opts: Macro.escape(opts)
          ] do
      StateMachine.new(init, reducer, opts)
    end
  end

  defp add_steps(workflow, nil), do: workflow

  defp add_steps(workflow, steps) when is_list(steps) do
    # root level pass
    Enum.reduce(steps, workflow, fn
      %Step{} = step, wrk ->
        Workflow.add_step(wrk, step)

      {%Step{} = step, _dependent_steps} = parent_and_children, wrk ->
        wrk = Workflow.add_step(wrk, step)
        add_dependent_steps(parent_and_children, wrk)

      {[_step | _] = parent_steps, dependent_steps}, wrk ->
        wrk = Enum.reduce(parent_steps, wrk, fn step, wrk -> Workflow.add_step(wrk, step) end)

        join =
          parent_steps
          |> Enum.map(& &1.hash)
          |> Workflow.Join.new()

        wrk = Workflow.add_step(wrk, parent_steps, join)

        add_dependent_steps({join, dependent_steps}, wrk)
    end)
  end

  defp add_dependent_steps({parent_step, dependent_steps}, workflow) do
    Enum.reduce(dependent_steps, workflow, fn
      {[_step | _] = parent_steps, dependent_steps}, wrk ->
        wrk =
          Enum.reduce(parent_steps, wrk, fn step, wrk ->
            Workflow.add_step(wrk, parent_step, step)
          end)

        join =
          parent_steps
          |> Enum.map(& &1.hash)
          |> Workflow.Join.new()

        wrk = Workflow.add_step(wrk, parent_steps, join)

        add_dependent_steps({join, dependent_steps}, wrk)

      {step, _dependent_steps} = parent_and_children, wrk ->
        wrk = Workflow.add_step(wrk, parent_step, step)
        add_dependent_steps(parent_and_children, wrk)

      step, wrk ->
        Workflow.add_step(wrk, parent_step, step)
    end)
  end

  defp add_rules(workflow, nil), do: workflow

  defp add_rules(workflow, rules) do
    Enum.reduce(rules, workflow, fn %Rule{} = rule, wrk ->
      Workflow.add_rule(wrk, rule)
    end)
  end

  @doc """
  Creates a step: a basic lambda expression that can be added to a workflow.
  """
  def step(opts \\ [])

  def step(work) when is_function(work) do
    step(work: work)
  end

  def step(opts) when is_list(opts) do
    Step.new(opts)
  end

  def step(opts) when is_map(opts) do
    Step.new(opts)
  end

  def step(work, opts) when is_function(work) do
    Step.new(Keyword.merge([work: work], opts))
  end

  def step({m, f, a} = work, opts) when is_atom(m) and is_atom(f) and is_integer(a) do
    Step.new(Keyword.merge([work: work], opts))
  end

  @doc """
  Accepts a boolean function
  """
  def condition(work) when is_function(work) do
    Condition.new(work)
  end

  # defp rule_condition(condition) when is_function(condition) do
  #   condition
  # end

  # defp rule_condition() do
  #   condition
  # end
end
