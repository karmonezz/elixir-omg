use Mix.Config

config :omisego_api,
  depositor_block_finality_margin: 5,
  depositor_get_deposits_interval_ms: 60_000,
  depositor_max_block_range_in_deposits_query: 5,
  contract_deployment_block: 10
