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

defmodule OMG.DB.ReleaseTasks.SetKeyValueDBTest do
  use ExUnit.Case, async: false
  alias OMG.DB.ReleaseTasks.SetKeyValueDB
  @app :omg_db

  @configuration_old Application.get_all_env(@app)
  test "if environment variables get applied in the configuration" do
    :ok = System.put_env("DB_TYPE", "ROCKsDB")
    :ok = System.put_env("DB_PATH", "/tmp/YOLO")
    :ok = SetKeyValueDB.init([])
    configuration = Enum.sort(Application.get_all_env(@app))
    :rocksdb = configuration[:type]
    "/tmp/YOLO" = configuration[:path]

    ^configuration =
      @configuration_old
      |> Keyword.put(:type, :rocksdb)
      |> Keyword.put(:path, "/tmp/YOLO")
      |> Enum.sort()
  end

  test "if default configuration is used when there's no environment variables" do
    :ok = Enum.each(@configuration_old, fn {key, value} -> Application.put_env(@app, key, value, persistent: true) end)
    :ok = System.delete_env("DB_TYPE")
    :ok = System.delete_env("DB_PATH")
    :ok = SetKeyValueDB.init([])
    configuration = Application.get_all_env(@app)
    sorted_configuration = Enum.sort(configuration)
    ^sorted_configuration = Enum.sort(@configuration_old)
  end

  test "if faulty db type exits" do
    :ok = System.put_env("DB_TYPE", "LEVELDB1111")

    try do
      SetKeyValueDB.init([])
    catch
      :exit, _reason ->
        :ok = System.delete_env("DB_TYPE")
    end
  end
end
