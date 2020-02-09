defmodule Dagger do
  @moduledoc """
  Dagger is a tool for building and operating run-time modifiable pipelines of steps.

  A `Step` is a composable recipe calculations and its dependent operations.

  Dependent operations are just more steps.

  When a Step is ran it is assigned a run_id and dispatched to the `Runner` specified in the Step.

  The Runner is responsible for executing the `work` specified in the Step.

  The return of running `work` will be added to the Step's `result` then each dependent step's `input` will be set to the parent job.

  ## How do I get results?

  Results are obtained by calling out to some other service in the `work` function or in a dependent step, also in the `work` function.

  It's your responsibility to consume the results as needed.

  ## Building a

  Dagger lets you build a pipeline of steps that can be injected with inputs and delivered to a runner.

  The top level API of Dagger is responsible for helping you build those pipelines of Steps,
    assert validity of a step, and dispatch to the runner.

  ```elixir
  Do we want

  some_runner = SomeRunner.new(config)
  some_command = SomeCommand.new(params)

  some_runner.run(some_command)

  or Dagger.run(some_command)
  ```
  """
end
