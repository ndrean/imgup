defmodule App.Repo.Migrations.CreateUrls do
  use Ecto.Migration

  def change do
    create table(:urls) do
      add :origin_url, :string
      add :compressed_url, :string
      add :key, :string
      add :uuid, :uuid
      add :ext, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    # create unique_index(:urls, [:origin_url, :user_id], name: :urls_origin_url_user_id_index)
  end
end
