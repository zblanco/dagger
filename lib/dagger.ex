defmodule Dagger do
  @moduledoc """
  Dagger is a tool for modeling your code as a Dataflow graph of Steps.

  Data flow dependencies are modeled as Steps (nodes) in Workflows hosting the graph structure.

  Steps represent a single input -> output lambda function.

  As Facts are fed through a workflow, varous steps are activated producing more Facts.

  Further abstractions on sets of dependent Steps like Rules and Accumulators can also be added to a
  Workflow.

  Together this enables Dagger to express complex decision trees, finite state machines, data pipelines, and more.

  See the [Workflow]() module for more information.

  This core library is responsible for modeling Workflows with Steps, enforcing contracts of Step functions,
    and defining the contract of Runners used to execute Workflows.

  If you just need concurrent processing of large amounts of data consider using GenStage, Broadway and/or the Flow libraries.

  Dagger is used for runtime modification of a workflow where you might want to compose pieces of a workflow together.

  ## Installation and Setup


  """
end
