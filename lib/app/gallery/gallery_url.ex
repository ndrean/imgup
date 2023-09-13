defmodule App.Gallery.Url do
  @moduledoc """
  The schema of the table "urls": the list of urls per user per uuid.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias App.Accounts.User
  alias App.Gallery.Url
  @keys [:origin_url, :thumb_url, :resized_url, :key, :user_id, :ext, :uuid]

  schema "urls" do
    field :origin_url, :string
    field :thumb_url, :string
    field :resized_url, :string
    field :key, :string
    field :uuid, :binary_id
    field :ext, :string
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(%Url{} = url, attrs) do
    url
    |> cast(attrs, @keys)
    |> validate_required([:thumb_url, :resized_url, :user_id])

    # |> unique_constraint(:origin_url, name: :urls_origin_url_user_id_index)
  end

  # def thumb_changeset(%Url{} = url, attrs) do
  #   url
  #   |> cast(attrs, @keys)
  #   |> validate_required([:user_id, :uuid])
  # end
end
