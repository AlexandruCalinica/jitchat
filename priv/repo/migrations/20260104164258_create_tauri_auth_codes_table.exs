defmodule Como.Repo.Migrations.CreateTauriAuthCodesTable do
  use Ecto.Migration

  def up do
    create table(:tauri_auth_codes, primary_key: false) do
      add(:id, :string, primary_key: true, null: false)
      add(:code, :binary, null: false)
      add(:redirect_uri, :string, null: false)
      add(:state, :string)
      add(:user_id, :string, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:used, :boolean, default: false, null: false)

      timestamps(updated_at: false)
    end

    create(index(:tauri_auth_codes, [:code]))
    create(index(:tauri_auth_codes, [:expires_at]))
  end

  def down do
    drop(table(:tauri_auth_codes))
  end
end
