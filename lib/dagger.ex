defmodule Dagger do
  @moduledoc """
  Dagger is a tool for modeling your workflows as data that can be composed together at runtime.

  All Dagger constructs can be integrated into a Dagger.Workflow and evaluated lazily in concurrent contexts.

  Dagger Workflows are essentially a decorated dataflow graph (a DAG - "directed acyclic graph") of your code that can model your rules, pipelines, and state machines.

  Basic data flow dependencies such as in a pipeline are modeled as %Step{} structs (nodes/vertices) in the graph with directed edges (arrows) between steps.

  Steps can be thought of as a sumple input -> output lambda function.

  As Facts are fed through a workflow, various steps are traversed to as needed and activated producing more Facts.

  Beyond steps, Dagger has support for Rules and Accumulators for conditional and stateful evaluation.

  Together this enables Dagger to express complex decision trees, finite state machines, data pipelines, and more.

  The Dagger.Runnable protocol is what allows for extension of Dagger and composability of structures like Workflows, Steps, Rules, and Accumulators by allowing user defined structures to be integrated into a `Dagger.Workflow`.

  See the [Workflow]() module for more information.

  This top level module provides high level functions and macros for building Dagger Runnables
    such as Steps, Rules, Workflows, and Accumulators.

  This core library is responsible for modeling Workflows with Steps, enforcing contracts of Step functions,
    and defining the contract of Runners used to execute Workflows.

  Dagger was designed to be used custom process topologies and/or libraries such as GenStage, Broadway, and Flow.

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
    Steps,
    Rule
  }

  @doc """
  Defines a rule with specific key value params.
  """
  defmacro rule(opts) when is_list(opts) do
    rule_name = Keyword.get(opts, :name) || raise ArgumentError, "Defining a rule requires a name"

    condition = Keyword.get(opts, :condition) || (&Steps.always_true/1)

    reaction =
      Keyword.get(opts, :reaction) || raise ArgumentError, "Defining a rule requires a reaction"

    description = Keyword.get(opts, :description)

    expression = [{condition, reaction}]

    arity = Steps.arity_of(reaction)

    quote bind_quoted: [
            expression: expression,
            description: description,
            arity: arity,
            rule_name: rule_name
          ] do
      Kernel.struct!(Dagger.Workflow.Rule,
        name: to_string(rule_name),
        arity: arity,
        expression: expression,
        description: description
      )
    end
  end

  defmacro rule(_, opts \\ [])

  @doc """
  Defines a Rule with an anonymous function and additional options.
  """
  defmacro rule({:fn, _meta, clauses}, opts) do
    rule_name = Keyword.get(opts, :name) || raise ArgumentError, "Defining a rule requires a name"
    description = Keyword.get(opts, :description)

    IO.inspect(clauses, label: "clauses")
    IO.inspect(opts, label: "opts")

    arity = Steps.arity_of(clauses) |> IO.inspect(label: "arity of anonymous function rule")
    expressions = Enum.map(clauses, &expression_of_clauses/1) |> IO.inspect(label: "expressions")

    quote bind_quoted: [
            expressions: Macro.escape(expressions),
            arity: arity,
            description: description,
            rule_name: rule_name
          ] do
      Kernel.struct!(Dagger.Workflow.Rule,
        name: to_string(rule_name),
        arity: arity,
        expression: expressions,
        description: description
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
                   {{:., _dot_meta, [{:__aliases__, aliasing_opts, aliases}, function_name]},
                    _dot_opts, _dot_etc}
                   | [arity]
                 ]}
              ]} = _captured_function,
             opts
           ) do
    rule_name = Keyword.get(opts, :name) || raise ArgumentError, "Defining a rule requires a name"
    description = Keyword.get(opts, :description)

    # IO.inspect(captured_function, label: "captured_function")
    IO.inspect(aliasing_opts, label: "aliasing_opts")
    # IO.inspect(aliases, label: "aliases")
    # IO.inspect(function_name, label: "function_name")
    # IO.inspect(dot_opts, label: "dot_opts")
    # IO.inspect(arity, label: "arity")
    # IO.inspect(opts, label: "opts")

    # IO.inspect(__ENV__, label: "env", limit: :infinity, printable_limit: :infinity)
    # IO.inspect(__CALLER__, label: "caller", limit: :infinity, printable_limit: :infinity)
    IO.inspect(__CALLER__.context_modules, label: "context_modules")

    root_module = Keyword.get(aliasing_opts, :counter) |> elem(0)

    captured_function_module_string =
      [root_module | aliases]
      |> Enum.map(fn module ->
        module_string = to_string(module)
        String.replace(module_string, "Elixir.", "")
      end)
      |> Enum.uniq()
      |> IO.inspect(label: "modules to join")
      |> Enum.join(".")

    captured_function_module =
      "Elixir.#{captured_function_module_string}"
      |> String.to_atom()
      |> IO.inspect(label: "captured_function_module")

    with {:ok, function_ast} <- fetch_ast(captured_function_module, function_name) do
      expression = expression_of_clauses(function_ast)

      quote bind_quoted: [
              expression: Macro.escape(expression),
              description: description,
              arity: arity,
              rule_name: rule_name
            ] do
        Kernel.struct!(Dagger.Workflow.Rule,
          name: to_string(rule_name),
          expression: expression,
          description: description,
          arity: arity
        )
      end
    end
  end

  defmacro rule(func, opts) do
    IO.inspect(func, label: "func")
    IO.inspect(opts, label: "opts")

    func
  end

  defp expression_of_clauses({:->, _meta, [lhs, rhs]}) do
    IO.inspect(lhs, label: "lhs anon")
    IO.inspect(rhs, label: "rhs anon")
    {lhs, rhs}
  end

  defp expression_of_clauses({:->, _meta, [[], rhs]}) do
    {&Steps.always_true/1, rhs}
  end

  defp expression_of_clauses(clauses) when is_list(clauses) do
    clauses
    |> Enum.map(&expression_of_clauses/1)
    |> List.flatten()
  end

  defp expression_of_clauses({:def, _meta, [{_function_name, _clause_meta, lhs}, [do: rhs]]}) do
    IO.inspect(lhs, label: "lhs named")
    IO.inspect(rhs, label: "rhs named")
    {lhs, rhs}
  end

  defp fetch_ast(module, function_name) do
    with {_, accumulation} <-
           module.__info__(:compile)[:source]
           |> to_string()
           |> File.read!()
           |> Code.string_to_quoted!()
           |> Macro.prewalk([], fn
             matching_fun = {:def, _, [{^function_name, _, _} | _]}, acc ->
               matching_fun |> IO.inspect(label: "matching function found")
               {matching_fun, [matching_fun | acc]}

             segment, acc ->
               {segment, acc}
           end) do
      {:ok, accumulation}
    end
  end

  def workflow(opts \\ []) do
    name = Keyword.get(opts, :name) || raise ArgumentError, "Defining a workflow requires a name"
    steps = Keyword.get(opts, :steps)
    rules = Keyword.get(opts, :rules)

    Workflow.new(name)
    |> add_steps(steps)
    |> add_rules(rules)
  end

  # def accumulator(opts \\ []) do
  #   name = Keyword.get(opts, :name) || raise ArgumentError, "Defining an accumulator requires a name"
  #   init = Keyword.get(opts, :init) || raise ArgumentError, "Defining an accumulator requires an initiator"
  #   reducers = Keyword.get(opts, :reducers) || raise ArgumentError, "Defining an accumulator requires a list of reducers"

  # end

  # defp init_rule(%Rule{} = init, _acc_name), do: init
  # defp init_rule(init, acc_name), do: Dagger.rule(init, name: "#{acc_name}-init")

  defp add_steps(workflow, nil), do: workflow

  defp add_steps(workflow, steps) when is_list(steps) do
    Enum.reduce(steps, workflow, fn
      %Step{} = step, wrk ->
        Workflow.add_step(wrk, step)

      {%Step{} = step, _dependent_steps} = parent_and_children, wrk ->
        wrk = Workflow.add_step(wrk, step)
        add_dependent_steps(parent_and_children, wrk)
    end)
  end

  defp add_dependent_steps({parent_step, dependent_steps}, workflow) do
    Enum.reduce(dependent_steps, workflow, fn
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

  # def next_runnables(flowable) do

  # end

  # def next_runnables(%Workflow{} = workflow, %Fact{} = input) do
  #   Workflow.next_runnables(workflow, input)
  # end

  # def next_runnables(runnable, input) do
  #   Dagger.Flowable.to_workflow()
  # end
end
