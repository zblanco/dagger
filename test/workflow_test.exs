defmodule WorkflowText do
  use ExUnit.Case
  alias Dagger.Workflow.{Rule, Step, Fact}
  alias Dagger.Workflow
  alias Dagger.TestRunner

  defmodule TextProcessing do
    def tokenize(text) do
      text
      |> String.downcase
      |> String.split(~R/[^[:alnum:]\-]/u, trim: true)
    end

    def count_words(list_of_words) do
      list_of_words
      |> Enum.reduce(Map.new, fn(word, map) ->
        Map.update(map, word, 1, &(&1 + 1))
      end)
    end
  end

  defmodule Counting do
    def initiator(:start_count), do: true
    def initiation(_), do: 0

    def do_increment?(:count, count), do: true
    def incrementer(count) when is_integer(count), do: count + 1
  end

  defmodule Lock do
    def locked?(:locked), do: true
    def locked?(_), do: false

    def lock(_), do: :locked
    def unlock(_), do: :unlocked
  end

  describe "rules" do
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
    test "a workflow can be connected to another workflow as a dependent step" do
      assert false
    end
  end

  describe "use cases" do

    test "counter accumulation with triggers" do
      wrk =
        Workflow.new(name: "counter accumulator")
        |> Workflow.add_accumulator(Accumulator.new(
          Rule.new(
            name: "counter accumulator initiation",
            description: "A rule that reacts to a :start_count message by starting a counter at 0",
            condition: &Counting.initiator/1, # trigger for accumulation
            reaction: &Counting.initiation/1 # sets initial state (initial state wants the initiating fact - conditions just activate)
          ),
          [ # state reactors match on both current state AND other conditions
            Rule.new(
              name: "counter incrementer",
              description: "A rule that reacts to a command to increment with the current counter state",
              condition: &Counting.do_increment?/2, # accumulator conditions handle a Condition clause with two arguments OR a Condition with at least a state and another fact
              reaction: &Counting.incrementer/1
            ),
          ]
        ))

      reactions = Workflow.react(wrk, [:start_count, :count, :count, :count])
      assert match?(List.last(reactions), %Fact{type: :state_produced, value: 2})
    end

    test "simple lock" do
      wrk =
        Workflow.new(name: "simple lock")
        |> Workflow.add_accumulator(
          name: "represents the state of a lock",
          init: :locked,
          reactors: [
            Rule.new(
              name: "unlocks a locked lock",
              description: "if locked, unlocks",
              condition: &Lock.locked?/2,
              reaction: &Lock.unlock/1
            ),
            Rule.new(
              name: "locks an unlocked lock",
              description: "if locked, unlocks",
              condition: &Lock.unlocked?/2,
              reaction: &Lock.unlock/1
            ),
          ]
        )

      assert false
    end

    test "text processing pipeline" do
      wrk =
        Workflow.new(name: "basic text processing pipeline")
        |> Workflow.add_step(:root, Step.new(name: "tokenize", work: &TextProcessing.tokenize/1))
        |> Workflow.add_step("tokenize", Step.new(name: "count words", work: &TextProcessing.count_words/1))

      reaction = Workflow.react(wrk, "anybody want a peanut")

      assert match?(reaction, %Fact{})
      assert reaction.value == 4
    end
  end

end
