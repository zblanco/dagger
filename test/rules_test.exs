defmodule RulesTest do
  use ExUnit.Case
  alias Dagger.Workflow.{Rule}
  alias Dagger.Workflow

  defmodule Examples do
    def is_potato?(:potato), do: true
    def is_potato?("potato"), do: true

    def new_potato(), do: :potato
    def new_potato(_), do: :potato

    def potato_baker(:potato), do: :baked_potato
    def potato_baker("potato"), do: :baked_potato

    def potato_transformer(_), do: :potato
  end

  describe "valid rules" do
    setup do
      {:ok, [
        stateless_rule: Rule.new(
          name: "stateless rule",
          description: "a stateless rule that runs regardless of the input",
          reaction: fn _any -> "potato" end,
        ),
        term_reaction_rule: Rule.new(
          name: "term_reaction",
          description: "a rule that always returns a term",
          reaction: "potato",
        ),
        zero_arity_reaction_rule: Rule.new(
          name: "term_reaction",
          description: "a rule that always returns a term",
          reaction: fn -> "potato" end,
        ),
        zero_arity_anonymous_function_rule: Rule.new(
          fn -> "potato" end
          name: "term_reaction",
          description: "a rule that always returns a term",
        ),
        anonymous_function_condition_rule: Rule.new(
          name: "anonymous_function_condition_rule",
          description: "a rule that always returns a term",
          condition: fn _anything -> true end,
          reaction: "potato",
        ),
        always_firing_anonymous_function_rule: Rule.new(
          condition: fn _anything -> true end,
          name: "a rule",
          description: "a rule from an anonymous function with an always matching lhs"
        ),
        rule_from_anonymous_function_with_condition: Rule.new(
          fn :potato -> "potato" end,
          name: "a rule",
          description: "a rule made from an anonymous function's lhs and rhs"
        ),
      ]}
    end

    test "a rule can be created with valid params" do
      anonymous_function_condition_rule = Rule.new(
          name: "anonymous_function_condition_rule",
          description: "a rule that always returns a term",
          condition: fn _anything -> true end,
          reaction: "potato",
      ),
    end

    test "a rule can be created from a single function or binary representation of function" do
      potato_fun = fn :potato -> :potato end
      potato_fun_string = "fn :potato -> :potato end"

      assert match?(%Rule{}, Rule.new(potato_fun))
      assert match?(%Rule{}, Rule.new(potato_fun_string))

      rule = Rule.new(potato_fun)

      assert rule.name == potato_fun_string
      assert :potato == Rule.run(rule, :potato)
      assert is_nil(rule.description)
    end

    test "we can create a rule that always fires" do
      always_fires_rule_arity_1 = Rule.new(fn _anything -> :potato end)
      always_fires_rule_arity_0 = Rule.new(fn -> :potato end)

      inputs = [
        "potato",
        "ham",
        1,
        nil,
        :potato
      ]

      assert Enum.all?(Enum.map(inputs, &Rule.check(always_fires_rule_arity_1, &1)))
      assert Enum.all?(Enum.map(inputs, &Rule.check(always_fires_rule_arity_0, &1)))

      assert Enum.all?(Enum.map(inputs, &Rule.run(always_fires_rule_arity_1, &1) == :potato))
      assert Enum.all?(Enum.map(inputs, &Rule.run(always_fires_rule_arity_0, &1) == :potato))
    end

    test "a rule can be made out of functions with an arity of 0 or 1" do
      assert match?(%Rule{}, Rule.new(fn _anything -> :potato end))
      assert match?(%Rule{}, Rule.new(fn -> :potato end))
      assert match?(%Rule{}, Rule.new(fn :potato -> :potato end))
      assert match?(%Rule{}, Rule.new(fn -> :potato end))
      assert match?(%Rule{}, Rule.new(&Examples.potato_baker/1))
      assert match?(%Rule{}, Rule.new(&Examples.potato_transformer/1))
    end

    test "a rule's reaction can return an arbitrary term" do
      term_rule = Rule.new(reaction: "potato")
      term_rule_with_condition = Rule.new(condition: &Examples.is_potato?/1, reaction: "potato")

      assert match?(%Rule{}, term_rule)
      assert Rule.check(term_rule, "anything") == "potato"
      assert Rule.check(term_rule, nil) == "potato"
    end

    test "a rule's condition can be composed of many conditions in a list" do
      rule_from_list_of_conditions = Rule.new(
        condition: [
          fn term -> term == "potato" end,
          &is_binary/1,
          fn term -> String.length(term) == 6 end,
          fn term when not is_integer(term) -> true end,
          &Examples.is_potato?/1
        ],
        reaction: "potato"
      )

      assert match?(%Rule{}, rule_from_list_of_conditions)
      assert Rule.check(rule_from_list_of_conditions, "potato") == true
      assert Rule.check(rule_from_list_of_conditions, "tomato") == false
      assert Rule.check(rule_from_list_of_conditions, 42) == false
      assert Rule.check(rule_from_list_of_conditions, :potato) == false

      assert Rule.run(rule_from_list_of_conditions, "potato") == "potato"
      assert Rule.run(rule_from_list_of_conditions, 42) == {:error, :condition_not_satisfied}
    end

    test "a rule's condition can be composed of many conditions built from guard clauses" do
      rule_from_guard_logic = Rule.new(
        fn
          term when term in [:potato, "potato"]
          and term != "tomato"
          and (
            binary_part(term, 0, 4) == "pota" or
            is_atom(term) and term == :potato
          )
        ->
          "potato!!"
        end)

      assert match?(%Rule{}, rule_from_guard_logic)
      refute Rule.check(rule_from_guard_logic, 42)
      assert Rule.check(rule_from_guard_logic, "potato")
      assert Rule.check(rule_from_guard_logic, :potato)
      assert Rule.run(rule_from_guard_logic, "potato") == "potato!!"
    end

    test "a rule's condition can be composed of many conditions built from guard clauses" do

    end
  end

end
