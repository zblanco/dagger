defmodule Dagger.Workflow.Rule do
  @moduledoc """
  A Dagger Rule is a user-facing component to a workflow that is evaluated as a set of conditions that if true prepare a reaction.

  A rule is a the pair of a condition (otherwise known as the left hand side: LHS) and a reaction (right hand side: RHS)

  Like how a function in Elixir/Erlang has a head with a pattern for parameters and a body (the reaction) a rule is similar except
    these components are separate and modeled as data we can compose at runtime rather than compile time.

  A function is in many ways a rule where the head is the pattern that, when the match evaluates to true,
    results in evaluation of the function body.

  So a rule composed into a workflow is a way to compose patterns/conditionals that can be evaluated like
    a bunch of overloaded functions being matched against.

  Instead of a function we might make Condition a Runnable by following a protocol so abstractions of conditional logic
    can be extended upon more naturally. Ultimately Conditions and Reactions become steps, the protocol would just
    convert a more complex condition into many dependent steps in the case that reactions to specific clauses are added.

  Rules are useful constructs to have persisted and indexed for runtime addition to an existing workflow.

  ## Examples
  """
  # use Norm
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Condition,
    Steps,
    Step
  }

  defstruct name: nil,
            description: nil,
            condition: nil,
            reaction: nil

  @type t() :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          condition: Condition.t(),
          reaction: any()
        }

  @doc """
  Constructs a new Rule.
  ## Example

  ```elixir
  Rule.new(
    name: "my_rule",
    description: "A test rule",
    condition: fn _ -> true end,
    reaction: fn _ -> IO.puts "I'm triggered!" end
  )
  ```
  """
  def new(params) do
    struct(__MODULE__, params)
    |> prepare_lhs()
    |> prepare_rhs()
  end

  defp prepare_lhs(%__MODULE__{condition: condition} = rule) when is_list(condition) do
    # conditions = Enum.map()
    %__MODULE__{rule | condition: Condition.new(condition)}

  end

  defp prepare_lhs(%__MODULE__{condition: condition} = rule) when is_function(condition, 1) do
    %__MODULE__{rule | condition: Condition.new(condition)}
  end

  defp prepare_lhs(%__MODULE__{condition: {m, f} = mfa_condition} = rule)
       when is_atom(m) and is_atom(f) do
    %__MODULE__{rule | condition: Condition.new(mfa_condition)}
  end

  defp prepare_lhs(%__MODULE__{condition: condition} = rule)
       when is_nil(condition) or condition == true do
    %__MODULE__{rule | condition: Condition.new(&Steps.always_true/1)}
  end

  defp prepare_rhs(%__MODULE__{reaction: reaction} = rule) when is_function(reaction, 1) do
    %__MODULE__{rule | reaction: Step.new(reaction)}
  end

  defp prepare_rhs(%__MODULE__{reaction: %Step{} = step} = rule) do
    %__MODULE__{rule | reaction: step}
  end

  defp prepare_rhs(%__MODULE__{reaction: {m, f} = mfa_step} = rule)
       when is_atom(m) and is_atom(f) do
    %__MODULE__{rule | reaction: Step.new(mfa_step)}
  end

  defp prepare_rhs(%__MODULE__{reaction: %Workflow{is_pipeline?: true} = wrk} = rule) do
    %__MODULE__{rule | reaction: wrk}
  end

  defp prepare_rhs(%__MODULE__{reaction: whatever} = rule) do
    %__MODULE__{rule | reaction: Step.new(Steps.returns_whatever(whatever))}
  end
end
