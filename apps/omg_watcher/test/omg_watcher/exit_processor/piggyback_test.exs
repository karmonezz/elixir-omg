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

defmodule OMG.Watcher.ExitProcessor.PiggybackTest do
  @moduledoc """
  Test of the logic of exit processor - detecting conditions related to piggybacks
  """
  use OMG.Watcher.ExitProcessor.Case, async: true

  alias OMG.Block
  alias OMG.State.Transaction
  alias OMG.TestHelper
  alias OMG.Utxo
  alias OMG.Watcher.Event
  alias OMG.Watcher.ExitProcessor
  alias OMG.Watcher.ExitProcessor.Core

  require Utxo

  import OMG.Watcher.ExitProcessor.TestHelper

  @exit_id 1

  describe "sanity checks" do
    test "throwing when unknown piggyback events arrive", %{processor_filled: state, ife_tx_hashes: [ife_id | _]} do
      catch_error(Core.new_piggybacks(state, [%{tx_hash: 0, output_index: 0}]))
      catch_error(Core.new_piggybacks(state, [%{tx_hash: ife_id, output_index: 8}]))
      # cannot piggyback twice the same output
      {updated_state, [_]} = Core.new_piggybacks(state, [%{tx_hash: ife_id, output_index: 0}])
      catch_error(Core.new_piggybacks(updated_state, [%{tx_hash: ife_id, output_index: 0}]))
    end

    test "can process empty piggybacks and challenges", %{processor_empty: empty, processor_filled: filled} do
      {^empty, []} = Core.new_piggybacks(empty, [])
      {^filled, []} = Core.new_piggybacks(filled, [])
      {^empty, []} = Core.challenge_piggybacks(empty, [])
      {^filled, []} = Core.challenge_piggybacks(filled, [])
    end
  end

  test "forgets challenged piggybacks",
       %{processor_filled: processor, ife_tx_hashes: [tx_hash1, tx_hash2]} do
    {processor, _} =
      Core.new_piggybacks(processor, [%{tx_hash: tx_hash1, output_index: 0}, %{tx_hash: tx_hash2, output_index: 0}])

    # sanity: there are some piggybacks after piggybacking, to be removed later
    assert [%{piggybacked_inputs: [_]}, %{piggybacked_inputs: [_]}] = Core.get_active_in_flight_exits(processor)
    {processor, _} = Core.challenge_piggybacks(processor, [%{tx_hash: tx_hash1, output_index: 0}])

    assert [%{txhash: ^tx_hash1, piggybacked_inputs: []}, %{piggybacked_inputs: [0]}] =
             Core.get_active_in_flight_exits(processor)
             |> Enum.sort_by(&length(&1.piggybacked_inputs))
  end

  test "can open and challenge two piggybacks at one call",
       %{processor_filled: processor, ife_tx_hashes: [tx_hash1, tx_hash2]} do
    events = [%{tx_hash: tx_hash1, output_index: 0}, %{tx_hash: tx_hash2, output_index: 0}]

    {processor, _} = Core.new_piggybacks(processor, events)
    # sanity: there are some piggybacks after piggybacking, to be removed later
    assert [%{piggybacked_inputs: [_]}, %{piggybacked_inputs: [_]}] = Core.get_active_in_flight_exits(processor)
    {processor, _} = Core.challenge_piggybacks(processor, events)

    assert [%{piggybacked_inputs: []}, %{piggybacked_inputs: []}] = Core.get_active_in_flight_exits(processor)
  end

  describe "available piggybacks" do
    test "detects multiple available piggybacks, with all the fields",
         %{processor_filled: processor, transactions: [tx1, tx2], alice: alice, carol: carol} do
      txbytes_1 = Transaction.raw_txbytes(tx1)
      txbytes_2 = Transaction.raw_txbytes(tx2)

      assert {:ok, events} =
               %ExitProcessor.Request{blknum_now: 5000, eth_height_now: 5}
               |> Core.check_validity(processor)

      assert_events(events, [
        %Event.PiggybackAvailable{
          available_inputs: [%{address: alice.addr, index: 0}, %{address: carol.addr, index: 1}],
          available_outputs: [%{address: alice.addr, index: 0}, %{address: carol.addr, index: 1}],
          txbytes: txbytes_1
        },
        %Event.PiggybackAvailable{
          available_inputs: [%{address: alice.addr, index: 0}, %{address: carol.addr, index: 1}],
          available_outputs: [%{address: alice.addr, index: 0}, %{address: carol.addr, index: 1}],
          txbytes: txbytes_2
        }
      ])
    end

    test "detects available piggyback because tx not seen in valid block, regardless of competitors",
         %{processor_empty: processor, alice: alice} do
      # testing this because everywhere else, the test fixtures always imply competitors
      tx = TestHelper.create_recovered([{1, 0, 0, alice}], [])
      txbytes = txbytes(tx)
      processor = processor |> start_ife_from(tx)

      assert {:ok, [%Event.PiggybackAvailable{txbytes: ^txbytes}]} =
               %ExitProcessor.Request{blknum_now: 5000, eth_height_now: 5}
               |> Core.check_validity(processor)
    end

    test "detects available piggyback correctly, even if signed multiple times",
         %{processor_empty: processor, alice: alice} do
      # there is leeway in the contract, that allows IFE transactions to hold non-zero signatures for zero-inputs
      # we want to be sure that this doesn't crash the `ExitProcessor`
      tx = Transaction.Payment.new([{1, 0, 0}], [])
      txbytes = txbytes(tx)
      # superfluous signatures
      %{sigs: sigs} = signed_tx = OMG.DevCrypto.sign(tx, [alice.priv, alice.priv, alice.priv])
      processor = processor |> start_ife_from(signed_tx, sigs: sigs)

      assert {:ok, [%Event.PiggybackAvailable{txbytes: ^txbytes}]} =
               %ExitProcessor.Request{blknum_now: 5000, eth_height_now: 5}
               |> Core.check_validity(processor)
    end

    test "doesn't detect available piggybacks because txs seen in valid block",
         %{processor_filled: processor, transactions: [tx1, tx2]} do
      txbytes2 = txbytes(tx2)

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx1], 3000)]
      }

      processor = processor |> Core.find_ifes_in_blocks(request)
      assert {:ok, [%Event.PiggybackAvailable{txbytes: ^txbytes2}]} = request |> Core.check_validity(processor)
    end

    test "transaction without outputs and different input owners",
         %{alice: alice, bob: bob, processor_empty: processor} do
      tx = TestHelper.create_recovered([{1, 0, 0, alice}, {1, 2, 1, bob}], [])
      alice_addr = alice.addr
      bob_addr = bob.addr
      txbytes = txbytes(tx)
      processor = processor |> start_ife_from(tx)

      assert {:ok,
              [
                %Event.PiggybackAvailable{
                  available_inputs: [%{address: ^alice_addr, index: 0}, %{address: ^bob_addr, index: 1}],
                  available_outputs: [],
                  txbytes: ^txbytes
                }
              ]} =
               %ExitProcessor.Request{blknum_now: 1000, eth_height_now: 5}
               |> check_validity_filtered(processor, only: [Event.PiggybackAvailable])
    end

    test "when output is already piggybacked, it is not reported in piggyback available event",
         %{alice: alice, processor_empty: processor} do
      tx = TestHelper.create_recovered([{1, 0, 0, alice}, {1, 2, 1, alice}], [])
      tx_hash = Transaction.raw_txhash(tx)
      processor = processor |> start_ife_from(tx) |> piggyback_ife_from(tx_hash, 0)

      assert {:ok,
              [
                %Event.PiggybackAvailable{
                  available_inputs: [%{index: 1}],
                  available_outputs: []
                }
              ]} =
               %ExitProcessor.Request{blknum_now: 1000, eth_height_now: 5}
               |> check_validity_filtered(processor, only: [Event.PiggybackAvailable])
    end

    test "when ife is finalized, it's outputs are not reported as available for piggyback",
         %{alice: alice, processor_empty: processor} do
      tx = TestHelper.create_recovered([{1, 0, 0, alice}, {1, 2, 1, alice}], [])
      tx_hash = Transaction.raw_txhash(tx)
      processor = processor |> start_ife_from(tx) |> piggyback_ife_from(tx_hash, 0)
      finalization = %{in_flight_exit_id: @exit_id, output_index: 0}
      {:ok, processor, _} = Core.finalize_in_flight_exits(processor, [finalization], %{})

      assert {:ok, []} =
               %ExitProcessor.Request{blknum_now: 1000, eth_height_now: 5}
               |> check_validity_filtered(processor, only: [Event.PiggybackAvailable])
    end

    test "challenged IFEs emit the same piggybacks as canonical ones",
         %{processor_filled: processor, transactions: [tx | _], competing_tx: comp} do
      assert {:ok, events_canonical} =
               %ExitProcessor.Request{blknum_now: 1000, eth_height_now: 5}
               |> Core.check_validity(processor)

      {challenged_processor, _} = Core.new_ife_challenges(processor, [ife_challenge(tx, comp)])

      assert {:ok, events_challenged} =
               %ExitProcessor.Request{blknum_now: 5000, eth_height_now: 5}
               |> Core.check_validity(challenged_processor)

      assert_events(events_canonical, events_challenged)
    end
  end

  describe "evaluates correctness of new piggybacks" do
    test "no event if input double-spent but not piggybacked",
         %{processor_filled: processor, competing_tx: comp} do
      processor = processor |> start_ife_from(comp)

      assert {:ok, []} =
               %ExitProcessor.Request{blknum_now: 5000, eth_height_now: 5}
               |> check_validity_filtered(processor, only: [Event.InvalidPiggyback])
    end

    test "no event if output spent but not piggybacked",
         %{alice: alice, processor_filled: processor, transactions: [tx | _]} do
      tx_blknum = 3000

      # 2. transaction which spends that piggybacked output
      comp = TestHelper.create_recovered([{tx_blknum, 0, 0, alice}], [])

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)]
      }

      # 3. stuff happens in the contract, but NO PIGGYBACK!
      processor = processor |> start_ife_from(comp) |> Core.find_ifes_in_blocks(request)

      assert {:ok, []} =
               %ExitProcessor.Request{blknum_now: 5000, eth_height_now: 5}
               |> check_validity_filtered(processor, only: [Event.InvalidPiggyback])
    end

    test "detects double-spend of an input, found in IFE",
         %{processor_filled: state, transactions: [tx | _], competing_tx: comp, ife_tx_hashes: [ife_id | _]} do
      txbytes = txbytes(tx)
      {comp_txbytes, other_sig} = {txbytes(comp), sig(comp, 1)}
      state = state |> start_ife_from(comp) |> piggyback_ife_from(ife_id, 0)
      request = %ExitProcessor.Request{blknum_now: 1000, eth_height_now: 5}

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [0], outputs: []}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_input_index: 0,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 1,
                spending_sig: ^other_sig
              }} = Core.get_input_challenge_data(request, state, txbytes, 0)
    end

    test "detects double-spend of an input, found in a block",
         %{processor_filled: state, transactions: [tx | _], competing_tx: comp, ife_tx_hashes: [ife_id | _]} do
      txbytes = txbytes(tx)
      {comp_txbytes, comp_sig} = {txbytes(comp), sig(comp, 1)}

      comp_blknum = 4000

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        blocks_result: [Block.hashed_txs_at([comp], comp_blknum)]
      }

      state = state |> piggyback_ife_from(ife_id, 0) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [0], outputs: []}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_input_index: 0,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 1,
                spending_sig: ^comp_sig
              }} = Core.get_input_challenge_data(request, state, txbytes, 0)
    end

    test "detects double-spend of an output, found in a IFE",
         %{alice: alice, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      # 1. transaction which is, ife'd, output piggybacked, and included in a block
      txbytes = txbytes(tx)
      tx_blknum = 3000

      # 2. transaction which spends that piggybacked output
      comp = TestHelper.create_recovered([{tx_blknum, 0, 0, alice}], [])
      {comp_txbytes, comp_signature} = {txbytes(comp), sig(comp)}

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)]
      }

      # 3. stuff happens in the contract
      state = state |> start_ife_from(comp) |> piggyback_ife_from(ife_id, 4) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [], outputs: [0]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_output_pos: Utxo.position(^tx_blknum, 0, 0),
                in_flight_proof: proof_bytes,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 0,
                spending_sig: ^comp_signature
              }} = Core.get_output_challenge_data(request, state, txbytes, 0)

      assert_proof_sound(proof_bytes)
    end

    test "detects and proves double-spend of an output, found in a block",
         %{alice: alice, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      # this time, the piggybacked-output-spending tx is going to be included in a block, which requires more back&forth
      # 1. transaction which is, ife'd, output piggybacked, and included in a block
      txbytes = txbytes(tx)
      tx_blknum = 3000

      # 2. transaction which spends that piggybacked output
      comp = TestHelper.create_recovered([{tx_blknum, 0, 0, alice}], [])
      {comp_txbytes, comp_signature} = {txbytes(comp), sig(comp)}

      comp_blknum = 4000

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)],
        blocks_result: [Block.hashed_txs_at([comp], comp_blknum)]
      }

      # 3. stuff happens in the contract
      state = state |> piggyback_ife_from(ife_id, 4) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [], outputs: [0]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_output_pos: Utxo.position(^tx_blknum, 0, 0),
                in_flight_proof: proof_bytes,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 0,
                spending_sig: ^comp_signature
              }} = Core.get_output_challenge_data(request, state, txbytes, 0)

      assert_proof_sound(proof_bytes)
    end

    test "detects and proves double-spend of an output, found in a block, various output indices",
         %{carol: carol, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      txbytes = txbytes(tx)
      tx_blknum = 3000

      comp = TestHelper.create_recovered([{tx_blknum, 0, 1, carol}], [])
      {comp_txbytes, comp_signature} = {txbytes(comp), sig(comp)}

      comp_blknum = 4000

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)],
        blocks_result: [Block.hashed_txs_at([comp], comp_blknum)]
      }

      state = state |> piggyback_ife_from(ife_id, 5) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [], outputs: [1]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_output_pos: Utxo.position(^tx_blknum, 0, 1),
                in_flight_proof: proof_bytes,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 0,
                spending_sig: ^comp_signature
              }} = Core.get_output_challenge_data(request, state, txbytes, 1)

      assert_proof_sound(proof_bytes)
    end

    test "detects and proves double-spend of an output, found in a block, various spending input indices",
         %{alice: alice, carol: carol, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      txbytes = txbytes(tx)
      tx_blknum = 3000

      comp = TestHelper.create_recovered([{tx_blknum, 0, 0, alice}, {tx_blknum, 0, 1, carol}], [])
      {comp_txbytes, comp_signature} = {txbytes(comp), sig(comp, 1)}

      comp_blknum = 4000

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)],
        blocks_result: [Block.hashed_txs_at([comp], comp_blknum)]
      }

      state = state |> piggyback_ife_from(ife_id, 5) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [], outputs: [1]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_output_pos: Utxo.position(^tx_blknum, 0, 1),
                in_flight_proof: proof_bytes,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 1,
                spending_sig: ^comp_signature
              }} = Core.get_output_challenge_data(request, state, txbytes, 1)

      assert_proof_sound(proof_bytes)
    end

    test "proves and proves double-spend of an output, found in a block, for various inclusion positions",
         %{alice: alice, bob: bob, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      other_tx = TestHelper.create_recovered([{10_000, 0, 0, bob}], [])
      txbytes = txbytes(tx)
      tx_blknum = 3000

      comp = TestHelper.create_recovered([{tx_blknum, 1, 0, alice}], [])
      {comp_txbytes, comp_signature} = {txbytes(comp), sig(comp)}

      comp_blknum = 4000

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([other_tx, tx], tx_blknum)],
        blocks_result: [Block.hashed_txs_at([comp], comp_blknum)]
      }

      state = state |> piggyback_ife_from(ife_id, 4) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [], outputs: [0]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_output_pos: Utxo.position(^tx_blknum, 1, 0),
                in_flight_proof: proof_bytes,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 0,
                spending_sig: ^comp_signature
              }} = Core.get_output_challenge_data(request, state, txbytes, 0)

      assert_proof_sound(proof_bytes)
    end

    test "detects no double-spend of an input, if a different input is being spent in block",
         %{processor_filled: state, competing_tx: comp, ife_tx_hashes: [ife_id | _]} do
      # NOTE: the piggybacked index is the second one, compared to the invalid piggyback situation
      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        blocks_result: [Block.hashed_txs_at([comp], 4000)]
      }

      state = state |> piggyback_ife_from(ife_id, 1) |> Core.find_ifes_in_blocks(request)

      assert {:ok, []} = check_validity_filtered(request, state, only: [Event.InvalidPiggyback])
    end

    test "detects no double-spend of an output, if a different output is being spent in block",
         %{alice: alice, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      # NOTE: the piggybacked index is the second one, compared to the invalid piggyback situation
      tx_blknum = 3000

      # 2. transaction which _doesn't_ spend that piggybacked output
      comp = TestHelper.create_recovered([{tx_blknum, 0, 0, alice}], [])

      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)],
        blocks_result: [Block.hashed_txs_at([comp], 4000)]
      }

      state = state |> piggyback_ife_from(ife_id, 5) |> Core.find_ifes_in_blocks(request)

      assert {:ok, []} = check_validity_filtered(request, state, only: [Event.InvalidPiggyback])
    end

    test "does not look into ife_input_spending_blocks_result when it should not",
         %{processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      request = %ExitProcessor.Request{
        blknum_now: 5000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], 3000)]
      }

      state = state |> piggyback_ife_from(ife_id, 4) |> Core.find_ifes_in_blocks(request)

      # now zero out the prior result to make a sanity check of well-behaving wrt. to the database results
      request = %{request | blocks_result: [], ife_input_spending_blocks_result: nil}
      assert {:ok, []} = check_validity_filtered(request, state, only: [Event.InvalidPiggyback])
      assert {:error, _} = Core.get_output_challenge_data(request, state, txbytes(tx), 0)
    end

    test "detects multiple double-spends in single IFE, correctly as more piggybacks appear",
         %{alice: alice, processor_filled: state, transactions: [tx | _], ife_tx_hashes: [ife_id | _]} do
      tx_blknum = 3000
      txbytes = txbytes(tx)

      comp =
        TestHelper.create_recovered(
          [{1, 0, 0, alice}, {1, 2, 1, alice}, {tx_blknum, 0, 0, alice}, {tx_blknum, 0, 1, alice}],
          []
        )

      {comp_txbytes, alice_sig} = {txbytes(comp), sig(comp)}

      request = %ExitProcessor.Request{
        blknum_now: 4000,
        eth_height_now: 5,
        ife_input_spending_blocks_result: [Block.hashed_txs_at([tx], tx_blknum)]
      }

      state = state |> start_ife_from(comp) |> piggyback_ife_from(ife_id, 0) |> Core.find_ifes_in_blocks(request)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [0], outputs: []}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      state = state |> piggyback_ife_from(ife_id, 1)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [0, 1], outputs: []}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      state = state |> piggyback_ife_from(ife_id, 4)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [0, 1], outputs: [0]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      state = state |> piggyback_ife_from(ife_id, 5)

      assert {:ok, [%Event.InvalidPiggyback{txbytes: ^txbytes, inputs: [0, 1], outputs: [0, 1]}]} =
               check_validity_filtered(request, state, only: [Event.InvalidPiggyback])

      assert {:ok,
              %{
                in_flight_input_index: 1,
                in_flight_txbytes: ^txbytes,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 1,
                spending_sig: ^alice_sig
              }} = Core.get_input_challenge_data(request, state, txbytes, 1)

      assert {:ok,
              %{
                in_flight_txbytes: ^txbytes,
                in_flight_output_pos: Utxo.position(^tx_blknum, 0, 0),
                in_flight_proof: inclusion_proof,
                spending_txbytes: ^comp_txbytes,
                spending_input_index: 2,
                spending_sig: ^alice_sig
              }} = Core.get_output_challenge_data(request, state, txbytes, 0)

      assert_proof_sound(inclusion_proof)
    end
  end

  describe "produces challenges for bad piggybacks" do
    test "produces single challenge proof on double-spent piggyback input",
         %{
           invalid_piggyback_on_input: %{
             state: state,
             request: request,
             ife_input_index: ife_input_index,
             ife_txbytes: ife_txbytes,
             spending_txbytes: spending_txbytes,
             spending_input_index: spending_input_index,
             spending_sig: spending_sig
           }
         } do
      assert {:ok,
              %{
                in_flight_input_index: ^ife_input_index,
                in_flight_txbytes: ^ife_txbytes,
                spending_txbytes: ^spending_txbytes,
                spending_input_index: ^spending_input_index,
                spending_sig: ^spending_sig
              }} = Core.get_input_challenge_data(request, state, ife_txbytes, ife_input_index)
    end

    test "fail when asked to produce proof for wrong oindex",
         %{
           invalid_piggyback_on_input: %{
             state: state,
             request: request,
             ife_input_index: bad_pb_output,
             ife_txbytes: txbytes
           }
         } do
      assert bad_pb_output != 1

      assert {:error, :no_double_spend_on_particular_piggyback} =
               Core.get_input_challenge_data(request, state, txbytes, 1)
    end

    test "fail when asked to produce proof for wrong txhash",
         %{invalid_piggyback_on_input: %{state: state, request: request}, unrelated_tx: comp} do
      comp_txbytes = Transaction.raw_txbytes(comp)
      assert {:error, :ife_not_known_for_tx} = Core.get_input_challenge_data(request, state, comp_txbytes, 0)
      assert {:error, :ife_not_known_for_tx} = Core.get_output_challenge_data(request, state, comp_txbytes, 0)
    end

    test "fail when asked to produce proof for wrong badly encoded tx",
         %{invalid_piggyback_on_input: %{state: state, request: request}} do
      assert {:error, :malformed_transaction} = Core.get_input_challenge_data(request, state, <<0>>, 0)
      assert {:error, :malformed_transaction} = Core.get_output_challenge_data(request, state, <<0>>, 0)
    end

    test "fail when asked to produce proof for illegal oindex",
         %{invalid_piggyback_on_input: %{state: state, request: request, ife_txbytes: txbytes}} do
      assert {:error, :piggybacked_index_out_of_range} = Core.get_input_challenge_data(request, state, txbytes, -1)
      assert {:error, :piggybacked_index_out_of_range} = Core.get_output_challenge_data(request, state, txbytes, -1)
    end

    test "will fail if asked to produce proof for wrong output",
         %{
           invalid_piggyback_on_output: %{
             state: state,
             request: request,
             ife_input_index: bad_pb_output,
             ife_txbytes: txbytes
           }
         } do
      assert 2 != bad_pb_output - 4

      assert {:error, :no_double_spend_on_particular_piggyback} =
               Core.get_output_challenge_data(request, state, txbytes, 2)
    end

    test "will fail if asked to produce proof for correct piggyback on output",
         %{
           invalid_piggyback_on_output: %{
             state: state,
             request: request,
             ife_good_pb_index: good_pb_output,
             ife_txbytes: txbytes
           }
         } do
      assert {:error, :no_double_spend_on_particular_piggyback} =
               Core.get_output_challenge_data(request, state, txbytes, good_pb_output - 4)
    end
  end
end
