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

defmodule OMG.State.Transaction.Settlement do
  alias OMG.Crypto
  alias OMG.State.Transaction
  alias OMG.Utxo

  require Transaction
  require Utxo

  @default_metadata nil

  @zero_address OMG.Eth.zero_address()

  defstruct [:inputs, :outputs, metadata: @default_metadata]

  @type t() :: %__MODULE__{
          inputs: list(input()),
          outputs: list(output()),
          metadata: metadata()
        }
  @type metadata() :: binary() | nil

  @type input() :: %{
          blknum: non_neg_integer(),
          txindex: non_neg_integer(),
          oindex: non_neg_integer()
        }

  @type output() :: %{
          owner: Crypto.address_t(),
          currency: currency(),
          amount: non_neg_integer()
        }
  @type currency() :: Crypto.address_t()

  @max_inputs 4
  @max_outputs 4

  defmacro is_metadata(metadata) do
    quote do
      unquote(metadata) == nil or (is_binary(unquote(metadata)) and byte_size(unquote(metadata)) == 32)
    end
  end

  defmacro max_inputs do
    quote do
      unquote(@max_inputs)
    end
  end

  defmacro max_outputs do
    quote do
      unquote(@max_outputs)
    end
  end

  @doc """
  Creates a new transaction from a list of inputs and a list of outputs.
  Adds empty (zeroes) inputs and/or outputs to reach the expected size
  of `@max_inputs` inputs and `@max_outputs` outputs.

  assumptions:
  ```
    length(inputs) <= @max_inputs
    length(outputs) <= @max_outputs
  ```
  """
  @spec new(
          list({pos_integer, pos_integer, 0..3}),
          list({Crypto.address_t(), currency(), pos_integer}),
          metadata()
        ) :: t()
  def new(inputs, outputs, metadata \\ @default_metadata)

  def new(inputs, outputs, metadata) do
    # TODO: steal from Payment and mold, because for now these are the same
    tx_data = Transaction.Payment.new(inputs, outputs, metadata) |> Map.from_struct()

    struct!(__MODULE__, tx_data)
  end

  @doc """
  Transaform the structure of RLP items after a successful RLP decode of a raw transaction, into a structure instance
  """
  def reconstruct(rlp) do
    # TODO: steal from Payment and mold, because for now these are the same
    with {:ok, payment_struct} <- Transaction.Payment.reconstruct(rlp) do
      tx_data = payment_struct |> Map.from_struct()
      {:ok, struct!(__MODULE__, tx_data)}
    end
  end
end

defimpl OMG.State.Transaction.Protocol, for: OMG.State.Transaction.Settlement do
  alias OMG.State.Transaction
  alias OMG.Utxo

  require Transaction
  require Utxo
  require Transaction.Settlement

  @zero_address OMG.Eth.zero_address()

  # TODO: dry wrt. Application.fetch_env!(:omg, :tx_types_modules)? Use `bimap` perhaps?
  @settlement_marker <<2>>

  @doc """
  Turns a structure instance into a structure of RLP items, ready to be RLP encoded, for a raw transaction
  """
  def get_data_for_rlp(%Transaction.Settlement{metadata: metadata} = tx) do
    # TODO: steal from Payment and mold, because for now these are the same
    tx
    |> Transaction.Protocol.OMG.State.Transaction.Payment.get_data_for_rlp()
    |> List.replace_at(0, @settlement_marker)
  end

  def get_outputs(tx) do
    # NOTE: for now behaves just like payment, subject to change
    Transaction.Protocol.OMG.State.Transaction.Payment.get_outputs(tx)
  end

  def get_inputs(tx) do
    # NOTE: for now behaves just like payment, subject to change
    Transaction.Protocol.OMG.State.Transaction.Payment.get_inputs(tx)
  end

  def valid?(%Transaction.Settlement{}, %Transaction.Signed{sigs: sigs} = tx) do
    tx
    |> Transaction.get_inputs()
    |> all_inputs_witnessed?(sigs)
  end

  # FIXME spec out document
  def can_apply?(tx, input_utxos) do
    # NOTE: for now behaves just like payment, subject to change
    Transaction.Protocol.OMG.State.Transaction.Payment.can_apply?(tx, input_utxos)
  end

  def get_effects(tx, blknum, tx_index) do
    # NOTE: for now behaves just like payment, subject to change
    Transaction.Protocol.OMG.State.Transaction.Payment.get_effects(tx, blknum, tx_index)
  end

  defp all_inputs_witnessed?(non_zero_inputs, sigs) do
    count_non_zero_signatures = Enum.count(sigs, &(&1 != @empty_signature))
    count_non_zero_inputs = length(non_zero_inputs)

    cond do
      count_non_zero_signatures > count_non_zero_inputs -> {:error, :superfluous_signature}
      count_non_zero_signatures < count_non_zero_inputs -> {:error, :missing_signature}
      true -> true
    end
  end
end
