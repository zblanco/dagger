defmodule Dagger.Pipeline do
  @moduledoc """
  A forward stepping pipeline of tasks.

  A pipeline can be given to a Runner with an initial input to execute.

  Steps in the pipeline are required to have unique names to guarantee
    we can do things like fetch a step, add a dependent step, etc.

  Dagger pipelines are validated to ensure dependent steps are only given valid inputs.

  ## Intended API

  ```elixir
  alias Dagger.{Pipeline, Step}

  pipeline_with_two_concurrent_steps =
    Pipeline.new(name: "my_pipeline")
    |> Pipeline.add_step(Step.new("my_step", &MyModule.my_function/1)
    |> Pipeline.add_step(Step.new("my_other_step", &MyModule.my_other_function/1)

  pipeline_with_dependent_jobs =
    pipeline_with_two_concurrent_steps
    |> Pipeline.add_dependent_step("my_step", Step.new("my_dependent_step", &MyModule.my_dependent_function/1))
  ```
  """
  alias Dagger.Step

  defstruct name: nil,
            run_id: nil,
            steps: nil, # will we want individual steps to have different runners?
            context: %{}

  def new(params \\ []) do
    struct!(__MODULE__, params) |> Map.put(:steps, Graph.new())
  end

  @doc """
  Adds a top-level step
  """
  def add_step(%__MODULE__{steps: steps} = pipeline, child_step) do

  end

  def add_dependent_step(%__MODULE__{steps: steps} = pipeline, parent_step_name, child_step) do

  end
end
