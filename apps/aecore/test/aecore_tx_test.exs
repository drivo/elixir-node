defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData

  setup wallet do
    [
      path: File.cwd!
      |> Path.join("test/aewallet/")
      |> Path.join("wallet--2018-1-10-10-49-58"),
      pass: "1234",
      to_acc: <<4, 3, 85, 89, 175, 35, 38, 163, 5, 16, 147, 44, 147, 215, 20, 21, 141, 92,
      253, 96, 68, 201, 43, 224, 168, 79, 39, 135, 113, 36, 201, 236, 179, 76, 186,
      91, 130, 3, 145, 215, 221, 167, 128, 23, 63, 35, 140, 174, 35, 233, 188, 120,
        63, 63, 29, 61, 179, 181, 221, 195, 61, 207, 76, 135, 26>>
    ]
  end

  setup tx do
    to_account = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    [
      nonce: Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1,
      lock_time_block: Chain.top_block().header.height +
      Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1,
      to_acc: <<4, 234, 31, 124, 43, 123, 54, 65, 213>>,
      wallet_path: File.cwd!
      |> Path.join("test/aewallet/")
      |> Path.join("wallet--2018-1-10-10-49-58"),
      wallet_pass: "1234"
    ]
  end

  @tag :tx
  test "create and verify a signed tx", tx do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(tx.wallet_path, tx.wallet_pass)
    {:ok, tx_data} = TxData.create(from_acc, tx.to_acc, 5, tx.nonce, 1, tx.lock_time_block)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(tx.wallet_path, tx.wallet_pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = :erlang.term_to_binary(signed_tx.data)
    assert :true = Aewallet.Signing.verify(message, signature, from_acc)
  end

  test "positive tx valid", wallet  do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    {:ok, tx_data} = TxData.create(from_acc, wallet.to_acc, 5,
      Map.get(Chain.chain_state, wallet.to_acc, %{nonce: 0}).nonce + 1, 1)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(wallet.path, wallet.pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = :erlang.term_to_binary(signed_tx.data)
    assert :true = Aewallet.Signing.verify(message, signature, from_acc)
  end

  test "negative tx invalid", wallet do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    {:ok, tx_data} = TxData.create(from_acc, wallet.to_acc, -5,
      Map.get(Chain.chain_state, wallet.to_acc, %{nonce: 0}).nonce + 1, 1)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(wallet.path, wallet.pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_valid(signed_tx)
  end

  test "coinbase tx invalid", wallet do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    {:ok, tx_data} = TxData.create(from_acc, wallet.to_acc, 5,
      Map.get(Chain.chain_state, wallet.to_acc, %{nonce: 0}).nonce + 1, 1)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(wallet.path, wallet.pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_coinbase(signed_tx)
  end
end
