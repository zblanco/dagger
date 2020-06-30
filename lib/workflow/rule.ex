defmodule Dagger.Workflow.Rule do
  @moduledoc """
  A Dagger Rule is a user-facing component to a workflow that is evaluated as a series of conditions that if true emit the reaction.

  A rule is a the pair of a condition and a reaction. Two steps where the condition must return true or false and the reaction returns any fact.

  Instead of a function we might make Condition a Runnable by following a protocol so abstractions of conditional logic
    can be extended upon more naturally. Ultimately Conditions and Reactions become steps, the protocol would just
    convert a more complex condition into smaller pieces in the case that reactions to specific clauses are added.

  Rules are useful constructs to have persisted and indexed for runtime addition to an existing workflow.
  """
  use Norm
  defstruct name: nil,
            description: nil,
            condition: nil,
            reaction: nil

  @type t() :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    condition: function(),
    reaction: function(),
  }

  @doc """
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
    struct!(__MODULE__, params)
  end

  # spec(fn any() -> boolean() end)

  def set_condition(%__MODULE__{} = rule, condition) when is_function(condition) do
    # validate boolean pattern constraints
    # a condition is a function that always returns a boolean no matta what
    # feed a variety of data into the condition (stream data gen?)
    %__MODULE__{rule | condition: condition}
  end

  def set_reaction(%__MODULE__{} = rule, reaction) do
    # enforce runnable constraints
    %__MODULE__{rule | reaction: reaction}
  end
end
