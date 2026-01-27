defmodule Como.Repo.Migrations.AddRefIdToDocuments do
  use Ecto.Migration

  def up do
    alter table(:documents) do
      add :ref_id, :string
    end

    create index(:documents, [:ref_id])

    execute """
    UPDATE documents
    SET ref_id = refs_documents.ref_id
    FROM refs_documents
    WHERE documents.id = refs_documents.document_id
    """
  end

  def down do
    drop index(:documents, [:ref_id])

    alter table(:documents) do
      remove :ref_id
    end
  end
end
