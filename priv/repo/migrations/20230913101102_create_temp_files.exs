defmodule App.Repo.Migrations.CreateTempFiles do
  use Ecto.Migration

  def change do
    create table(:temps) do
      add :origin_path, :string
      add :thumb_path, :string
      add :resized_path, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end
  end
end
