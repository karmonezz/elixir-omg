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
  alias OMG.Output.FungibleMoreVPToken
  alias OMG.Output.FungibleMVPToken
  alias OMG.State.Transaction
  alias OMG.Utxo

  import Transaction.Payment.Tools

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
          Crypto.address_t(),
          metadata()
        ) :: t()
  def new(inputs, outputs, confirmer, metadata \\ @default_metadata)

  def new(inputs, outputs, confirmer, metadata) do
    # TODO: steal from Payment and mold, because for now these are the same
    Transaction.Payment.new(inputs, outputs, metadata) |> payment_to_settlement(confirmer)
  end

  @doc """
  Transaform the structure of RLP items after a successful RLP decode of a raw transaction, into a structure instance
  """
  def reconstruct([inputs_rlp, outputs_rlp | rest_rlp])
      when rest_rlp == [] or length(rest_rlp) == 1 do
    with {:ok, inputs} <- reconstruct_inputs(inputs_rlp),
         {:ok, outputs} <- reconstruct_outputs(outputs_rlp),
         {:ok, metadata} <- reconstruct_metadata(rest_rlp),
         do: {:ok, %__MODULE__{inputs: inputs, outputs: outputs, metadata: metadata}}
  end

  def reconstruct(_), do: {:error, :malformed_transaction}

  # FIXME: somewhat copy-pasted - can we do sth about this?

  defp reconstruct_outputs(outputs_rlp) do
    with {:ok, outputs} <- parse_outputs(outputs_rlp),
         {:ok, outputs} <- outputs_without_gaps(outputs),
         do: {:ok, filter_non_zero_outputs(outputs)}
  end

  defp parse_outputs(outputs_rlp) do
    outputs = Enum.map(outputs_rlp, &parse_output!/1)

    with nil <- Enum.find(outputs, &match?({:error, _}, &1)),
         do: {:ok, outputs}
  rescue
    _ -> {:error, :malformed_outputs}
  end

  defp filter_non_zero_outputs(outputs),
    do:
      Enum.reject(
        outputs,
        &match?(%{owner: @zero_address, currency: @zero_address, amount: 0, confirmer: @zero_address}, &1)
      )

  defp parse_output!(output), do: FungibleMVPToken.reconstruct(output)

  defp outputs_without_gaps({:error, _} = error), do: error

  defp outputs_without_gaps(outputs),
    do:
      check_for_gaps(
        outputs,
        %FungibleMVPToken{owner: @zero_address, currency: @zero_address, amount: 0, confirmer: @zero_address},
        {:error, :outputs_contain_gaps}
      )

  # FIXME end copy pasted code here, see fixme above

  defp payment_to_settlement(%Transaction.Payment{} = payment_struct, confirmer) do
    payment_struct
    |> Map.from_struct()
    |> Map.update!(:outputs, fn outputs -> Enum.map(outputs, &append_confirmer(&1, confirmer)) end)
    |> (&struct!(__MODULE__, &1)).()
  end

  defp append_confirmer(%FungibleMoreVPToken{} = without_confirmer, confirmer) do
    without_confirmer
    |> Map.from_struct()
    |> Map.put(:confirmer, confirmer)
    |> (&struct!(FungibleMVPToken, &1)).()
  end
end

defimpl OMG.State.Transaction.Protocol, for: OMG.State.Transaction.Settlement do
  alias OMG.State.Transaction
  alias OMG.Utxo

  require Transaction
  require Utxo
  require Transaction.Settlement

  # TODO: dry wrt. Application.fetch_env!(:omg, :tx_types_modules)? Use `bimap` perhaps?
  @settlement_marker <<2>>

  @doc """
  Turns a structure instance into a structure of RLP items, ready to be RLP encoded, for a raw transaction
  """
  def get_data_for_rlp(%Transaction.Settlement{} = tx) do
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

  def valid?(%Transaction.Settlement{}, %Transaction.Signed{}) do
    # so far we don't want any such checks
    true
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
end
