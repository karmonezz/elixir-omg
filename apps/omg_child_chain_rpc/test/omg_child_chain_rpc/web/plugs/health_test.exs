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

defmodule OMG.ChildChainRPC.Plugs.HealthTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false

  alias OMG.ChildChainRPC.Web.TestHelper
  @alarm_1 {:boot_in_progress, %{node: Node.self(), reporter: __MODULE__}}
  @alarm_2 {:ethereum_client_connection, %{node: Node.self(), reporter: __MODULE__}}

  describe "testing for boot_in_progress alarm" do
    @tag fixtures: [:phoenix_sandbox]
    test "if alarm.get endpoint does not reject request because alarms are raised" do
      :ok = :alarm_handler.clear_alarm(@alarm_2)
      :ok = :alarm_handler.set_alarm(@alarm_1)

      :ok =
        pull_client_alarm(
          300,
          %{
            "data" => [
              %{
                "boot_in_progress" => %{
                  "node" => "nonode@nohost",
                  "reporter" => "Elixir.OMG.ChildChainRPC.Plugs.HealthTest"
                }
              }
            ],
            "success" => true
          },
          fn -> TestHelper.rpc_call(:post, "/alarm.get", %{}) end
        )

      :ok = :alarm_handler.clear_alarm(@alarm_1)
    end

    @tag fixtures: [:phoenix_sandbox]
    test "if block.get endpoint rejects request because alarms are raised" do
      :ok = :alarm_handler.clear_alarm(@alarm_2)
      :ok = :alarm_handler.set_alarm(@alarm_1)

      :ok =
        pull_client_alarm(
          300,
          %{
            "data" => %{
              "code" => "operation:service_unavailable",
              "description" => "The server is not ready to handle the request.",
              "object" => "error"
            },
            "success" => false
          },
          fn -> TestHelper.rpc_call(:post, "/block.get", %{}) end
        )

      :ok = :alarm_handler.clear_alarm(@alarm_1)
    end

    @tag fixtures: [:phoenix_sandbox]
    test "if block.get endpoint rejects the request because of bad params when alarm is cleared" do
      :ok = :alarm_handler.clear_alarm(@alarm_1)
      :ok = :alarm_handler.clear_alarm(@alarm_2)
      missing_param = %{}

      assert catch_error(
               %{
                 "data" => %{
                   "code" => "operation:service_unavailable"
                 }
               } = TestHelper.rpc_call(:post, "/block.get", missing_param)
             )
    end
  end

  describe "testing for ethereum_client_connection alarm " do
    @tag fixtures: [:phoenix_sandbox]
    test "if alarm.get endpoint works even though alarms are raised" do
      :ok = :alarm_handler.set_alarm(@alarm_2)
      :ok = :alarm_handler.clear_alarm(@alarm_1)

      :ok =
        pull_client_alarm(
          300,
          %{
            "data" => [
              %{
                "ethereum_client_connection" => %{
                  "node" => "nonode@nohost",
                  "reporter" => "Elixir.OMG.ChildChainRPC.Plugs.HealthTest"
                }
              }
            ],
            "success" => true
          },
          fn -> TestHelper.rpc_call(:post, "/alarm.get", %{}) end
        )

      :ok = :alarm_handler.clear_alarm(@alarm_2)
    end

    @tag fixtures: [:phoenix_sandbox]
    test "if block.get endpoint rejects request because alarms are raised" do
      :ok = :alarm_handler.set_alarm(@alarm_2)
      :ok = :alarm_handler.clear_alarm(@alarm_1)

      :ok =
        pull_client_alarm(
          300,
          %{
            "data" => %{
              "code" => "operation:service_unavailable",
              "description" => "The server is not ready to handle the request.",
              "object" => "error"
            },
            "success" => false
          },
          fn -> TestHelper.rpc_call(:post, "/block.get", %{}) end
        )

      :ok = :alarm_handler.clear_alarm(@alarm_2)
    end

    @tag fixtures: [:phoenix_sandbox]
    test "if block.get endpoint rejects the request because of bad params when alarm is cleared" do
      :ok = :alarm_handler.clear_alarm(@alarm_1)
      :ok = :alarm_handler.clear_alarm(@alarm_2)
      missing_param = %{}

      assert catch_error(
               %{
                 "data" => %{
                   "code" => "operation:service_unavailable"
                 }
               } = TestHelper.rpc_call(:post, "/block.get", missing_param)
             )
    end
  end

  defp pull_client_alarm(0, _, _), do: :cant_match

  defp pull_client_alarm(n, match, fnn) do
    endpoint_call_result = fnn.()
    match = Map.put_new(match, "version", Map.get(endpoint_call_result, "version"))
    match = Map.put_new(match, "service_name", Map.get(endpoint_call_result, "service_name"))

    case endpoint_call_result do
      ^match ->
        :ok

      _ ->
        Process.sleep(10)
        pull_client_alarm(n - 1, match, fnn)
    end
  end
end
