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

defmodule OMG.InputPointer.OutputId do
  defstruct [:id]

  @type t :: %__MODULE__{id: binary()}

  def from_db_key(db_key), do: %__MODULE__{id: db_key}
  def reconstruct(id) when is_binary(id), do: %__MODULE__{id: id}
end

defimpl OMG.InputPointer.Protocol, for: OMG.InputPointer.OutputId do
  alias OMG.InputPointer.OutputId

  # TODO: dry wrt. Application.fetch_env!(:omg, :input_pointer_types_modules)? Use `bimap` perhaps?
  @input_pointer_type_marker <<2>>

  @spec to_db_key(OutputId.t()) :: {:input_pointer, binary(), tuple()}
  def to_db_key(%OutputId{id: id}), do: {:input_pointer, @input_pointer_type_marker, id}

  @spec get_data_for_rlp(OutputId.t()) :: list()
  def get_data_for_rlp(%OutputId{id: id}), do: id

  @spec non_empty?(OutputId.t()) :: boolean()
  def non_empty?(%OutputId{id: ""}), do: false
  def non_empty?(%OutputId{id: id}) when is_binary(id), do: true
end
