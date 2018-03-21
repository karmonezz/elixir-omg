defmodule OmiseGO.DB do
  @moduledoc """
  Our-types-aware port/adapter to the db backend
  """
  # TODO 1: leveldb interactions should be polished out.
  #         Includes better than Poison value encoding, overhaulf of key encoding,
  #         smoke-test (smoke test can be a temporary thing), iron out shell-core interactions
  # TODO 2: still needs to be integrated into other components and integration-tested

  ### Client (port)

  def start_link do
    GenServer.start_link(OmiseGO.DB.LevelDBServer, :ok, name: OmiseGO.DB.LevelDBServer)
  end

  def multi_update(db_updates) do
    GenServer.call(OmiseGO.DB.LevelDBServer, {:multi_update, db_updates})
  end

  def tx(hash) do
    GenServer.call(OmiseGO.DB.LevelDBServer, {:tx, hash})
  end

  # TODO: FreshBlocks fetches by block number and returns by block number, while we probably want by block hash
  @spec blocks(block_to_fetch :: list()) :: {:ok, map} | {:error, any}
  def blocks(blocks_to_fetch) do
    GenServer.call(OmiseGO.DB.LevelDBServer, {:blocks, blocks_to_fetch})
  end

  def block_hashes(block_numbers_to_fetch) do
    GenServer.call(OmiseGO.DB.LevelDBServer, {:block_hashes, block_numbers_to_fetch})
  end

  def child_top_block_number do
    GenServer.call(OmiseGO.DB.LevelDBServer, {:child_top_block_number})
  end

  def utxos do
    GenServer.call(OmiseGO.DB.LevelDBServer, {:utxos})
  end

  def height do
    #FIXME
    {:ok, 1}
  end

  def last_deposit_height do
    GenServer.call(OmiseGO.DB.LevelDBServer, :last_deposit_block_height)
  end

  defmodule LevelDBServer do
    @moduledoc """
    Server handling a db connection to leveldb
    """
    defstruct [:db_ref]

    use GenServer

    alias OmiseGO.DB.LevelDBCore

    import Exleveldb

    def init(:ok) do
      # TODO: handle file location properly - probably pass as parameter here and configure in DB.Application
      {:ok, db_ref} = open("/home/user/.omisego/data")
      {:ok, %__MODULE__{db_ref: db_ref}}
    end

    def handle_call({:tx, hash}, _from, %__MODULE__{db_ref: db_ref} = state) do
      result =
        with key <- LevelDBCore.tx_key(hash),
             {:ok, value} <- get(db_ref, key),
             {:ok, decoded} <- LevelDBCore.decode_value(:tx, value),
             do: {:ok, decoded}
      {:reply, result, state}
    end

    def handle_call({:blocks, blocks_to_fetch}, _from, %__MODULE__{db_ref: db_ref} = state) do
      result =
        blocks_to_fetch
        |> Enum.map(&LevelDBCore.block_key/1)
        |> Enum.map(fn key -> get(db_ref, key) end)
        |> Enum.map(fn {:ok, value} -> LevelDBCore.decode_value(:block, value) end)
      {:reply, result, state}
    end

    def handle_call({:block_hashes, _block_numbers_to_fetch}, _from, %__MODULE__{db_ref: _db_ref} = _state) do
      :not_implemented
    end

    def handle_call({:child_top_block_number}, _from, %__MODULE__{db_ref: _db_ref} = _state) do
      :not_implemented
    end

    def handle_call({:utxos}, _from, %__MODULE__{db_ref: db_ref} = state) do
      with key <- LevelDBCore.utxo_list_key(),
           {:ok, utxo_list} <- get(db_ref, key),
           utxo_keys <- Enum.map(utxo_list, &LevelDBCore.utxo_key/1),
           result <- Enum.map(utxo_keys, fn key -> get(db_ref, key) end),
           do: {:reply, result, state}
    end

    def handle_call({:multi_update, db_updates}, _from, %__MODULE__{db_ref: db_ref} = state) do
      operations =
        db_updates
        |> LevelDBCore.parse_multi_updates

      :ok = write(db_ref, operations)
      {:reply, :ok, state}
    end

    def handle_call(:last_deposit_block_height, _from, %__MODULE__{db_ref: db_ref} = state) do
      #TODO: initialize db with height 0
      with key <- LevelDBCore.last_deposit_block_height_key(),
           {:ok, height} <- get(db_ref, key),
           do: {:reply, LevelDBCore.decode_value(:last_deposit_block_height, height), state}
    end
  end
end
