defmodule Dagger.Workflow.Condition do
  @moduledoc """
  A datastructure enforcing construction and standardization of conditions and their composition within a workflow.

  A condition is the left hand side of a rule.

  Successful construction of a rule's left hand side results in a condition.

  A rules addition to a Workflow may result in a condition being kept as a Condition
    that behaves as a step which returns a boolean or a network of join nodes for stateful
    evaluation of the condition over time.

  If the overall condition evaluates to `true` the right hand side of the rule is to be executed.

  The purpose of a condition is to assist in building a workflow agenda of runnables
    by conditionally appending a runnable of the fact that passed conditions with the
    step to run.

  ### Different kinds of conditions

  * A step that returns true or false
    * The simplest kind of condition which can operate statelessly
    * No additional state or context needs to be maintained in the workflow, a runnable
      can be appended to the agenda with simply the passing fact and any leaf node steps
      dependent on the condition.
  * A set of steps which must all return true
    * AND logical bindings requiring state of activated conditions in a network of Join nodes
  """
  alias Dagger.Workflow.{
    Steps,
    Step
  }

  defstruct work: nil,
            hash: nil,
            arity: nil

  @type t() :: %__MODULE__{
          work: runnable(),
          hash: integer(),
          arity: arity()
        }

  @doc """
  Anything that conforms to the Runnable protocol.
  """
  @type runnable() :: function() | mfa() | %Step{} | any()

  def new(work) when is_function(work) do
    %__MODULE__{
      work: work,
      hash: Steps.work_hash(work),
      arity: Function.info(work, :arity) |> elem(1)
    }
  end

  def new(work, arity) when is_function(work) do
    %__MODULE__{
      work: work,
      hash: Steps.work_hash(work),
      arity: arity
    }
  end
end
