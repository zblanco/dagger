defmodule WorkflowTest do
  use ExUnit.Case
  alias Dagger.Workflow.{Rule, Step, Fact, Runnable}
  alias Dagger.Workflow
  alias Dagger.TestRunner
  require Dagger

  defmodule TextProcessing do
    def tokenize(text) do
      text
      |> String.downcase()
      |> String.split(~R/[^[:alnum:]\-]/u, trim: true)
    end

    def count_words(list_of_words) do
      list_of_words
      |> Enum.reduce(Map.new(), fn word, map ->
        Map.update(map, word, 1, &(&1 + 1))
      end)
    end

    def count_uniques(word_count) do
      Enum.count(word_count)
    end

    def first_word(list_of_words) do
      List.first(list_of_words)
    end

    def last_word(list_of_words) do
      List.last(list_of_words)
    end
  end

  defmodule Counting do
    def initiator(:start_count), do: true
    def initiation(_), do: 0

    def do_increment?(:count, _count), do: true
    def incrementer(count) when is_integer(count), do: count + 1
  end

  defmodule Lock do
    def locked?(:locked), do: true
    def locked?(_), do: false

    def lock(_), do: :locked
    def unlock(_), do: :unlocked
  end

  defmodule TestWorkflows do
    def basic_text_processing_pipeline() do
      Dagger.workflow(
        name: "basic text processing example",
        steps: [
          {Dagger.step(name: "tokenize", work: &TextProcessing.tokenize/1),
           [
             {Dagger.step(name: "count words", work: &TextProcessing.count_words/1),
              [
                Dagger.step(name: "count unique words", work: &TextProcessing.count_uniques/1)
              ]},
             Dagger.step(name: "first word", work: &TextProcessing.first_word/1),
             Dagger.step(name: "last word", work: &TextProcessing.last_word/1)
           ]}
        ]
      )
    end

    def counter_accumulator_with_triggers() do
      # Dagger.accumulator(

      # )

      Workflow.new(name: "counter accumulator")
      |> Workflow.add_accumulator(
        Accumulator.new(
          Dagger.rule(
            name: "counter accumulator initiation",
            description:
              "A rule that reacts to a :start_count message by starting a counter at 0",
            # trigger for accumulation
            condition: &Counting.initiator/1,
            # sets initial state (initial state wants the initiating fact - conditions just activate)
            reaction: &Counting.initiation/1
          ),
          # state reactors match on both current state AND other conditions
          [
            Dagger.rule(
              name: "counter incrementer",
              description:
                "A rule that reacts to a command to increment with the current counter state",
              # accumulator conditions handle a Condition clause with two arguments OR a Condition with at least a state and another fact
              condition: &Counting.do_increment?/2,
              reaction: &Counting.incrementer/1
            )
          ]
        )
      )
    end

    # def simple_lock() do
    #   Workflow.new(name: "simple lock")
    #   |> Workflow.add_accumulator(
    #     name: "represents the state of a lock",
    #     init: :locked,
    #     reactors: [
    #       Dagger.rule(
    #         name: "unlocks a locked lock",
    #         description: "if locked, unlocks",
    #         condition: &Lock.locked?/2,
    #         reaction: &Lock.unlock/1
    #       ),
    #       Dagger.rule(
    #         name: "locks an unlocked lock",
    #         description: "if locked, unlocks",
    #         condition: &Lock.unlocked?/2,
    #         reaction: &Lock.unlock/1
    #       )
    #     ]
    #   )
    # end
  end

  def setup_test_pipelines(_context) do
    {:ok,
     [
       basic_text_processing_pipeline: TestWorkflows.basic_text_processing_pipeline()
       #  counter_accumulator_with_triggers: TestWorkflows.counter_accumulator_with_triggers(),
       #  simple_lock: TestWorkflows.simple_lock()
     ]}
  end

  describe "workflow construction" do
    test "creating a new workflow" do
      assert match?(%Workflow{}, Workflow.new("workflow"))
    end

    test "defining a workflow using the macro/keyword syntax" do
      an_existing_rule = Dagger.rule(fn :bar -> :foo end, name: "barfoo")

      Dagger.workflow(
        name: "a test workflow",
        accumulators: [
          Dagger.accumulator(
            name: "fancy counter",
            init: 0,
            reducers: [
              fn
                num when num <= 10 -> num + 1
                num when num > 10 -> num + 2
                num when num > 20 -> num + 2
              end,
              Dagger.rule(
                fn num when num > 30 -> num + 3 end,
                name: "greater than 30 increment more",
                description: "when the number is greater than 30 we increment by 3"
              )
            ]
          )
        ],
        rules: [
          Dagger.rule(fn :foo -> :bar end,
            name: "test rule",
            description: "a rule description"
          ),
          fn
            :potato -> "potato!"
            "potato" -> "potato!"
            :tomato -> "tomato!"
            item when is_integer(item) and item > 41 and item < 43 -> "fourty two"
          end,
          an_existing_rule
        ]
      )
    end

    test "adding a step" do
    end

    test "adding steps to other steps" do
    end

    test "adding an existing step to another existing step makes no changes" do
    end

    test "adding rules" do
    end

    test "adding accumulators" do
    end
  end

  describe "left hand side / match phase evaluation" do
    test "plan/2 evaluates a single layer of the match phase with an external input" do
      workflow =
        Dagger.workflow(
          name: "test workflow",
          rules: [
            Dagger.rule(
              fn
                :potato -> "potato!"
                :tomato -> "tomato!"
              end,
              name: "rule1"
            ),
            Dagger.rule(
              fn item when is_integer(item) and item > 41 and item < 43 ->
                result = Enum.random(1..10)
                result
              end,
              name: "rule2"
            )
          ]
        )

      wrk = Workflow.plan(workflow, :potato)

      assert Enum.count(Workflow.next_runnables(wrk)) == 1
      assert Enum.count(wrk.facts) == 1
    end

    test "plan/1 evaluates a single layer" do
      workflow =
        Dagger.workflow(
          name: "test workflow",
          rules: [
            Dagger.rule(
              fn
                :potato -> "potato!"
                :tomato -> "tomato!"
              end,
              name: "rule1"
            ),
            Dagger.rule(
              fn item when is_integer(item) and item > 41 and item < 43 ->
                result = Enum.random(1..10)
                result
              end,
              name: "rule2"
            )
          ]
        )

      wrk = Workflow.plan(workflow, :potato)

      Workflow.plan(workflow)
    end
  end

  describe "workflow cycles / evaluation" do
    test "a workflow made of many rules and conditions can evaluate a composition of the rules" do
      workflow =
        Dagger.workflow(
          name: "test workflow",
          rules: [
            Dagger.rule(
              fn
                :potato -> "potato!"
                :tomato -> "tomato!"
              end,
              name: "rule1"
            ),
            Dagger.rule(
              fn item when is_integer(item) and item > 41 and item < 43 ->
                result = Enum.random(1..10)
                result
              end,
              name: "rule2"
            )
          ]
        )

      wrk = Workflow.plan_eagerly(workflow, :potato)

      assert Enum.count(Workflow.next_runnables(wrk)) == 1
      assert Enum.any?(wrk.facts, &match?(%{value: :satisfied}, &1))

      # a user ought to be able to run a concurrent set of runnables at this point
      # but the api for doing so needs to not require a reduce + activate + agenda cycling as that's too complex

      next_facts =
        Workflow.next_runnables(wrk)
        |> Enum.map(fn {work, input} -> Dagger.Runnable.run(work, input) end)
        |> IO.inspect(label: "next facts")

      assert match?(%{value: "potato!"}, List.first(next_facts))

      wrk = Workflow.plan_eagerly(workflow, 42)
      assert Enum.count(Workflow.next_runnables(wrk)) == 1

      [%{value: result_value} | _rest] =
        Workflow.next_runnables(wrk)
        |> Enum.map(fn {work, input} -> Dagger.Runnable.run(work, input) end)

      assert is_integer(result_value)
    end
  end

  describe "rules" do
    setup [:setup_test_pipelines]

    test "construction with new/1" do
      assert false
    end

    test "conditions must be functions" do
      assert false
    end

    test "a rule's condition must return a boolean" do
      assert false
    end

    test "a rule's reaction always returns a fact" do
      assert false
    end
  end

  describe "workflow composition" do
    setup [:setup_test_pipelines]

    test "a workflow can be merged into another workflow" do
      assert false
    end

    test "a stateless pipeline workflow can be attached to another workflow as a dependent step" do
      assert false
    end
  end

  describe "use cases" do
    setup [:setup_test_pipelines]

    # test "counter accumulation with triggers", %{counter_accumulator_with_triggers: wrk} do
    #   reactions = Workflow.react(wrk, [:start_count, :count, :count, :count])

    #   # assert match?(List.last(reactions), %Fact{type: :state_produced, value: 2})
    # end

    # test "simple lock", %{simple_lock: wrk} do
    #   assert false
    # end

    test "text processing pipeline", %{basic_text_processing_pipeline: wrk} do
      wrk =
        wrk
        |> Workflow.plan_eagerly("anybody want a peanut")

      wrk =
        Enum.reduce(
          Workflow.next_runnables(wrk),
          wrk,
          fn {step, fact}, wrk ->
            Workflow.plan_eagerly(wrk, Dagger.Runnable.run(step, fact))
          end
        )
        |> IO.inspect()
    end
  end
end
