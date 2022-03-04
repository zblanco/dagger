defmodule AccumulatorTest do
  require Dagger

  alias Dagger.Workflow.Accumulator

  defmodule Counting do
    def initiator(:start_count), do: true
    def initiation(_), do: 0

    def do_increment?(:count, _count), do: true
    def incrementer(count) when is_integer(count), do: count + 1
  end

  defmodule Lock do
    def init, do: :locked

    def locked?(:locked), do: true
    def locked?(_), do: false

    def lock(_), do: :locked
    def unlock(_), do: :unlocked

    def toggle_lock(:unlocked), do: :locked
    def toggle_lock(:locked), do: :unlocked
    def toggle_lock(state), do: state

    def attempt(:lock, :unlocked), do: :locked
    def attempt(:unlock, :locked), do: :unlocked
    def attempt(_otherwise, state), do: state

    # requires code_1 then code_2 entered in succession to unlock
    # def build(code_1, code_2) when is_integer(code_1) and is_integer(code_2) do

    # end
  end

  # test "an accumulator can be made through Dagger's declarative constructor api" do
  #   lock_using_reduce_form =
  #     Dagger.accumulator(
  #       :locked,
  #       fn
  #         :unlock, :locked -> :unlocked
  #         :lock, :unlocked -> :locked
  #         _otherwise, state -> state
  #       end
  #     )

  #   lock_using_keywords =
  #     Dagger.accumulator(
  #       init: :locked,
  #       reducer: fn
  #         :unlock, :locked -> :unlocked
  #         :lock, :unlocked -> :locked
  #         _otherwise, state -> state
  #       end
  #     )

  #   lock_using_reducer_functions =
  #     Dagger.accumulator(
  #       &Lock.init/0,
  #       &Lock.toggle_lock/1
  #     )
  # end

  # test "an accumulator can be made directly through Accumulator.new/2" do
  #   Accumulator.new(
  #     init,
  #     [
  #       Ragger.rule(condition: fn , reaction: ),
  #     ]
  #   )
  # end
end
