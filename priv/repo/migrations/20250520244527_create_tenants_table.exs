defmodule Como.Repo.Migrations.CreateTenantsTable do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :citext, null: false
      add :domain, :string, null: false
      add :workspace_name, :string
      add :workspace_icon_key, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:name])
  end
end
