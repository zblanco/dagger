defmodule DaggerTest do
  use ExUnit.Case
  alias Dagger.Workflow.Step
  alias Dagger.Workflow.Rule
  alias Dagger.Workflow.StateMachine
  alias Dagger.Workflow
  require Dagger
  # import CompileTimeAssertions

  defmodule Examples do
    def is_potato?(:potato), do: true
    def is_potato?("potato"), do: true

    def new_potato(), do: :potato
    def new_potato(_), do: :potato

    def potato_baker(:potato), do: :baked_potato
    def potato_baker("potato"), do: :baked_potato

    def potato_transformer(_), do: :potato

    def potato_masher(:potato, :potato), do: :mashed_potato
    def potato_masher("potato", "potato"), do: :mashed_potato
  end

  describe "Dagger.rule/2 macro" do
    test "creates rules using anonymous functions" do
      rule1 = Dagger.rule(fn :potato -> "potato!" end, name: "rule1")
      rule2 = Dagger.rule(fn "potato" -> "potato!" end, name: "rule1")
      rule3 = Dagger.rule(fn :tomato -> "tomato!" end, name: "rule1")

      rule4 =
        Dagger.rule(fn item when is_integer(item) and item > 41 and item < 43 -> "fourty two" end,
          name: "rule1"
        )

      rule5 =
        Dagger.rule(
          fn item when is_integer(item) and item > 41 and item < 43 ->
            result = Enum.random(1..10)
            result
          end,
          name: "rule1"
        )

      rules = [rule1, rule2, rule3, rule4, rule5]

      Enum.each(rules, &assert(match?(%Rule{}, &1)))
    end

    test "created rules can be evaluated" do
      some_rule =
        Dagger.rule(fn item when is_integer(item) and item > 41 and item < 43 -> "fourty two" end,
          name: "rule1"
        )

      assert Rule.check(some_rule, 42)
      refute Rule.check(some_rule, 45)
      assert Rule.run(some_rule, 42) == "fourty two"
    end

    test "a valid rule can be created from functions an arity > 1" do
      rule =
        Dagger.rule(
          fn num, other_num when is_integer(num) and is_integer(other_num) -> num * other_num end,
          name: "multiplier"
        )

      assert match?(%Rule{}, rule)
      # if we want this to return false - should we store context of a rule's arity?
      assert Rule.check(rule, :potato) == false
      assert Rule.check(rule, 10) == false
      assert Rule.check(rule, 1) == false
      assert Rule.check(rule, [1, 2]) == true
      assert Rule.check(rule, [:potato, "tomato"]) == false
      assert Rule.run(rule, [10, 2]) == 20
      assert Rule.run(rule, [2, 90]) == 180
    end
  end

  describe "Dagger.step constructors" do
    test "a Step can be created with params using Dagger.step/1" do
      assert match?(%Step{}, Dagger.step(work: fn -> :potato end, name: "potato"))
    end

    test "a Step can be created with params using Dagger.step/2" do
      assert match?(%Step{}, Dagger.step(fn -> :potato end, name: "potato"))
      assert match?(%Step{}, Dagger.step(fn _ -> :potato end, name: "potato"))

      assert match?(
               %Step{},
               Dagger.step(fn something -> something * something end, name: "squarifier")
             )

      assert match?(%Step{}, Dagger.step(&Examples.potato_baker/1, name: "potato_baker"))
      assert match?(%Step{}, Dagger.step(&Examples.potato_transformer/1, name: "potato_baker"))
      assert match?(%Step{}, Dagger.step(&Examples.potato_baker/1))
      assert match?(%Step{}, Dagger.step(&Examples.potato_transformer/1))
    end

    test "a Step can be run for localized testing" do
      squarifier_step = Dagger.step(fn something -> something * something end, name: "squarifier")

      assert 4 == Dagger.Workflow.Step.run(squarifier_step, 2)
    end
  end

  describe "Dagger.workflow/1 constructor" do
    test "constructs an operable %Workflow{} given a set of steps" do
      steps_to_add = [
        Dagger.step(fn something -> something * something end, name: "squarifier"),
        Dagger.step(fn something -> something * 2 end, name: "doubler"),
        Dagger.step(fn something -> something * -1 end, name: "negator")
      ]

      workflow =
        Dagger.workflow(
          name: "a test workflow",
          steps: steps_to_add
        )

      assert match?(%Workflow{}, workflow)

      steps = Dagger.Workflow.steps(workflow)

      assert Enum.any?(steps, &Enum.member?(steps_to_add, &1))
    end

    test "constructs an operable %Workflow{} given a tree of dependent steps" do
      workflow =
        Dagger.workflow(
          name: "a test workflow with dependent steps",
          steps: [
            {Dagger.step(fn x -> x * x end, name: "squarifier"),
             [
               Dagger.step(fn x -> x * -1 end, name: "negator"),
               Dagger.step(fn x -> x * 2 end, name: "doubler")
             ]},
            {Dagger.step(fn x -> x * 2 end, name: "doubler"),
             [
               {Dagger.step(fn x -> x * 2 end, name: "doubler"),
                [
                  Dagger.step(fn x -> x * 2 end, name: "doubler"),
                  Dagger.step(fn x -> x * -1 end, name: "negator")
                ]}
             ]}
          ]
        )

      assert match?(%Workflow{}, workflow)
    end

    test "constructs an operable %Workflow{} given a set of rules" do
      workflow =
        Dagger.workflow(
          name: "a test workflow",
          rules: [
            Dagger.rule(fn :foo -> :bar end, name: "foobar"),
            Dagger.rule(fn :potato -> :tomato end, name: "tomato when potato"),
            Dagger.rule(
              fn item when is_integer(item) and item > 41 and item < 43 ->
                "the answer to life the universe and everything"
              end,
              name: "what about the question?"
            )
          ]
        )

      assert match?(%Workflow{}, workflow)
    end
  end

  describe "Dagger.state_machine/1" do
    test "constructs a Flowable %StateMachine{} given a name, init, and a reducer expression" do
      state_machine =
        Dagger.state_machine(
          name: "adds integers of some factor to its state up until 30 then stops",
          init: 0,
          reducer: fn
            num, state when is_integer(num) and state >= 0 and state < 10 -> state + num * 1
            num, state when is_integer(num) and state >= 10 and state < 20 -> state + num * 2
            num, state when is_integer(num) and state >= 20 and state < 30 -> state + num * 3
            _num, state -> state
          end
        )

      assert match?(%StateMachine{}, state_machine)

      wrk = Dagger.Flowable.to_workflow(state_machine)

      assert match?(%Workflow{}, wrk)
    end

    test "reactors can be included to respond to state changes" do
      potato_lock =
        Dagger.state_machine(
          name: "potato lock",
          init: %{code: "potato", state: :locked, contents: "ham"},
          reducer: fn
            :lock, state ->
              %{state | state: :locked}

            {:unlock, input_code}, %{code: code, state: :locked} = state
            when input_code == code ->
              %{state | state: :unlocked}

            {:unlock, _input_code}, %{state: :locked} = state ->
              state

            _input_code, %{state: :unlocked} = state ->
              state
          end,
          reactors: [
            fn %{state: :unlocked, contents: contents} -> contents end,
            fn %{state: :locked} -> {:error, :locked} end
          ]
        )

      productions_from_1_cycles =
        potato_lock.workflow
        |> Workflow.plan_eagerly({:unlock, "potato"})
        |> Workflow.react()
        |> Workflow.productions()

      assert Enum.count(productions_from_1_cycles) == 2

      workflow_after_2_cycles =
        potato_lock.workflow
        |> Workflow.plan_eagerly({:unlock, "potato"})
        |> Workflow.react()
        |> Workflow.plan()
        |> Workflow.react()

      assert Enum.count(Workflow.productions(workflow_after_2_cycles)) == 3

      assert "ham" in Workflow.raw_reactions(workflow_after_2_cycles)
    end
  end
end
