defmodule RulesTest do
  use ExUnit.Case
  alias Dagger.Workflow.{Rule}
  alias Dagger.Workflow
  require Dagger

  defmodule Examples do
    def is_potato?(:potato), do: true
    def is_potato?("potato"), do: true

    def new_potato(), do: :potato
    def new_potato(_), do: :potato

    def potato_baker(:potato), do: :baked_potato
    def potato_baker("potato"), do: :baked_potato

    def potato_transformer(_), do: :potato

    def potato_block_transformer(_), do: :potato
  end

  describe "valid rules" do
    setup do
      {:ok,
       [
         stateless_rule:
           Dagger.rule(
             name: "stateless rule",
             description: "a stateless rule that runs regardless of the input",
             reaction: fn _any -> "potato" end
           ),
         term_reaction_rule:
           Dagger.rule(
             name: "term_reaction",
             description: "a rule that always returns a term",
             reaction: "potato"
           ),
         zero_arity_reaction_rule:
           Dagger.rule(
             name: "term_reaction",
             description: "a rule that always returns a term",
             reaction: fn -> "potato" end
           ),
         zero_arity_anonymous_function_rule:
           Dagger.rule(
             fn -> "potato" end,
             name: "term_reaction",
             description: "a rule that always returns a term"
           ),
         anonymous_function_condition_rule:
           Dagger.rule(
             name: "anonymous_function_condition_rule",
             description: "a rule that always returns a term",
             condition: fn _anything -> true end,
             reaction: "potato"
           ),
         always_firing_anonymous_function_rule:
           Dagger.rule(
             condition: fn _anything -> true end,
             reaction: "potato",
             name: "a rule",
             description: "a rule from an anonymous function with an always matching lhs"
           ),
         rule_from_anonymous_function_with_condition:
           Dagger.rule(
             fn :potato -> "potato" end,
             name: "a rule",
             description: "a rule made from an anonymous function's lhs and rhs"
           )
       ]}
    end

    test "a rule can be created with valid params" do
      assert match?(
               %Rule{},
               Dagger.rule(
                 name: "anonymous_function_condition_rule",
                 description: "a rule that always returns a term",
                 condition: fn _anything -> true end,
                 reaction: "potato"
               )
             )
    end

    # test "a rule can be created from a single function or binary representation of function" do
    #   rule = Dagger.rule(fn :potato -> :potato end, name: "potato rule")

    #   assert match?(%Rule{}, rule)

    #   assert match?(
    #            %Rule{},
    #            Dagger.rule("fn :potato -> :potato end", name: "potato rule from string function")
    #          )

    #   assert :potato == Rule.run(rule, :potato)
    #   assert is_nil(rule.description)
    # end

    test "we can create a rule that always fires" do
      always_fires_rule_arity_1 = Dagger.rule(fn _anything -> :potato end, name: "1_arity_rule") |> IO.inspect(label: "1_arity_rule")
      always_fires_rule_arity_0 = Dagger.rule(fn -> :potato end, name: "0_arity_rule") |> IO.inspect(label: "0_arity_rule")

      inputs = [
        "potato",
        "ham",
        1,
        nil,
        :potato
      ]

      assert Enum.all?(Enum.map(inputs, &Rule.check(always_fires_rule_arity_1, &1)))
      assert not Enum.any?(Enum.map(inputs, &Rule.check(always_fires_rule_arity_0, &1)))

      assert Enum.all?(Enum.map(inputs, &(Rule.run(always_fires_rule_arity_1, &1) == :potato)))
      Enum.map(inputs, &(Rule.run(always_fires_rule_arity_0, &1) == :potato)) |> IO.inspect(label: "Rule.run/2 on :potato")
    end

    test "a rule can be made out of functions with an arity of 0 or 1" do
      assert match?(
               %Rule{},
               Dagger.rule(fn _anything -> :potato end, name: "1_arity_anything_rule")
             )

      Dagger.Flowable.to_workflow(
        Dagger.rule(fn :potato_seed -> :potato end, name: "1_arity_rule")
      )
      |> IO.inspect(label: "runnable workflow")

      Dagger.Flowable.to_workflow(
        Dagger.rule(fn _anything -> :potato end, name: "1_arity_anything_rule")
      )
      |> IO.inspect(label: "runnable workflow")

      assert match?(%Rule{}, Dagger.rule(fn -> :potato end, name: "0_arity_rule"))
      assert match?(%Rule{}, Dagger.rule(fn :potato -> :potato end, name: "1_arity_rule"))

      assert match?(
               %Rule{},
               Dagger.rule(&Examples.potato_baker/1,
                 name: "1_arity_rule_from_captured_function_with_overloads"
               )
             )

      assert match?(
               %Rule{},
               Dagger.rule(&RulesTest.Examples.potato_baker/1,
                 name: "1_arity_rule_from_captured_function_with_overloads"
               ) |> IO.inspect()
             )

      assert match?(
               %Rule{},
               Dagger.rule(&Examples.potato_transformer/1, name: "1_arity_rule_without")
             )

      assert match?(
               %Rule{},
               Dagger.rule(&Examples.potato_block_transformer/1,
                 name: "1_arity_rule_from_block_func_definition"
               ) |> IO.inspect()
             )
    end

    test "a rule's reaction can return an arbitrary term" do
      term_rule = Dagger.rule(reaction: "potato", name: "term_rule") |> IO.inspect(label: "term_rule")

      Dagger.Flowable.to_workflow(term_rule) |> IO.inspect(label: "term rule workflow")

      term_rule_with_condition =
        Dagger.rule(
          condition: &Examples.is_potato?/1,
          reaction: "potato",
          name: "term_rule_with_captured_function_condition"
        )

      assert match?(%Rule{}, term_rule)
      assert Rule.check(term_rule, "anything") == true
      assert Rule.check(term_rule, nil) == true
      assert Rule.run(term_rule, "anything") == "potato"
      assert Rule.run(term_rule, nil) == "potato"
    end

    test "a rule's condition can be composed of many conditions in a list" do
      rule_from_list_of_conditions =
        Dagger.rule(
          condition: [
            fn term -> term == "potato" end,
            &is_binary/1,
            fn term -> String.length(term) == 6 end,
            fn term when not is_integer(term) -> true end,
            &Examples.is_potato?/1
          ],
          reaction: "potato",
          name: "rule from list of conditions"
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
      rule_from_guard_logic =
        Dagger.rule(
          fn
            term
            when term in [:potato, "potato"] and
                   term != "tomato" or
                   (binary_part(term, 0, 4) == "pota" or
                      (is_atom(term) and term == :potato)) ->
              "potato!!"
          end,
          name: "rule from guard"
        )

      assert match?(%Rule{}, rule_from_guard_logic)
      assert Rule.check(rule_from_guard_logic, 42) == false
      assert Rule.check(rule_from_guard_logic, "potato") == true
      assert Rule.check(rule_from_guard_logic, :potato) == true
      assert Rule.run(rule_from_guard_logic, "potato") == "potato!!"
    end

    test "a rule's condition can be composed of many conditions in the guard clause" do
    end
  end
end
