defmodule App.Repo.Migrations.CreateThumbs do
  use Ecto.Migration

  def change do
    create table(:thumbs) do
      add :origin_url, :string
      add :compressed_url, :string
      add :uuid, :uuid
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    # create unique_index(:thumbs, [:public_url, :user_id], name: :thumbs_public_url_user_id_index)
  end
end
