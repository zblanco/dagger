defmodule Dagger.Workflow.Rule do
  @moduledoc """
  A Dagger Rule is a user-facing component to a workflow that is evaluated as a series of conditions that if true emit the reaction.

  A rule is a the pair of a condition and a reaction. Two steps where the condition must return true or false and the reaction returns any fact.

  Instead of a function we might make Condition a Runnable by following a protocol so abstractions of conditional logic
    can be extended upon more naturally. Ultimately Conditions and Reactions become steps, the protocol would just
    convert a more complex condition into smaller pieces in the case that reactions to specific clauses are added.
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

  def new(params) do
    struct!(__MODULE__, params)
  end

  def set_condition(%__MODULE__{} = rule, condition) when is_function(condition) do
    # validate boolean pattern constraints
    %__MODULE__{rule | condition: condition}
  end

  def set_reaction(%__MODULE__{} = rule, reaction) do
    # enforce runnable constraints
    %__MODULE__{rule | reaction: reaction}
  end
end
