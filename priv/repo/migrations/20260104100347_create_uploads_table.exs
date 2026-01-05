defmodule Como.Repo.Migrations.CreateUploadsTable do
  use Ecto.Migration

  def up do
    create table(:uploads, primary_key: false) do
      add(:id, :string, primary_key: true, null: false)
      add(:filename, :string, null: false)
      add(:content_type, :string, null: false)
      add(:size, :bigint, null: false)
      add(:width, :integer)
      add(:height, :integer)
      add(:storage_path, :string, null: false)
      add(:channel_id, :string, null: false)
      add(:user_id, :string, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:uploads, [:channel_id]))
    create(index(:uploads, [:user_id]))
  end

  def down do
    drop(table(:uploads))
  end
end
