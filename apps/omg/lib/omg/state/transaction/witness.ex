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

defmodule OMG.State.Transaction.Witness do
  @moduledoc """
  Code required to validate and recover raw witnesses (e.g. signatures) goes here.

  These should be called by the stateless validation, in order to put load off stateful validation (i.e. sig recovery)
  """
  alias OMG.Crypto
  @signature_length 65
  @address_length 20

  @type t :: Crypto.address_t() | list(binary() | list(binary))

  @doc """
  Pre-check done after decoding to quickly assert whether the witness has one of valid forms
  """
  def valid?(["settlement_witness", [preimage, exchange_sig]]) when is_binary(exchange_sig) and is_binary(preimage) do
    signature_length?(exchange_sig) and is_preimage?(preimage)
  end

  def valid?(witness) when is_binary(witness), do: signature_length?(witness)
  def valid?(_), do: false

  @doc """
  Prepares the witness to be quickly used in stateful validation
  """
  def recover(["settlement_witness", raw_witness], raw_tx_hash, _raw_tx) when is_list(raw_witness) do
    [preimage, exchange_sig] = raw_witness

    with {:ok, exchange_addr} <- Crypto.recover_address(raw_tx_hash, exchange_sig),
         do: {:ok, {preimage, exchange_addr}}
  end

  def recover(raw_witness, raw_txhash, _raw_tx) when is_binary(raw_witness),
    do: Crypto.recover_address(raw_txhash, raw_witness)

  defp signature_length?(sig) when byte_size(sig) == @signature_length, do: true
  defp signature_length?(_sig), do: false

  defp is_preimage?("output_type_is_deposit" <> rest) when byte_size(rest) >= 2 * @address_length, do: true
  defp is_preimage?(_), do: false
end
