defmodule App.Gallery.GalleryTemp do
  @moduledoc """
  The list of temporary files saved on the server disk per user.
  """
  use Ecto.Schema
  alias App.Accounts.User

  schema "temps" do
    field :origin_path, :string
    field :thumb_path, :string
    field :resized_path, :string
    belongs_to :user, User

    timestamps()
  end
end
