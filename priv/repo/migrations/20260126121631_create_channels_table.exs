defmodule Como.Repo.Migrations.CreateChannelsTable do
  use Ecto.Migration

  def up do
    create table(:channels, primary_key: false) do
      add :id, :string, primary_key: true, null: false
      add :name, :string, null: false
      add :description, :text
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:channels, [:user_id])

    alter table(:documents) do
      add :channel_id, references(:channels, type: :string, on_delete: :delete_all)
    end

    create index(:documents, [:channel_id])
  end

  def down do
    drop index(:documents, [:channel_id])

    alter table(:documents) do
      remove :channel_id
    end

    drop index(:channels, [:user_id])
    drop table(:channels)
  end
end
