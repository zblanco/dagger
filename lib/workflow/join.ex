defmodule Dagger.Workflow.Join do
  @moduledoc """
  A join node between dependent conditions.

  When conditions of left and right have been satisfied, the join node produces a
    fact indicating so. Joins may be dependent on other joins or base conditions.
    Contained in the second element of the tuple is a hash of the condition for which
    satisfies that side of the join. So the state transitions of this node are to produce
    facts indicating satisfaction of a given side, left or right.

  As the workflow containing joins progresses we need some mechanism for storing the state
    in context of left or right satisfied facts. So some interaction has to take place
    to toggle from :not_satisfied to :satisfied.

  For that we either make the activation protocol of `run` return the new satisfied fact or.

  Construction:


  Evaluation:

  1. A valid join is added to the workflow.
  2. A fact matching a condition's activation is logged.
  3. Joins with that condition's hash are found by checking a hash map.
  4. The join's state is now set to a partially satisfied state.
  5. When both conditions for the join are satisfied, a fact asserting the combination of the two condition's satisfaction being met is logged.
  6. Other join nodes dependent on other join node satisfactions may evaluate again using the same flow.
  """
  alias Dagger.Workflow

  alias Dagger.Workflow.{
    Fact,
    Join,
    Steps,
    Runnable,
    Activation
  }

  defstruct left: nil,
            right: nil,
            hash: nil

  def new(left, right) do
    %__MODULE__{
      left: {:not_satisfied, left},
      right: {:not_satisfied, right},
      hash: Steps.join_hash(left, right)
    }
  end

  # def apply(%__MODULE__{left: {:not_satisfied, left}} = join, %Fact{value: :left_satisfied, ancestry}) do
  #   %__MODULE__{join | left: {:satisfied, left}}
  # end

  # def apply(%__MODULE__{right: {:not_satisfied, right}} = join, %Fact{value: :right_satisfied, ancestry}) do
  #   %__MODULE__{join | right: {:satisfied, right}}
  # end

  def fully_satisfied?(%__MODULE__{left: {:satisfied, _left}, right: {:satisfied, _right}}),
    do: true

  def fully_satisfied?(%__MODULE__{}), do: false

  # defimpl Runnable do
  #   def run(
  #     %Join{left: {:satisfied, _left}, right: {:not_satisfied, right}} = join,
  #     %Fact{ancestry: {condition_hash, _}} = fact) when right == condition_hash do
  #       satisfied_fact(join, fact, :right)
  #   end

  #   def run(
  #     %Join{left: {:satisfied, _left}, right: {:not_satisfied, _right}} = join, fact) do
  #       unsatisfied_fact(join, fact, :right)
  #   end

  #   def run(
  #     %Join{left: {:not_satisfied, left}, right: {:not_satisfied, _right}} = join,
  #     %Fact{ancestry: {condition_hash, _}} = fact) do
  #     case left === condition_hash do
  #       true -> satisfied_fact(join, fact, :left)
  #       _otherwise -> :not_satisfied
  #     end
  #   end

  #   defp satisfied_fact(%Join{left: {_, condition_hash}}, %Fact{} = fact, :left) do
  #     Fact.new(value: :left_satisfied, ancestry: {condition_hash, Steps.fact_hash(fact.value)})
  #   end

  #   defp satisfied_fact(%Join{right: {_, condition_hash}}, %Fact{} = fact, :right) do
  #     Fact.new(value: :right_satisfied, ancestry: {condition_hash, Steps.fact_hash(fact.value)})
  #   end

  #   defp unsatisfied_fact(%Join{hash: hash}, %Fact{} = fact, :right) do
  #     Fact.new(value: :unsatisfied, ancestry: {hash, Steps.fact_hash(fact.value)})
  #   end
  # end

  # defimpl Activation do
  #   # activation of a join is a state transformation of the join and the worklow
  #   # when
  #   def activate(
  #     %Workflow{} = workflow,
  #     %Join{left: {:not_satisfied, left}, right: {:not_satisfied, right}} = join,
  #     %Fact{ancestry: {condition_hash, _}} = fact) do
  #     with {true, false} <- {left === condition_hash, right === condition_hash},
  #       satisfied_fact <- satisfied_fact(join, fact, :left)
  #     do
  #       workflow
  #       |> Workflow.log_fact(fact)
  #       |> activate_join(fact)
  #     end
  #   end

  #   defp activate_join(%Workflow{activations: activations} = workflow, fact) do
  #     %Workflow{workflow |
  #       activations: activations
  #     }
  #   end
  # end
end
