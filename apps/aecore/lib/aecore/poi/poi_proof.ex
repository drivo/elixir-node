defmodule Aecore.Poi.PoiProof do

  alias Aecore.Poi.PoiProof
  alias Aecore.Poi.PoiDB
  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Proof
  alias MerklePatriciaTree.DB.ExternalDB
  alias Aeutil.PatriciaMerkleTree

  @doc """
  This is the canonical root hash of an empty Patricia merkle tree
  """
  @canonical_root_hash <<69, 176, 207, 194, 32, 206, 236, 91, 124, 28, 98, 196, 212, 25, 61, 56,
                         228, 235, 164, 142, 136, 21, 114, 156, 231, 95, 156, 10, 176, 228, 193,
                         192>>

  @type t :: %PoiProof{
          root_hash: :empty | binary(),
          db: Map.t()
        }

  defstruct [
    root_hash: :empty,
    db: %{},
  ]

  def construct(%Trie{} = trie) do
    %PoiProof{
      root_hash: trie_root_hash(trie),
      db: %{}
    }
  end

  defp get_proof_construction_handles(%PoiProof{db: proof_db}) do
    PoiDB.prepare_for_requests(proof_db)
    %{
      get: fn _ -> :error end,
      put: &PoiDB.put/2
    }
  end

  defp get_proof_readonly_handles(%PoiProof{db: proof_db}) do
    %{
      get:
        fn key ->
          case Map.get(proof_db, key) do
            nil ->
              :not_found
            value ->
              {:ok, value}
          end
        end,
      put: fn _ -> :error end
    }
  end

  defp trie_root_hash(%Trie{} = trie) do
    case PatriciaMerkleTree.root_hash(trie) do
      @canonical_root_hash ->
        :empty
      hash ->
        hash
    end
  end

  defp poi_root_hash_to_trie_root_hash(%PoiProof{root_hash: :empty}) do
    @canonical_root_hash
  end

  defp poi_root_hash_to_trie_root_hash(%PoiProof{root_hash: root_hash}) do
    root_hash
  end

  defp get_proof_construction_trie(%PoiProof{} = poi_proof) do
    Trie.new(ExternalDB.init(get_proof_construction_handles(poi_proof)))
  end

  defp get_readonly_proof_trie(%PoiProof{} = poi_proof) do
    Trie.new(ExternalDB.init(get_proof_readonly_handles(poi_proof)))
  end

  defp invoke_proof_construction(%PoiProof{} = poi_proof, %Trie{} = trie, key) do
    proof_trie = get_proof_construction_trie(poi_proof)
    {value, _} = Proof.construct_proof({trie, key, proof_trie})
    new_proof_db = PoiDB.finilize()
    case value do
      nil ->
        {:error, :key_not_found}
      _ ->
        {:ok, value, new_proof_db}
    end
  end

  defp invoke_proof_verification(%PoiProof{} = poi_proof, key, value) do
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTrie.verify_proof(proof_trie, key, value)
  end

  @spec add_to_poi(PoiProof.t(), Trie.t(), Trie.key()) :: {:ok, Trie.value(), PoiProof.t()} | {:error, :wrong_root_hash | :key_not_found}
  def add_to_poi(%PoiProof{root_hash: root_hash} = poi_proof, %Trie{} = trie, key) do
    case trie_root_hash(trie) do
      ^root_hash ->
        case invoke_proof_construction(poi_proof, trie, key) do
          {:error, _} = err ->
            err
          {:ok, value, proof_db} ->
            {:ok, value, %PoiProof{poi_proof | db: proof_db}}
        end
      _ ->
        {:error, :wrong_root_hash}
    end
  end

  @spec verify_poi_entry(PoiProof.t(), Trie.key, Trie.value()) :: boolean()
  def verify_poi_entry(%PoiProof{} = poi_proof, key, value) do
    root_hash = poi_root_hash_to_trie_root_hash(poi_proof)
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTree.verify_proof(key, value, root_hash, proof_trie)
  end

  @spec lookup_in_poi(PoiProof.t(), Trie.key()) :: {:ok, value} | :error
  def lookup_in_poi(%PoiProof{} = poi_proof, key) do
    root_hash = poi_root_hash_to_trie_root_hash(poi_proof)
    proof_trie = get_readonly_proof_trie(poi_proof)
    PatriciaMerkleTree.lookup_proof(key, root_hash, proof_trie)
  end

end