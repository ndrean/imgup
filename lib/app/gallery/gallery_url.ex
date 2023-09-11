defmodule App.Gallery.Url do
  @moduledoc """
  The schema of the table "urls". A record contains two URL, and a reference to the user_id.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias App.Gallery.Url
  @keys [:origin_url, :compressed_url, :key, :user_id, :ext, :uuid]

  schema "urls" do
    field :origin_url, :string
    field :compressed_url, :string
    field :key, :string
    field :uuid, :binary_id
    field :ext, :string
    belongs_to :user, App.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(%Url{} = url, attrs) do
    url
    |> cast(attrs, @keys)
    |> validate_required([:origin_url, :user_id])

    # |> unique_constraint(:origin_url, name: :urls_origin_url_user_id_index)
  end

  # def thumb_changeset(%Url{} = url, attrs) do
  #   url
  #   |> cast(attrs, @keys)
  #   |> validate_required([:user_id, :uuid])
  # end
end
