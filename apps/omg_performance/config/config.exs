use Mix.Config

config :briefly, directory: ["/tmp/omisego"]

config :omg_performance, watcher_url: "localhost:7434"

import_config "#{Mix.env()}.exs"
