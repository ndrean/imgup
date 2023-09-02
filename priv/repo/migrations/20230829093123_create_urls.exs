defmodule App.Repo.Migrations.CreateUrls do
  use Ecto.Migration

  def change do
    create table(:urls) do
      add :public_url, :string
      add :compressed_url, :string
      add :key, :string
      add :ext, :string
      add :user_id, references(:users)

      timestamps()
    end

    create unique_index(:urls, [:public_url, :user_id], name: :urls_public_url_user_id_index)
  end
end
