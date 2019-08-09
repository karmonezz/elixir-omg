# Copyright 2019 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.State.ExchangeTest do
  use ExUnitFixtures
  use ExUnit.Case, async: true

  alias OMG.Block
  alias OMG.Fees
  alias OMG.State.Core
  alias OMG.State.Transaction
  alias OMG.Utxo

  import OMG.TestHelper
  import OMG.ExchangeHelper

  require Utxo

  @eth OMG.Eth.RootChain.eth_pseudo_address()
  @not_eth <<1::size(160)>>
  @interval OMG.Eth.RootChain.get_child_block_interval() |> elem(1)
  @blknum1 @interval
  @blknum2 @interval * 2

  @empty_block_hash <<119, 106, 49, 219, 52, 161, 160, 167, 202, 175, 134, 44, 255, 223, 255, 23, 137, 41, 127, 250,
                      220, 56, 11, 211, 211, 146, 129, 211, 64, 171, 211, 173>>

  setup do
    [alice, bob, exchange] = 1..3 |> Enum.map(fn _ -> generate_entity() end)
    {:ok, child_block_interval} = OMG.Eth.RootChain.get_child_block_interval()
    {:ok, state} = Core.extract_initial_state([], 0, 0, child_block_interval)

    deposited_state =
      state
      |> do_deposit(alice, %{amount: 10, currency: @eth, blknum: 1})
      |> do_deposit(bob, %{amount: 10, currency: @not_eth, blknum: 2})

    %{alice: alice, bob: bob, exchange: exchange, state_empty: state, deposited_state: deposited_state}
  end

  test "can't spend from orders", %{alice: alice, exchange: exchange, deposited_state: state} do
    state
    |> Core.exec(fund_order_recovered([{1, 0, 0, alice}], [{exchange, @eth, 10}], <<1>>), :ignore)
    |> success?
    |> Core.exec(create_recovered([{@blknum1, 0, 0, exchange}], [{exchange, @eth, 10}]), :ignore)
    |> fail?(:unauthorized_spent)
  end

  test "can settle orders", %{alice: alice, bob: bob, exchange: exchange, deposited_state: state} do
    state
    |> Core.exec(fund_order_recovered([{1, 0, 0, alice}], [{exchange, @eth, 10}], "alice_0"), :ignore)
    |> success?
    |> Core.exec(fund_order_recovered([{2, 0, 0, bob}], [{exchange, @not_eth, 10}], "bob_0"), :ignore)
    |> success?
    |> Core.exec(
      settlement_recovered(
        [{@blknum1, 0, 0, exchange, alice, "alice_0"}, {@blknum1, 1, 0, exchange, bob, "bob_0"}],
        [{alice, @not_eth, 10}, {bob, @eth, 10}]
      ),
      :ignore
    )
    |> success?
  end

  test "non-exchange can't settle orders", %{alice: alice, bob: bob, exchange: exchange, deposited_state: state} do
    state
    |> Core.exec(fund_order_recovered([{1, 0, 0, alice}], [{exchange, @eth, 10}], "alice_0"), :ignore)
    |> success?
    |> Core.exec(fund_order_recovered([{2, 0, 0, bob}], [{exchange, @not_eth, 10}], "bob_0"), :ignore)
    |> success?
    |> Core.exec(
      settlement_recovered(
        [{@blknum1, 0, 0, alice, alice, "alice_0"}, {@blknum1, 1, 0, alice, bob, "bob_0"}],
        [{alice, @not_eth, 10}, {bob, @eth, 10}]
      ),
      :ignore
    )
    |> fail?(:unauthorized_spent)
  end

  test "orders can't produce money", %{alice: alice, bob: bob, exchange: exchange, deposited_state: state} do
    state
    |> Core.exec(fund_order_recovered([{1, 0, 0, alice}], [{exchange, @eth, 10}], "alice_0"), :ignore)
    |> success?
    |> Core.exec(fund_order_recovered([{2, 0, 0, bob}], [{exchange, @not_eth, 10}], "bob_0"), :ignore)
    |> success?
    |> Core.exec(
      settlement_recovered(
        [{@blknum1, 0, 0, exchange, alice, "alice_0"}, {@blknum1, 1, 0, exchange, bob, "bob_0"}],
        [{alice, @not_eth, 11}, {bob, @eth, 10}]
      ),
      :ignore
    )
    |> fail?(:amounts_do_not_add_up)
  end

  test "can't spend from settlements without confirmsig",
       %{alice: alice, bob: bob, exchange: exchange, deposited_state: state} do
    state
    |> Core.exec(fund_order_recovered([{1, 0, 0, alice}], [{exchange, @eth, 10}], "alice_0"), :ignore)
    |> success?
    |> Core.exec(fund_order_recovered([{2, 0, 0, bob}], [{exchange, @not_eth, 10}], "bob_0"), :ignore)
    |> success?
    |> Core.exec(
      settlement_recovered(
        [{@blknum1, 0, 0, exchange, alice, "alice_0"}, {@blknum1, 1, 0, exchange, bob, "bob_0"}],
        [{alice, @not_eth, 10}, {bob, @eth, 10}]
      ),
      :ignore
    )
    |> success?
    |> Core.exec(create_recovered([{@blknum1, 2, 0, alice}], [{alice, @not_eth, 10}]), :ignore)
    |> fail?(:unauthorized_spent)
  end

  # FIXME: copy pasted from State.CoreTest - DRY?
  defp success?(result) do
    assert {:ok, _, state} = result
    state
  end

  defp fail?(result, expected_error) do
    assert {{:error, ^expected_error}, state} = result
    state
  end

  defp same?({{:error, _someerror}, state}, expected_state) do
    assert expected_state == state
    state
  end

  defp same?(state, expected_state) do
    assert expected_state == state
    state
  end

  defp empty_block(number \\ @blknum1) do
    %Block{transactions: [], hash: @empty_block_hash, number: number}
  end

  # used to check the invariants in form_block
  # use this throughout this test module instead of Core.form_block
  defp form_block_check(state) do
    {_, {block, _, db_updates}, _} = result = Core.form_block(@interval, state)

    # check if block returned and sent to db_updates is the same
    assert Enum.member?(db_updates, {:put, :block, Block.to_db_value(block)})
    # check if that's the only db_update for block
    is_block_put? = fn {operation, type, _} -> operation == :put && type == :block end
    assert Enum.count(db_updates, is_block_put?) == 1

    result
  end
end
