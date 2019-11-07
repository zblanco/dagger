defmodule DaggerTest do
  use ExUnit.Case
  alias Dagger.Step

  describe "new/1" do
    test "we can create a step with a map of params" do
      step = Step.new(%{name: "test_job", work: &JobSupport.squareaplier/1})

      assert match?(%Step{}, step)
    end

    test "we can create a step with a keyword list of params" do
      step = Step.new(name: "test_job", work: &JobSupport.squareaplier/1)

      assert match?(%Step{}, step)
    end

    test "without required params a step isn't runnable" do
      step = Step.new(name: "test_job", work: &JobSupport.squareaplier/1)

      assert Step.can_run?(step) == :error
    end
  end

  describe "evaluate_runnability/1" do
    test "a valid step has a name, work, input, no result, and a queue" do
      step = Step.new(
        name: "test_job",
        work: &JobSupport.squareaplier/1,
        input: 2,
        queue: JobSupport.TestQueue
      ) |> Step.evaluate_runnability()

      assert Step.can_run?(step) == :ok
    end

    test "setting the last required value will make a step runnable" do
      invalid_job = Step.new(
        name: "test_job",
        work: &JobSupport.squareaplier/1,
        queue: JobSupport.TestQueue
      ) |> Step.evaluate_runnability()

      assert Step.can_run?(invalid_job) == :error

      valid_job = Step.set_input(invalid_job, 2)
      assert Step.can_run?(valid_job) == :ok
    end
  end

  describe "add_dependent_job/2" do
    test "we can add a dependent step to a parent" do
      parent_job = Step.new(
        name: "parent_test_job",
        work: &JobSupport.squareaplier/1,
        input: 2,
        queue: JobSupport.TestQueue
      ) |> Step.evaluate_runnability()

      child_job = Step.new(
        name: "child_test_job",
        work: &JobSupport.squareaplier/1,
        input: nil,
        queue: JobSupport.TestQueue
      ) |> Step.evaluate_runnability()

      parent_with_dependent_job = Step.add_dependent_job(parent_job, child_job)

      assert match?(parent_with_dependent_job, %Step{jobs: %{child_job.name => child_job}})
    end
  end

  describe "run/1" do
    test "if the step isn't runnable, we return an error" do
      invalid_job = Step.new(
        name: "test_job",
        work: &JobSupport.squareaplier/1,
        queue: JobSupport.TestQueue
      )

      assert match?({:error, "Step not runnable"}, Step.run(invalid_job))
    end

    test "a runnable step runs the work and puts the return into the result" do
      step = Step.new(
        name: "test_job",
        work: &JobSupport.squareaplier/1,
        input: 2,
        queue: JobSupport.TestQueue
      ) |> Step.evaluate_runnability()

      {:ok, ran_job} = Step.run(step)

      assert match?(%Step{result: 4}, ran_job)
    end

    test "dependent jobs are evaluated when parent is ran" do
      assert false
    end

    test "dependent jobs are enqueued with the result of the parent step" do
      # modify the test queue to hold state
    end
  end
end
