defmodule Aecore.Oracle.Tx.OracleRegistrationTx do
  @moduledoc """
  Module defining the OracleRegistration transaction
  """

  use Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.{Chainstate, Identifier}
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Expected structure for the OracleRegistration Transaction"
  @type payload :: %{
          query_format: String.t(),
          response_format: String.t(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl(),
          vm_version: non_neg_integer()
        }

  @typedoc "Structure of the OracleRegistration Transaction type"
  @type t :: %OracleRegistrationTx{
          query_format: String.t(),
          response_format: String.t(),
          query_fee: non_neg_integer(),
          ttl: Oracle.ttl(),
          vm_version: non_neg_integer()
        }

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Chainstate.oracles()

  defstruct [
    :query_format,
    :response_format,
    :query_fee,
    :ttl,
    :vm_version
  ]

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

  @spec init(payload()) :: OracleRegistrationTx.t()
  def init(%{
        query_format: query_format,
        response_format: response_format,
        query_fee: query_fee,
        ttl: ttl,
        vm_version: vm_version
      }) do
    %OracleRegistrationTx{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl,
      vm_version: vm_version
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(OracleRegistrationTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %OracleRegistrationTx{
          query_format: query_format,
          response_format: response_format,
          ttl: ttl,
          vm_version: vm_version
        },
        %DataTx{senders: senders}
      ) do
    cond do
      !is_binary(query_format) && !is_binary(response_format) ->
        {:error, "#{__MODULE__}: Invalid query or response format definition"}

      !Oracle.ttl_is_valid?(ttl) ->
        {:error, "#{__MODULE__}: Invalid ttl"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      Oracle.check_vm_version(vm_version) != :ok ->
        {:error, "#{__MODULE__}:  Bad VM version: #{inspect(vm_version)}"}

      true ->
        :ok
    end
  end

  @doc """
  Enters an oracle in the oracle state tree
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        oracles,
        block_height,
        %OracleRegistrationTx{
          query_format: query_format,
          response_format: response_format,
          query_fee: query_fee,
          ttl: ttl,
          vm_version: vm_version
        },
        %DataTx{senders: [%Identifier{value: sender}]},
        _context
      ) do
    identified_oracle_owner = Identifier.create_identity(sender, :oracle)

    oracle = %Oracle{
      owner: identified_oracle_owner,
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      expires: Oracle.calculate_absolute_ttl(ttl, block_height),
      vm_version: vm_version
    }

    {:ok,
     {
       accounts,
       OracleStateTree.insert_oracle(oracles, oracle)
     }}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
          DataTx.t(),
          Transaction.context()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        oracles,
        block_height,
        %OracleRegistrationTx{ttl: ttl} = tx,
        %DataTx{fee: fee, senders: [%Identifier{value: sender}]},
        _context
      ) do
    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(ttl)}"}

      OracleStateTree.exists_oracle?(oracles, sender) ->
        {:error, "#{__MODULE__}: Account: #{inspect(sender)} is already an oracle"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          OracleRegistrationTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(
        %DataTx{payload: %OracleRegistrationTx{ttl: ttl}, fee: fee},
        _oracles_tree,
        block_height
      ) do
    ttl_fee = fee - GovernanceConstants.oracle_register_base_fee()

    case ttl do
      %{ttl: ttl, type: :relative} ->
        ttl_fee >= Oracle.calculate_minimum_fee(ttl)

      %{ttl: _ttl, type: :absolute} ->
        ttl_fee >=
          ttl
          |> Oracle.calculate_relative_ttl(block_height)
          |> Oracle.calculate_minimum_fee()
    end
  end

  @spec encode_to_list(OracleRegistrationTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %OracleRegistrationTx{
          ttl: oracle_ttl,
          query_format: query_format,
          response_format: response_format,
          query_fee: query_fee,
          vm_version: vm_version
        },
        %DataTx{senders: [sender], nonce: nonce, fee: fee, ttl: ttl}
      ) do
    ttl_type = Serialization.encode_ttl_type(oracle_ttl)

    [
      :binary.encode_unsigned(@version),
      Identifier.encode_to_binary(sender),
      :binary.encode_unsigned(nonce),
      query_format,
      response_format,
      query_fee,
      ttl_type,
      :binary.encode_unsigned(oracle_ttl.ttl),
      :binary.encode_unsigned(fee),
      :binary.encode_unsigned(ttl),
      :binary.encode_unsigned(vm_version)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_sender,
        nonce,
        query_format,
        response_format,
        query_fee,
        encoded_ttl_type,
        ttl_value,
        fee,
        ttl,
        vm_version
      ]) do
    ttl_type =
      encoded_ttl_type
      |> Serialization.decode_ttl_type()

    payload = %{
      query_format: query_format,
      response_format: response_format,
      ttl: %{ttl: :binary.decode_unsigned(ttl_value), type: ttl_type},
      query_fee: :binary.decode_unsigned(query_fee),
      vm_version: :binary.decode_unsigned(vm_version)
    }

    DataTx.init_binary(
      OracleRegistrationTx,
      payload,
      [encoded_sender],
      :binary.decode_unsigned(fee),
      :binary.decode_unsigned(nonce),
      :binary.decode_unsigned(ttl)
    )
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
