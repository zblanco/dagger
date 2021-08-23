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
          {Dagger.step(name: "tokenize", work: &TextProcessing.tokenize/1), [
            {Dagger.step(name: "count words", work: &TextProcessing.count_words/1), [
              Dagger.step(name: "count unique words", work: &TextProcessing.count_uniques/1)
            ]}
          ]}
        ]
      )
    end

    def counter_accumulator_with_triggers() do
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
       basic_text_processing_pipeline: TestWorkflows.basic_text_processing_pipeline(),
      #  counter_accumulator_with_triggers: TestWorkflows.counter_accumulator_with_triggers(),
      #  simple_lock: TestWorkflows.simple_lock()
     ]}
  end

  describe "Workflow.stream/2" do
    setup [:setup_test_pipelines]

    test "stream/2 each cycle of a workflow stream returns a transformed workflow with a new agenda",
         %{basic_text_processing_pipeline: wrk} do
      cycle_1_workflow = Workflow.run(wrk, "anybody want a peanut?")
      # just a getter for %Workflow{agenda: agenda} -> agenda
      cycle_1_agenda = Workflow.agenda(cycle_1_workflow)

      # first cycle produces a runnable with the first step and our input
      assert length(cycle_1_agenda) == 1

      assert match?(cycle_1_agenda, [
               {%Step{name: "tokenize"}, %Fact{value: "anybody want a peanut?"}}
             ])

      # this operation is always embarassingly parallel
      cycle_1_results = Enum.map(cycle_1_agenda, &Runnable.run(&1))

      cycle_2_workflow = Workflow.run(cycle_1_workflow, cycle_1_results)
      cycle_2_agenda = Workflow.agenda(cycle_2_workflow)

      assert length(cycle_2_agenda) == 1

      assert match?(cycle_2_agenda, [
               {%Step{name: "count words"}, %Fact{value: ["anybody", "want", "a", "peanut?"]}}
             ])

      cycle_2_results = Enum.map(cycle_1_agenda, &Runnable.run(&1))

      cycle_3_workflow = Workflow.run(cycle_2_workflow, cycle_2_results)
      cycle_3_agenda = Workflow.agenda(cycle_3_workflow)

      assert length(cycle_3_agenda) == 1

      assert match?(cycle_3_agenda, [
               {%Step{name: "count words"}, %Fact{}}
             ])
    end
  end

  describe "workflow construction" do
    test "creating a new workflow" do
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
          end, # should result in 4 rules for each clause and additional guard check conditions to the root of the workflow

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

      wrk = Workflow.plan(workflow, :potato)

      assert Enum.count(Workflow.next_runnables(wrk)) == 1
      assert Enum.count(wrk.facts) == 2

      # a user ought to be able to run a concurrent set of runnables at this point
      # but the api for doing so needs to not require a reduce + activate + agenda cycling as that's too complex

      ran_runnables =
        Workflow.next_runnables(wrk)
        |> Enum.map(& Dagger.Workflow.Steps.run(&1))

      wrk = Workflow.run(wrk)

      assert Enum.count(wrk.facts) == 3
      assert Workflow.reactions(wrk) == ["potato!"]
      assert wrk.agenda.cycles == 1

      wrk = Workflow.plan(wrk, :tomato)

      assert Enum.count(wrk.agenda.runnables) == 1

      wrk = Workflow.run(wrk)
      assert Workflow.reactions(wrk) == ["tomato!", "potato!"]
      assert wrk.agenda.cycles == 2
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

    test "counter accumulation with triggers", %{counter_accumulator_with_triggers: wrk} do
      reactions = Workflow.react(wrk, [:start_count, :count, :count, :count])

      # assert match?(List.last(reactions), %Fact{type: :state_produced, value: 2})
    end

    test "simple lock", %{simple_lock: wrk} do
      assert false
    end

    test "text processing pipeline", %{basic_text_processing_pipeline: wrk} do
      reactions = Workflow.react(wrk, "anybody want a peanut") |> Enum.to_list()
      latest_reaction = List.first(reactions)
      assert match?(latest_reaction, %Fact{})
      assert latest_reaction.value == 4
    end
  end
end
