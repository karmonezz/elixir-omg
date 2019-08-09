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

defmodule OMG.State.Transaction.Payment.Tools do
  @moduledoc """
  Some useful shared tools to work with payment-like transactions
  """

  alias OMG.InputPointer
  alias OMG.State.Transaction
  alias OMG.Utxo

  require Transaction
  require Utxo

  @zero_metadata <<0::256>>

  def reconstruct_inputs(inputs_rlp) do
    with {:ok, inputs} <- parse_inputs(inputs_rlp),
         do: {:ok, inputs}
  end

  def reconstruct_metadata([]), do: {:ok, @zero_metadata}
  def reconstruct_metadata([metadata]) when Transaction.is_metadata(metadata), do: {:ok, metadata}
  def reconstruct_metadata([_]), do: {:error, :malformed_metadata}

  defp parse_inputs(inputs_rlp) do
    {:ok, Enum.map(inputs_rlp, &parse_input!/1)}
  rescue
    _ -> {:error, :malformed_inputs}
  end

  def filter_non_zero_inputs(inputs), do: Enum.filter(inputs, &InputPointer.Protocol.non_empty?/1)

  # FIXME: worse: we predetermine the input_pointer type, this is most likely bad - how to dispatch here?
  defp parse_input!(input_pointer), do: InputPointer.UtxoPosition.reconstruct(input_pointer)

  defp inputs_without_gaps(inputs),
    do: check_for_gaps(inputs, &InputPointer.Protocol.non_empty?/1, {:error, :inputs_contain_gaps})

  @doc """
  Check if any consecutive pair of elements contains empty followed by non-empty element
  which means there is a gap
  """
  def check_for_gaps(items, is_non_empty_predicate, error) do
    items
    |> Enum.map(is_non_empty_predicate)
    # discard - discards last unpaired element from a comparison
    |> Stream.chunk_every(2, 1, :discard)
    |> Enum.any?(fn
      [false, true] -> true
      _ -> false
    end)
    |> if(do: error, else: {:ok, items})
  end
end
