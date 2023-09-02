defmodule App.Gallery.Url do
  @moduledoc """
  The schema of the table "urls". A record contains two URL, and a reference to the user_id.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias App.Gallery.Url

  schema "urls" do
    field :public_url, :string
    field :compressed_url, :string
    field :key, :string
    field :ext, :string
    belongs_to :user, App.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(attrs) do
    %Url{}
    |> cast(attrs, [:public_url, :compressed_url, :key, :ext, :user_id])
    |> validate_required([:key, :public_url, :ext, :user_id])
    |> unique_constraint(:public_url, name: :urls_public_url_user_id_index)
  end
end
