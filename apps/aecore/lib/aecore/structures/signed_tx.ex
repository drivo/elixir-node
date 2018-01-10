defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx

  @type signed_tx() :: %SignedTx{}
  @type tx() :: %TxData{}

  @doc """
  Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase(signed_tx()) :: boolean()
  def is_coinbase(%{data: %{from_acc: key}, signature: signature}) do
    key == nil && signature == nil
  end

  @spec is_valid(signed_tx()) :: boolean()
  def is_valid(%{data: data, signature: signature}) do
    data.value >= 0 &&
      Aewallet.Signing.verify(:erlang.term_to_binary(data), signature, data.from_acc)
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  ## Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with

  """
  @spec sign_tx(tx(), binary()) :: {:ok, %SignedTx{}}
  def sign_tx(tx, priv_key) do
    signature = Aewallet.Signing.sign(:erlang.term_to_binary(tx), priv_key)
    {:ok, %SignedTx{data: tx, signature: signature}}
  end

  defp aewallet_path(), do: Application.get_env(:aecore, :aewallet)[:path]
end
