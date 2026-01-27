defmodule Como.Repo.Migrations.UpdateChannelsTenantScoped do
  use Ecto.Migration

  def up do
    execute "DELETE FROM channels"

    alter table(:channels) do
      add :tenant_id, references(:tenants, type: :string, on_delete: :delete_all), null: false
    end

    create index(:channels, [:tenant_id])

    drop index(:documents, [:channel_id])

    alter table(:documents) do
      remove :channel_id
    end
  end

  def down do
    alter table(:documents) do
      add :channel_id, references(:channels, type: :string, on_delete: :delete_all)
    end

    create index(:documents, [:channel_id])

    drop index(:channels, [:tenant_id])

    alter table(:channels) do
      remove :tenant_id
    end
  end
end
