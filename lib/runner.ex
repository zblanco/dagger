defmodule Dagger.Runner do
  @moduledoc """
  Behaviour definition that a valid Step Runner must implement.

  A runner is usually a combination of a Queue and some concurrency strategy consuming from the Queue.

  A runner should call `Step.run/1` at some point unless it's contrived for tests.
  """
  alias Dagger.Step

  @type runnable_data() :: any()

  @callback run(Step.t | runnable_data()) ::
    :ok
    | :error
    | {:error, any()}

  @callback ack(step :: Step.t) :: :ok | :error

  @callback cancel(step_id_or_step_ids :: list(String.t) | String.t) ::
    :ok
    | :error
    | {:error, any()}
end
