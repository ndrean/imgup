defmodule App.Gallery.Url do
  @moduledoc """
  The schema of the table "urls". A record contains two URL, and a reference to the user_id.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "urls" do
    field :public_url, :string
    field :compressed_url, :string
    field :key, :string
    belongs_to :user, App.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(gallery, attrs) do
    gallery
    |> cast(attrs, [:public_url, :compressed_url, :key, :user_id])
    |> validate_required([:key, :public_url, :user_id])
  end
end
