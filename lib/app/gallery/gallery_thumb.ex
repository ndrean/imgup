defmodule App.Gallery.Thumb do
  @moduledoc """
  The schema of the table "urls". A record contains two URL, and a reference to the user_id.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias App.Gallery.Thumb
  @keys [:origin_url, :compressed_url, :user_id, :uuid]

  schema "thumbs" do
    field :origin_url, :string
    field :compressed_url, :string
    field :uuid, :binary_id
    belongs_to :user, App.Accounts.User

    timestamps()
  end

  @doc false

  def changeset(%Thumb{} = thumb, attrs) do
    thumb
    |> cast(attrs, @keys)
    |> validate_required([:user_id, :uuid])
  end
end
