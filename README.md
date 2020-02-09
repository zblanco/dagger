# Dagger

Dagger is a tool for making runtime modifiable compute graphs.

Dagger supports step-wise job dependency representation as well as rule-based workflows.

You can think of Dagger as a library for expressing templates of a calculation or procedure that can be evaluated lazily like Elixir's `Stream` module.

The core capabilities are built around LibGraph where the dependencies between rules/steps/conditions
  are modeled as a Graph. The primary API's for using Dagger are in the `Pipeline` and `Workflow` modules.

Conceptually a Pipeline or a Workflow are static representations of the computation much like compiled code is.

At runtime a process might take the Pipeline or Workflow and run it with inputs to get results. The difference being this 
  data structure is still modifiable at runtime whereas compiled code might need hot-code-reloading and developer resources.

This makes Dagger a useful tool for requirements where the behaviour of a system has to change at runtime without introduction of
  new code or developer need-to-know.

A Dagger pipeline can be built, held in state, modified at run-time, and dispatched for any given input.

This makes Dagger Pipelines a good fit for realtime analysis use-cases or in situations where you want cleaner decoupling your runtime job processing infrastructure from your business logic.

Workflows are a higher level abstraction where you can define Rules, Reactions, and Accumulations of state. A reaction to a rule might be a Dagger Pipeline
  with predefined inputs to produce further facts that might activate the workflow further.

All business workflow compositions expressed in Domain Driven Design can be thought of in terms of a workflow.

For example in DDD an Aggregate reacts to Commands by producing events and holding state based on past events.

In workflow terminology both Commands and Events are facts. This makes an aggregate a combination of rules that react to command-facts to 
  accumulate state. State accumulation is expressed as `state_changed` events that can be matched in an `AND` relationship of another Command.

The reverse method is also possible for Process Managers which handle events and produce commands.

Everything else are stateless reactions to facts.

## Just the core logic

Dagger is just the pure business logic to construct, express, and evaluate the compute graphs.

The intention is that there's so many ways to "do the runtime" especially with something as powerful as the BEAM under the hood.

I didn't want to impose a specific OTP topology to users of this library but instead provide a clean API that you can use in 
  whatever architecture you find Dagger fits your requirements.

I might provide adapters and implementations that can be used for common use cases, but that shouldn't stop you from extending on your own.

## Pipelines and Steps

A Dagger.Step is ran by taking the `input` of a Step and running the `work/1` function contained in the `work` key of the Step.

Dependent Steps are given the finished `Step` with a `result` to it as input.

## Dagger Pipeline Runners

Dagger just specifies a contract that a Runner most implement. A common Runner implementation could be a queue feeding to a pool of workers.

In a simple scenario you could implement a Runner with Elixir's Task module:

```elixir
### MyApp.Application
children = [
  ...
  {Task.Supervisor, name: MyApp.TaskSupervisor}
]

### Runner

defmodule MyApp.TaskRunner do
  alias MyApp.TaskSupervisor
  alias Dagger.Step
  @behaviour Dagger.Runner

  @impl true
  def run(%Step{runnable?: true, runner: __MODULE__} = step) do
    TaskSupervisor.start_link([
      {Task, fn -> Step.run(step) end}
    ], strategy: :one_for_one)
    :ok
  def run([] = steps) do
    Enum.each(steps, fn %Step{} = step -> enqueue(step))
    :ok
  end

  @impl true
  def ack, do: :ok

  def cancel, do: :ok
end
```
Using the task module like this is unbounded concurrency which can be dangerous, so consider using an actual Queue with some limited concurrency strategy like a worker pool.

Broadway, and/or Genstage are good tools for the kind of data processing piplines Dagger is useful for. For different kinds of guarantees like exactly once processing you could also use Oban or a similar database-backed queue as your runner. Since a Dagger Step is just a datastructure that can be built at run-time, you could use any variety of Runners at the same time in your application.

## Dagger Workflows

Example:

```elixir


```

### Disclaimers

Dagger is in early/active development, not yet stable, and as such is not available on Hex. Adressing concerns like retries, timeouts, persistence for large data/result-sets and safer validation is in progress. It'll be released when I like it. Use Dagger in production at your own peril. That said Dagger is a simple tool so feel free to fork, extend, and tell me about your use case.

Dagger is a high level abstraction that brings your business logic expression into runtime modification. That means you don't get the same compile-time
guarantees and it adds a layer of complexity. I don't recommend using it when you can just write code to the same effect. Rule of thumb is that if your state machine is getting complex and unwieldy you might be better off expressing the problem as constraints with rules and reactions instead of modeling each state transition manually. The sweet spot of Dagger is when a non-coding user needs to make specific and isolated changes to a business procedure or calculation. 

Consider also making a DSL or transformation the DSL's output into a Dagger structure that can be run.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dagger` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dagger, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/dagger](https://hexdocs.pm/dagger).

