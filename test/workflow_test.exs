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

  describe "workflow api" do
    test "reactions/1 returns a list of facts ingested or produced throughout the workflow" do
      wrk =
        Dagger.workflow(
          name: "test",
          steps: [
            Dagger.step(fn num -> num * 2 end),
            Dagger.step(fn num -> num * 3 end),
            Dagger.step(fn num -> num * 4 end)
          ]
        )

      reactions =
        wrk
        |> Workflow.plan_eagerly(10)
        |> Workflow.react()
        |> Workflow.reactions()

      assert match?([%Fact{} | _], reactions)
      assert Enum.count(reactions) == 4

      for fact <- reactions, do: assert(fact.value in [10, 20, 30, 40])
    end

    test "raw_reactions/1 returns a list of fact values ingested or produced throughout the workflow" do
      wrk =
        Dagger.workflow(
          name: "test",
          steps: [
            Dagger.step(fn num -> num * 2 end),
            Dagger.step(fn num -> num * 3 end),
            Dagger.step(fn num -> num * 4 end)
          ]
        )

      reactions =
        wrk
        |> Workflow.plan_eagerly(10)
        |> Workflow.react()
        |> Workflow.raw_reactions()

      assert match?([_ | _], reactions)
      assert Enum.count(reactions) == 4

      for reaction <- reactions, do: assert(reaction in [10, 20, 30, 40])
    end

    test "matches/1 returns a list of matched conditions throughout the workflow evaluation" do
      wrk =
        Dagger.workflow(
          name: "test",
          rules: [
            Dagger.rule(fn
              :potato -> "potato!"
            end),
            Dagger.rule(fn
              :tomato -> "tomato!"
            end)
          ]
        )

      matches =
        wrk
        |> Workflow.plan_eagerly(:potato)
        |> Workflow.matches()

      assert match?([_ | _], matches)
      assert Enum.count(matches) == 2

      for match <- matches, do: assert(is_integer(match))
    end
  end

  describe "workflow construction" do
    test "creating a new workflow" do
      assert match?(%Workflow{}, Workflow.new("workflow"))
    end

    test "defining a workflow using the macro/keyword syntax" do
      an_existing_rule = Dagger.rule(fn :bar -> :foo end, name: "barfoo")

      wrk =
        Dagger.workflow(
          name: "a test workflow",
          rules: [
            Dagger.rule(fn :foo -> :bar end,
              name: "test rule",
              description: "a rule description"
            ),
            Dagger.rule(fn
              :potato -> "potato!"
            end),
            an_existing_rule
          ]
        )

      assert match?(%Workflow{}, wrk)
    end

    # test "adding a step" do
    # end

    # test "adding steps to other steps" do
    # end

    # test "adding an existing step to another existing step makes no changes i.e. idempotency" do
    # end

    # test "adding rules" do
    # end

    # test "adding accumulators" do
    # end
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

      assert Workflow.can_react?(wrk)
      assert wrk |> Workflow.matches() |> Enum.count() == 1
    end

    test "plan/1 evaluates a single layer" do
      workflow =
        Dagger.workflow(
          name: "test workflow",
          rules: [
            Dagger.rule(
              fn
                :potato -> "potato!"
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

      wrk.memory
      |> IO.inspect(label: "memory")

      wrk
      |> Workflow.matches()
      |> IO.inspect(label: "matches")
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
      assert not is_nil(Workflow.matches(wrk))

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

  describe "stateful workflow models" do
    test "joins are steps where many parents must have ran and produced consequent facts" do
      join_with_1_dependency =
        Dagger.workflow(
          name: "workflow with joins",
          steps: [
            {[Dagger.step(fn num -> num * 2 end), Dagger.step(fn num -> num * 3 end)],
             [
               Dagger.step(fn num_1, num_2 -> num_1 * num_2 end)
             ]}
          ]
        )

      assert match?(%Workflow{}, join_with_1_dependency)

      j_1 =
        join_with_1_dependency
        |> Workflow.plan_eagerly(2)

      assert Enum.count(Workflow.next_runnables(j_1)) == 2

      j_1_runnables_after_reaction =
        j_1
        |> Workflow.react()
        |> Workflow.next_runnables()

      assert Enum.count(j_1_runnables_after_reaction) == 2

      j_1_runnables_after_third_reaction =
        j_1
        |> Workflow.react()
        |> Workflow.react()
        |> Workflow.react()
        |> Workflow.raw_reactions()

      assert 24 in j_1_runnables_after_third_reaction

      join_with_many_dependencies =
        Dagger.workflow(
          name: "workflow with joins",
          steps: [
            {[Dagger.step(fn num -> num * 2 end), Dagger.step(fn num -> num * 3 end)],
             [
               Dagger.step(fn num_1, num_2 -> num_1 * num_2 end),
               Dagger.step(fn num_1, num_2 -> num_1 + num_2 end),
               Dagger.step(fn num_1, num_2 -> num_2 - num_1 end)
             ]}
          ]
        )

      assert match?(%Workflow{}, join_with_many_dependencies)

      assert join_with_many_dependencies
             |> Workflow.plan(2)
             |> Workflow.next_runnables()
             |> Enum.count() == 2

      assert join_with_many_dependencies
             |> Workflow.react(2)
             |> Workflow.react()
             |> Workflow.next_runnables()
             |> Enum.count() == 3

      reacted_join_with_many_dependencies =
        join_with_many_dependencies
        |> Workflow.react_until_satisfied(2)
        |> Workflow.raw_reactions()

      assert 24 in reacted_join_with_many_dependencies
      assert 10 in reacted_join_with_many_dependencies
      assert 2 in reacted_join_with_many_dependencies
    end

    test "stateful rules" do
    end

    test "accumulations" do
    end
  end

  # describe "workflow activation protocol interactions" do
  #   test "a join activates when its parent steps have produced its required facts combining the two steps in fact with binding context" do
  #     wrk =
  #       Dagger.workflow(
  #         name: "join_wrk",
  #         steps: [
  #           Dagger.step()

  #       ])
  #   end
  # end

  # describe "workflow identity and reflection" do
  #   setup do
  #     rule_1 = Dagger.rule(
  #       fn
  #         :potato -> "potato!"
  #       end,
  #       name: "rule_1"
  #     )

  #     rule_2 = Dagger.rule(
  #       fn item when is_integer(item) and item > 41 and item < 43 ->
  #         result = Enum.random(1..10)
  #         result
  #       end,
  #       name: "rule_2"
  #     )

  #     workflow =
  #       Dagger.workflow(
  #         name: "test workflow",
  #         rules: [
  #           rule_1, rule_2
  #         ]
  #       )

  #     {:ok, [workflow: workflow, rules: [rule_1, rule_2]]}
  #   end

  #   test "Workflow.fetch/2 can use the `:name` or `:hash` to find a workflow component", %{workflow: workflow, rules: [rule_1 | _]} do
  #     assert rule_1 == Workflow.fetch(workflow, name: rule_1.name)
  #     assert rule_1 == Workflow.fetch(workflow, hash: rule_1.hash)
  #   end

  #   test "Workflow.components/1 returns a list of named components the workflow consists of", %{workflow: workflow, rules: rules} do
  #     assert Enum.all?(rules, & &1 in Workflow.components(workflow))
  #   end

  #   test "Workflow.components_by_name/1 returns a map of named components in the workflow by name", %{workflow: workflow, rules: rules} do
  #     components_by_name = Workflow.components_by_name(workflow)

  #     assert Enum.all?(rules, & &1.name in Map.keys(components_by_name))
  #     assert Enum.all?(rules, & &1 in Map.values(components_by_name))
  #   end

  #   test "Workflow.rules/1 returns a list of the rules present in the workflow", %{workflow: workflow, rules: rules} do
  #     assert Enum.all?(rules, & &1 in Workflow.rules(workflow))
  #   end

  #   test "Workflow.steps/1 returns a list of the steps present in the workflow" do
  #     steps = [
  #       Dagger.step(fn num -> num * 2 end),
  #       Dagger.step(fn num -> num - 2 end),
  #       Dagger.step(fn num -> num + 2 end),
  #     ]

  #     wrk = Dagger.workflow(name: "two step", steps: steps)

  #     assert Enum.all?(steps, & &1 in Workflow.steps(wrk))
  #   end

  #   test "Workflow.conditions/1 returns a list of the conditions present in the workflow" do
  #     rules = [
  #       Dagger.rule(fn num when num == 2 -> num * 2 end),
  #       Dagger.rule(fn num when num != 2-> num + 2 end),
  #     ]

  #     wrk = Dagger.workflow(name: "two rules", rules: rules)

  #     # assert Enum.all?(steps, & &1 in Workflow.steps(wrk))

  #   end

  #   test "Workflow.conjunctions/1 returns a list of the conjunctions present in the workflow" do

  #   end

  #   test "Workflow.accumulators/1 returns a list of the accumulators present in the workflow" do

  #   end
  # end

  describe "workflow composition" do
    test "a workflow can be merged into another workflow" do
      text_processing_workflow = TestWorkflows.basic_text_processing_pipeline()

      some_other_workflow =
        Dagger.workflow(
          name: "test workflow",
          rules: [
            Dagger.rule(
              fn
                :potato -> "potato!"
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

      new_wrk = Workflow.merge(text_processing_workflow, some_other_workflow)
      assert match?(%Workflow{}, new_wrk)

      text_processing_workflow
      |> Workflow.react_until_satisfied("anybody want a peanut?")
      |> Workflow.reactions()
    end

    test "a stateless pipeline workflow can be attached to another workflow as a dependent step" do
      assert false
    end

    test "a rule can be triggered from an accumulation event" do
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
    end
  end
end
