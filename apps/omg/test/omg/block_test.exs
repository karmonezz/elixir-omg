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

defmodule OMG.BlockTest do
  @moduledoc """
  Simple unit test of part of `OMG.Block`.
  """

  use ExUnitFixtures
  use ExUnit.Case, async: true

  alias OMG.Block
  alias OMG.TestHelper

  defp eth, do: OMG.Eth.RootChain.eth_pseudo_address()

  describe "hashed_txs_at/2" do
    @tag fixtures: [:stable_alice, :stable_bob]
    test "returns a block with the list of transactions and a computed merkle root hash", %{
      stable_alice: alice,
      stable_bob: bob
    } do
      tx_1 = TestHelper.create_recovered([{1, 0, 0, alice}], eth(), [{bob, 100}])
      tx_2 = TestHelper.create_recovered([{1, 1, 1, alice}], eth(), [{bob, 100}])

      transactions = [tx_1, tx_2]

      assert Block.hashed_txs_at(transactions, 10) == %Block{
               hash:
                 <<220, 18, 7, 33, 200, 22, 204, 255, 175, 174, 40, 137, 181, 32, 224, 31, 93, 145, 116, 100, 33, 151,
                   124, 91, 42, 68, 242, 144, 183, 44, 211, 111>>,
               number: 10,
               transactions: [
                 tx_1.signed_tx_bytes,
                 tx_2.signed_tx_bytes
               ]
             }
    end

    test "handles an empty list of transactions" do
      assert Block.hashed_txs_at([], 10) == %Block{
               hash:
                 <<119, 106, 49, 219, 52, 161, 160, 167, 202, 175, 134, 44, 255, 223, 255, 23, 137, 41, 127, 250, 220,
                   56, 11, 211, 211, 146, 129, 211, 64, 171, 211, 173>>,
               number: 10,
               transactions: []
             }
    end
  end

  describe "to_api_format/1" do
    test "formats to map for API" do
      block = %Block{
        hash: "hash",
        number: 10,
        transactions: ["tx_1_bytes", "tx_2_bytes"]
      }

      assert Block.to_api_format(block) == %{
               blknum: 10,
               hash: "hash",
               transactions: ["tx_1_bytes", "tx_2_bytes"]
             }
    end
  end

  describe "to_db_value/1" do
    test "formats to DB format with valid inputs" do
      block = %Block{
        hash: "hash",
        number: 10,
        transactions: ["tx_1_bytes", "tx_2_bytes"]
      }

      assert Block.to_db_value(block) == %{
               hash: "hash",
               number: 10,
               transactions: ["tx_1_bytes", "tx_2_bytes"]
             }
    end

    test "fails to format when the list of transactions is not a list" do
      # Not sure how we want to handle this, there is currently no
      # fallback function in the Block module
      assert_raise FunctionClauseError, fn ->
        Block.to_db_value(%Block{
          hash: "hash",
          number: 10,
          transactions: %{}
        })
      end
    end

    test "fails to format when the hash is not a binary" do
      assert_raise FunctionClauseError, fn ->
        Block.to_db_value(%Block{
          hash: 1,
          number: 10,
          transactions: []
        })
      end
    end

    test "fails to format when the number is not an integer" do
      assert_raise FunctionClauseError, fn ->
        Block.to_db_value(%Block{
          hash: 1,
          number: "10",
          transactions: []
        })
      end
    end
  end

  describe "from_db_value/1" do
    test "formats from DB format with valid inputs" do
      block = %{
        hash: "hash",
        number: 10,
        transactions: ["tx_1_bytes", "tx_2_bytes"]
      }

      assert Block.from_db_value(block) == %Block{
               hash: "hash",
               number: 10,
               transactions: ["tx_1_bytes", "tx_2_bytes"]
             }
    end

    test "fails to format when the list of transactions is not a list" do
      # Not sure how we want to handle this, there is currently no
      # fallback function in the Block module
      assert_raise FunctionClauseError, fn ->
        Block.from_db_value(%{
          hash: "hash",
          number: 10,
          transactions: %{}
        })
      end
    end

    test "fails to format when the hash is not a binary" do
      assert_raise FunctionClauseError, fn ->
        Block.from_db_value(%{
          hash: 1,
          number: 10,
          transactions: []
        })
      end
    end

    test "fails to format when the number is not an integer" do
      assert_raise FunctionClauseError, fn ->
        Block.from_db_value(%{
          hash: 1,
          number: "10",
          transactions: []
        })
      end
    end
  end

  describe "inclusion_proof/2" do
    # The tests below checks merkle proof normally tested via speaking to the contract
    # (integration tests) against a fixed binary. The motivation for having such
    # test is a quick test of whether the merkle proving didn't change.
    @tag fixtures: [:stable_alice]
    test "calculates the inclusion proof when a list of transactions is given", %{
      stable_alice: alice
    } do
      # odd number of transactions, just in case
      tx_1 = TestHelper.create_encoded([{1, 0, 0, alice}], eth(), [{alice, 7}])
      tx_2 = TestHelper.create_encoded([{1, 1, 0, alice}], eth(), [{alice, 2}])
      tx_3 = TestHelper.create_encoded([{1, 0, 1, alice}], eth(), [{alice, 2}])

      proof = Block.inclusion_proof([tx_1, tx_2, tx_3], 1)

      assert <<141, 196, 109, 106, 192, 192, 252, 104, 128, 186, 67, 0, 100, 193>> <> _ = proof
      assert is_binary(proof)
      assert byte_size(proof) == 32 * 16
    end

    @tag fixtures: [:stable_alice]
    test "calculates the inclusion proof when a block is given", %{
      stable_alice: alice
    } do
      tx_1 = TestHelper.create_encoded([{1, 0, 0, alice}], eth(), [{alice, 7}])
      tx_2 = TestHelper.create_encoded([{1, 1, 0, alice}], eth(), [{alice, 2}])
      proof = Block.inclusion_proof(%Block{transactions: [tx_1, tx_2]}, 1)

      assert is_binary(proof)
      assert byte_size(proof) == 32 * 16
    end

    @tag fixtures: [:stable_alice]
    test "calculating a proof via a block or a list of transactions return the same result", %{
      stable_alice: alice
    } do
      tx_1 = TestHelper.create_encoded([{1, 0, 0, alice}], eth(), [{alice, 7}])
      tx_2 = TestHelper.create_encoded([{1, 1, 0, alice}], eth(), [{alice, 2}])

      block_proof = Block.inclusion_proof(%Block{transactions: [tx_1, tx_2]}, 1)
      transactions_proof = Block.inclusion_proof([tx_1, tx_2], 1)

      assert block_proof == transactions_proof
    end

    test "calculates the inclusion proof when an empty list is given" do
      proof = Block.inclusion_proof([], 1)

      assert is_binary(proof)
      assert byte_size(proof) == 32 * 16
    end

    test "raises an error when an invalid input is given (map)" do
      assert_raise FunctionClauseError, fn ->
        Block.inclusion_proof(%{}, 1)
      end
    end

    @tag fixtures: [:alice]
    test "calculates a block merkle proof for deposit transactions",
         %{alice: alice} do
      tx = TestHelper.create_encoded([], eth(), [{alice, 7}])
      proof = Block.inclusion_proof(%Block{transactions: [tx]}, 0)

      assert is_binary(proof)
      assert byte_size(proof) == 32 * 16
    end
  end
end
