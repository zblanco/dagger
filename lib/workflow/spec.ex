defmodule Dagger.Workflow.Spec do
  @moduledoc """
  Sudo-code typespec of the Dagger workflow specification to tie down a more formalized picture of what we're thinking.
  """

  @typedoc """

  """
  # @type step() :: {work: fn _any -> %Fact{}}

  # @type flow_graph() :: DirectedAcyclicGraph.t(
  #   root -> step() -> step() #...
  # )

  # @type flow_edge() :: {hash(parent_step), hash(dependent_step)}

  # @type rule() :: {condition(), reaction()}

  # @type condition() :: %Step{work: fn any -> boolean end}

  # @type reaction() :: %Step{work: fn _parent_condition_fact_true -> any end}

  # @type accumulator_state() :: term()

  # @type accumulator() :: %Accumulator{
  #   initiator: %Rule{
  #     condition: condition(),
  #     reaction: fn _ -> %Fact{type: :state_changed},
  #   },
  #   state_reactors: [
  #     %Rule{
  #       condition: fn %Fact{type: :state_changed, value: _current_state} and fact() -> boolean() end,
  #       reaction: fn _parent_condition_true -> %Fact{type: :state_changed} end,
  #     }
  #     # ...
  #   ]
  # }

  # @type aggregate() || process_manager() :: {accumulator(), [%Rule{
  #   condition: %Fact{type: :state_changed},
  #   reaction: fn _condition_true -> fact()
  # }]}

  # @type fact() :: hash( {step(), input_value, result_value} )


end
