defmodule Dagger.Step do
  @moduledoc """
  A step represents a recipe of dependent calculations to make for a given input.

  Dagger Steps model dependent operations that can be run concurrently by a runner.

  A top level step can be run when given the required parameters such as a `runner`, an `input`, a `name`, and a `work` function.

  Once a step has been run, dependent steps in the `steps` key are enqueued to be run with the parent step as input.

  A datastructure of these nested steps can be constructed without root inputs, injected with inputs at runtime,
    then dispatched to a runner for processing. The step processor only has to execute `Step.run/1` to start the pipeline of dependent steps.

  Assuming the Queue passed into the step is valid and feeds into more step processors the whole pipeline will run.

  For example once a step to run a calculation has been run,
    a notification to follow up with results can be published via a dependent step.

  However in most cases you would use this module when you want both `concurrent` execution along side step-by-step dependent execution.

  Dependent steps can be added using the `add_step/2` function.

  ```elixir
    example_step_pipeline = %{
      tokenization: %Step{
        name: :tokenization,
        work: &TextProcessing.tokenize/1,
        steps: %{ # steps here will be enqueued to run upon `:tokenization`'s completion
          down_case: %Step{
            name: :down_case,
            work: &TextProcessing.downcase/1,
            steps: %{
              word_counts: %Step{
                name: :word_counts,
                work: &TextProcessing.word_counts/1,
              },
              basic_sentiment: %Step{
                name: :basic_sentiment,
                work: &SentimentAnalysis.basic_sentiment/1,
              }
            }
          },
          total_count_of_words: %Step{
            name: :total_count_of_words,
            work: &TextProcessing.count_of_words/1
          },
        }
      },
      # Root steps can run concurrently from other steps.
      google_nlp: %Step{
        name: :google_nlp,
        work: &GoogleNLP.analyze_text/1,
      },
      dalle_challe_readability: %Step{
        name: :dalle_challe_readability,
        work: &Readbility.dalle_chall_readability/1,
      },
    }
  ```

  TODO:

  - [x] Implement `run_id` to keep track of active steps this will let us handle retries and prune deactivated steps from session terminations
  - [] step retry counts?
  * Maybe context is an anti-pattern?
  """
  defstruct name: nil,
            run_id: nil,
            work: nil,
            steps: nil,
            input: nil,
            result: nil,
            runner: nil,
            runnable?: false,
            context: %{}

  @type t :: %__MODULE__{
    name: binary(),
    run_id: term(),
    work: function(),
    steps: map(),
    input: term(),
    result: term(),
    runner: module(),
    runnable?: boolean(),
    context: map(),
  }

  def new(params) do
    struct!(__MODULE__, params)
  end

  def can_run?(%__MODULE__{runnable?: true}), do: :ok
  def can_run?(%__MODULE__{}), do: :error

  def set_queue(%__MODULE__{} = step, runner),
    do: set_step_value(step, :runner, runner)

  def set_work(%__MODULE__{} = step, work)
  when is_function(work), do: set_step_value(step, :work, work)

  def set_result(%__MODULE__{} = step, result),
    do: set_step_value(step, :result, result)

  def set_input(%__MODULE__{} = step, input),
    do: set_step_value(step, :input, input)

  def assign_run_id(%__MODULE__{} = step),
    do: set_step_value(step, :run_id, UUID.uuid4())

  def add_context(%__MODULE__{context: existing_context} = step, key, context) do
    %__MODULE__{step | context: Map.put(existing_context, key, context)}
  end

  defp set_step_value(%__MODULE__{} = step, key, value)
  when key in [:work, :input, :result, :runner, :run_id] do
    Map.put(step, key, value) |> evaluate_runnability()
  end

  @doc """
  Checks if a given step is runnable.

  This is chained automatically within `set_queue/2`, `set_result/2`, `set_input/2`, and `new/1`.

  `can_run?/1` can be used at run time to ensure a step is runnable before allocating resources and executing side effects.
  """
  def evaluate_runnability(%__MODULE__{
    name: name,
    work: work,
    input: input,
    result: nil,
    runner: runner,
    run_id: run_id,
  } = step)
    when is_function(work, 1)
    and not is_nil(name)
    and not is_nil(input)
    and not is_nil(runner)
    and not is_nil(run_id)
  do
    %__MODULE__{step | runnable?: true}
  end
  def evaluate_runnability(%__MODULE__{} = step), do:
    %__MODULE__{step | runnable?: false}

  @doc """
  Adds a child step to be enqueued with the result of the previous upon running.

  ### Usage

  ```elixir
  parent_step = %Step{name: "parent step"}
  child_step = %Step{name: "child step"}
  parent_with_child = Step.add_step(parent_step, child_step)
  ```
  """
  def add_step(%__MODULE__{steps: nil} = parent_step, child_step) do
    add_step(%__MODULE__{parent_step | steps: %{}}, child_step)
  end
  def add_step(
    %__MODULE__{steps: %{} = steps} = parent_step,
    %__MODULE__{name: name} = child_step)
  do
    %__MODULE__{parent_step | steps: Map.put_new(steps, name, child_step)}
  end

  @doc """
  Assuming a runnable step, `run/1` executes the function contained in `work`,
    sets the `result` with the return and enqueues dependent steps with the result as the input for the children.
  """
  def run(%__MODULE__{runnable?: false}), do: {:error, "step not runnable"}
  def run(%__MODULE__{work: work, input: input} = step) # consider mfa
  when is_function(work) do
    with {:ok, result} <- work.(input) do # we're assuming that the work function follows {:ok, _} | {:error, _} conventions - better way?
      updated_step =
        step
        |> set_result(result)
        |> set_parent_as_result_for_children()
        |> assign_run_id_for_children()
        |> enqueue_next_steps()

      {:ok, updated_step}
    else
      {:error, _} = error -> error
      error -> error
    end
  end

  def set_parent_as_result_for_children(%__MODULE__{steps: nil} = parent_step),  do: parent_step
  def set_parent_as_result_for_children(%__MODULE__{result: nil} = parent_step), do: parent_step
  def set_parent_as_result_for_children(%__MODULE__{steps: steps} = parent_step) do
    child_steps = Enum.map(steps, fn {name, step} ->
      {name, set_input(step, parent_step)}
    end)
    %__MODULE__{parent_step | steps: child_steps}
  end

  def assign_run_id_for_children(%__MODULE__{steps: nil} = parent_step), do: parent_step
  def assign_run_id_for_children(%__MODULE__{steps: steps} = parent_step) do
    child_steps = Enum.map(steps, fn {name, step} ->
      {name, assign_run_id(step)}
    end)
    %__MODULE__{parent_step | steps: child_steps}
  end

  def enqueue_next_steps(%__MODULE__{steps: nil} = step),
    do: evaluate_runnability(step)
  def enqueue_next_steps(%__MODULE__{steps: steps, runner: runner} = step) do
    Enum.each(steps, fn {_name, step} -> runner.enqueue(step) end) # consider how to handle errors
    step
  end
end
