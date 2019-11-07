# Dagger

Dagger is a tool for building and operating run-time modifiable pipelines of steps.

A Dagger Step supports job dependency representation using a [DAG](https://en.wikipedia.org/wiki/Directed_acyclic_graph).

A Dagger pipeline can be built, held in state, modified at run-time, and dispatched for any given input.

This makes Dagger a good fit for realtime analysis use-cases or in situations where you want cleaner decoupling your runtime job processing infrastructure from your business logic.

## `work/1` functions

A Dagger.Step is ran by taking the `input` of a Step and running the `work/1` function contained in the `work` key of the Step.

Dependent Steps are given the finished `Step` with a `result` to it as input.

## Dagger Runners

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

### Disclaimer

Dagger is in early/active development, not yet stable, and as such is not available on Hex. Adressing concerns like retries, timeouts, persistence for large data/result-sets and safer validation is in progress. It'll be released when I like it. Use Dagger in production at your own peril. That said Dagger is a simple tool so feel free to fork, extend, and tell me about your use case.

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

