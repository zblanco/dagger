# defmodule DaggerTest do
#   use ExUnit.Case
#   alias Dagger.Step
#   alias Dagger.TestRunner

#   describe "new/1" do
#     test "we can create a step with a map of params" do
#       step = Step.new(%{name: "test_step", work: &TestRunner.squareaplier/1})

#       assert match?(%Step{}, step)
#     end

#     test "we can create a step with a keyword list of params" do
#       step = Step.new(name: "test_step", work: &TestRunner.squareaplier/1)

#       assert match?(%Step{}, step)
#     end

#     test "without required params a step isn't runnable" do
#       step = Step.new(name: "test_step", work: &TestRunner.squareaplier/1)

#       assert Step.can_run?(step) == :error
#     end
#   end

#   describe "evaluate_runnability/1" do
#     test "a valid step has a name, work, input, no result, a run_id, and a runner" do
#       step = Step.new(
#         name: "test_step",
#         work: &TestRunner.squareaplier/1,
#         input: 2,
#         runner: TestRunner
#       )
#       |> Step.assign_run_id()

#       assert Step.can_run?(step) == :ok
#     end

#     test "setting the last required value will make a step runnable" do
#       invalid_step = Step.new(
#         name: "test_step",
#         work: &TestRunner.squareaplier/1,
#         runner: TestRunner
#       )
#       |> Step.evaluate_runnability()
#       |> Step.assign_run_id()

#       assert Step.can_run?(invalid_step) == :error

#       valid_step = Step.set_input(invalid_step, 2)
#       assert Step.can_run?(valid_step) == :ok
#     end
#   end

#   describe "add_step/2" do
#     test "we can add a dependent step to a parent" do
#       parent_step = Step.new(
#         name: "parent_test_step",
#         work: &TestRunner.squareaplier/1,
#         input: 2,
#         runner: TestRunner
#       ) |> Step.evaluate_runnability()

#       child_step = Step.new(
#         name: "child_test_step",
#         work: &TestRunner.squareaplier/1,
#         input: nil,
#         runner: TestRunner
#       ) |> Step.evaluate_runnability()

#       parent_with_dependent_step = Step.add_step(parent_step, child_step)

#       assert match?(parent_with_dependent_step, %Step{steps: %{child_step.name => child_step}})
#     end
#   end

#   describe "run/1" do
#     test "if the step isn't runnable, we return an error" do
#       invalid_step = Step.new(
#         name: "test_step",
#         work: &TestRunner.squareaplier/1,
#         runner: TestRunner
#       )

#       assert match?({:error, "step not runnable"}, Step.run(invalid_step))
#     end

#     test "a runnable step runs the work and puts the return into the result" do
#       step = Step.new(
#         name: "test_step",
#         work: &TestRunner.squareaplier/1,
#         input: 2,
#         runner: TestRunner
#       )
#       |> Step.assign_run_id()

#       {:ok, ran_step} = Step.run(step)

#       assert match?(%Step{result: 4}, ran_step)
#     end

#     test "dependent steps are evaluated when parent is ran" do
#       assert false
#     end

#     test "dependent steps are dispatched with the result of the parent step" do
#       # modify the test queue to hold state
#     end
#   end
# end
