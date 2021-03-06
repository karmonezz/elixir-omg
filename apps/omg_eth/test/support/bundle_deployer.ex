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

defmodule OMG.Eth.BundleDeployer do
  @moduledoc """
  Convenience module that performs the entire root chain contract suite (plasma framework + exit games) deployment for
  tests
  """

  alias OMG.Eth
  alias OMG.Eth.Deployer

  use OMG.Utils.LoggerExt

  @tx_defaults Eth.Defaults.tx_defaults()

  @gas_init_tx 500_000

  #
  # Some contract-dependent constants
  #
  # NOTE tx marker must match values defined in the `omg` app. This doesn't depend on `omg` so can't import from there
  # TODO drying this properly would require moving at least part of the deployment to `omg`. Not ready for this yet
  @payment_tx_marker 1
  # `Protocol.MORE_VP()` from `Protocol.sol`
  @morevp_protocol_marker 2
  @eth_vault_number 1
  @erc20_vault_number 2
  #

  import Eth.Encoding, only: [to_hex: 1, int_from_hex: 1]

  def deploy_all(root_path, deployer_addr, authority, exit_period_seconds \\ nil) do
    exit_period_seconds = get_exit_period(exit_period_seconds)

    transact_opts = @tx_defaults |> Keyword.put(:gas, @gas_init_tx)

    transactions_before = get_transaction_count(deployer_addr)

    {:ok, txhash, plasma_framework_addr} =
      Deployer.create_new("PlasmaFramework", root_path, deployer_addr, exit_period_seconds: exit_period_seconds)

    {:ok, _} = Eth.RootChainHelper.init_authority(authority, %{plasma_framework: plasma_framework_addr})
    {:ok, _, eth_deposit_verifier_addr} = Deployer.create_new("EthDepositVerifier", root_path, deployer_addr, [])
    {:ok, _, erc20_deposit_verifier_addr} = Deployer.create_new("Erc20DepositVerifier", root_path, deployer_addr, [])

    {:ok, _, eth_vault_addr} =
      Deployer.create_new("EthVault", root_path, deployer_addr, plasma_framework: plasma_framework_addr)

    {:ok, _, erc20_vault_addr} =
      Deployer.create_new("Erc20Vault", root_path, deployer_addr, plasma_framework: plasma_framework_addr)

    {:ok, _} =
      Eth.contract_transact(
        deployer_addr,
        eth_vault_addr,
        "setDepositVerifier(address)",
        [eth_deposit_verifier_addr],
        transact_opts
      )

    {:ok, _} =
      Eth.contract_transact(
        deployer_addr,
        plasma_framework_addr,
        "registerVault(uint256,address)",
        [@eth_vault_number, eth_vault_addr],
        transact_opts
      )

    {:ok, _} =
      Eth.contract_transact(
        deployer_addr,
        erc20_vault_addr,
        "setDepositVerifier(address)",
        [erc20_deposit_verifier_addr],
        transact_opts
      )

    {:ok, _} =
      Eth.contract_transact(
        deployer_addr,
        plasma_framework_addr,
        "registerVault(uint256,address)",
        [@erc20_vault_number, erc20_vault_addr],
        transact_opts
      )

    {:ok, _, payment_spending_condition_registry_addr} =
      Deployer.create_new("PaymentSpendingConditionRegistry", root_path, deployer_addr, [])

    {:ok, _, output_guard_handler_registry_addr} =
      Deployer.create_new("OutputGuardHandlerRegistry", root_path, deployer_addr, [])

    {:ok, _, payment_output_guard_handler_addr} =
      Deployer.create_new("PaymentOutputGuardHandler", root_path, deployer_addr, tx_type_marker: @payment_tx_marker)

    {:ok, _} =
      Eth.contract_transact(
        deployer_addr,
        output_guard_handler_registry_addr,
        "registerOutputGuardHandler(uint256,address)",
        [@payment_tx_marker, payment_output_guard_handler_addr],
        transact_opts
      )

    {:ok, _, payment_exit_game_addr} =
      Deployer.create_new(
        "PaymentExitGame",
        root_path,
        deployer_addr,
        plasma_framework: plasma_framework_addr,
        eth_vault: eth_vault_addr,
        erc20_vault: erc20_vault_addr,
        output_guard_handler: output_guard_handler_registry_addr,
        spending_condition: payment_spending_condition_registry_addr
      )

    {:ok, _} =
      Eth.contract_transact(
        deployer_addr,
        plasma_framework_addr,
        "registerExitGame(uint256,address,uint8)",
        [@payment_tx_marker, payment_exit_game_addr, @morevp_protocol_marker],
        transact_opts
      )
      |> Eth.DevHelpers.transact_sync!()

    assert_count_of_mined_transactions(deployer_addr, transactions_before, 18)

    {:ok, txhash,
     %{
       plasma_framework: plasma_framework_addr,
       eth_vault: eth_vault_addr,
       erc20_vault: erc20_vault_addr,
       payment_exit_game: payment_exit_game_addr
     }}
  end

  # instead of `transact_sync!()` on every call, we only check if the expected count of txs were mined from the deployer
  defp assert_count_of_mined_transactions(deployer_addr, transactions_before, expected_count) do
    transactions_after = get_transaction_count(deployer_addr)
    count = transactions_after - transactions_before

    if count != expected_count,
      do:
        Logger.warn(
          "Transactions from deployer mined (#{inspect(count)}) differs from the " <>
            "expected (#{inspect(expected_count)}). Check the deployment pipeline for possible failures"
        )
  end

  defp get_transaction_count(deployer_addr) do
    {:ok, transactions_before} = Ethereumex.HttpClient.eth_get_transaction_count(to_hex(deployer_addr))
    int_from_hex(transactions_before)
  end

  defp get_exit_period(nil) do
    Application.fetch_env!(:omg_eth, :exit_period_seconds)
  end

  defp get_exit_period(exit_period), do: exit_period
end
