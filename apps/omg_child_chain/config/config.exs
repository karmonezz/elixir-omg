use Mix.Config

# see [here](README.md) for documentation

config :omg_child_chain,
  submission_finality_margin: 20,
  block_queue_eth_height_check_interval_ms: 6_000,
  fee_file_check_interval_ms: 10_000,
  child_block_minimal_enqueue_gap: 1,
  fee_specs_file_name: "fee_specs.json",
  ignore_fees: false,
  metrics_collection_interval: 60_000

import_config "#{Mix.env()}.exs"
