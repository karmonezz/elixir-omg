defmodule OMG.ExchangeHelper do
  alias OMG.Crypto
  alias OMG.DevCrypto
  alias OMG.State.Transaction

  def fund_order_recovered(inputs, outputs, nonce),
    do: fund_order_encoded(inputs, outputs, nonce) |> Transaction.Recovered.recover_from!()

  def fund_order_encoded(inputs, outputs, nonce) do
    fund_order_signed(inputs, outputs, nonce) |> Transaction.Signed.encode()
  end

  @spec fund_order_signed(
          list({pos_integer, non_neg_integer, 0 | 1, map}),
          list({map, Transaction.Payment.currency(), pos_integer}),
          binary()
        ) :: Transaction.Signed.t()
  def fund_order_signed(inputs, outputs, nonce) do
    [order_placer] = inputs |> Enum.map(fn {_, _, _, owner} -> owner.addr end) |> Enum.uniq()
    [exchange] = outputs |> Enum.map(fn {owner, _, _} -> owner.addr end) |> Enum.uniq()

    output_guard = output_preimage(exchange, order_placer, nonce) |> output_guard()

    raw_tx =
      Transaction.Payment.new(
        inputs |> Enum.map(fn {blknum, txindex, oindex, _} -> {blknum, txindex, oindex} end),
        outputs |> Enum.map(fn {_, currency, amount} -> {output_guard, currency, amount} end)
      )

    privs = get_private_keys(inputs)
    DevCrypto.sign(raw_tx, privs)
  end

  def settlement_recovered(inputs, outputs),
    do: settlement_encoded(inputs, outputs) |> Transaction.Recovered.recover_from!()

  def settlement_encoded(inputs, outputs) do
    settlement_signed(inputs, outputs) |> Transaction.Signed.encode()
  end

  @spec settlement_signed(
          list({pos_integer, non_neg_integer, 0 | 1, map, map, binary}),
          list({map, Transaction.currency(), pos_integer})
        ) :: Transaction.Signed.t()
  def settlement_signed(inputs, outputs) do
    [exchange] = inputs |> Enum.map(fn {_, _, _, owner, _, _} -> owner.addr end) |> Enum.uniq()

    raw_tx =
      Transaction.Settlement.new(
        inputs |> Enum.map(fn {blknum, txindex, oindex, _, _, _} -> {blknum, txindex, oindex} end),
        outputs |> Enum.map(fn {owner, currency, amount} -> {owner.addr, currency, amount} end),
        exchange
      )

    privs = get_settlement_private_keys(inputs)
    # FIXME: refactor getting of the Transaction.Signed
    %Transaction.Signed{sigs: exchange_sigs} = DevCrypto.sign(raw_tx, privs)

    raw_witnesses =
      inputs
      |> Enum.map(fn {_, _, _, holder, owner, nonce} -> output_preimage(holder.addr, owner.addr, nonce) end)
      |> Enum.zip(exchange_sigs)
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(&["settlement_witness", &1])

    %Transaction.Signed{raw_tx: raw_tx, sigs: raw_witnesses}
  end

  # FIXME: what with this?
  # def post_settlement_recovered(inputs, outputs), do: create_encoded(inputs, outputs) |> Transaction.Recovered.recover_from!()
  #
  # def post_settlement_encoded(inputs, outputs) do
  #   create_signed(inputs, outputs) |> Transaction.Signed.encode()
  # end
  #
  # def post_settlement_signed(inputs, outputs) do
  #   raw_tx =
  #     Transaction.Payment.new(
  #       inputs |> Enum.map(fn {blknum, txindex, oindex, _} -> {blknum, txindex, oindex} end),
  #       outputs |> Enum.map(fn {owner, currency, amount} -> {owner.addr, currency, amount} end)
  #     )
  #
  #   privs = get_private_keys(inputs)
  #   DevCrypto.sign(raw_tx, privs)
  # end

  # FIXME: this is made up
  defp output_preimage(exchange, order_placer, nonce),
    do: "output_type_is_deposit" <> exchange <> order_placer <> nonce

  defp output_guard(preimage) do
    preimage |> Crypto.hash() |> binary_part(0, 20)
  end

  # FIXME: following private fs copied from OMG.TestHelper - DRY?

  def sign_encode(%{} = tx, priv_keys), do: tx |> DevCrypto.sign(priv_keys) |> Transaction.Signed.encode()

  def sign_recover!(%{} = tx, priv_keys),
    do: tx |> sign_encode(priv_keys) |> Transaction.Recovered.recover_from!()

  defp get_private_keys(inputs) do
    filler = List.duplicate(<<>>, 4 - length(inputs))

    inputs
    |> Enum.map(fn {_, _, _, owner} -> owner.priv end)
    |> Enum.concat(filler)
  end

  # FIXME: tidy/ dry etc
  defp get_settlement_private_keys(inputs) do
    filler = List.duplicate(<<>>, 4 - length(inputs))

    inputs
    |> Enum.map(fn {_, _, _, holder, _, _} -> holder.priv end)
    |> Enum.concat(filler)
  end
end
