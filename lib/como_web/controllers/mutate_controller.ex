defmodule ComoWeb.MutateController do
  use ComoWeb, :controller

  alias Phoenix.Sync.Writer
  alias Como.Repo
  alias Como.Channels.Channel
  alias Como.Documents.Document

  def mutate(conn, %{"transaction" => mutations}) do
    user = conn.assigns.current_user
    tenant_id = user.tenant_id
    user_id = user.id

    create_default_document = fn multi, changeset, _context ->
      channel_id = Ecto.Changeset.get_field(changeset, :id)

      doc_changeset =
        Document.channel_document_changeset(%Document{}, %{
          "name" => "Untitled",
          "tenant_id" => tenant_id,
          "user_id" => user_id,
          "ref_id" => channel_id
        })

      Ecto.Multi.insert(multi, {:default_doc, channel_id}, doc_changeset)
    end

    {:ok, txid, _changes} =
      Writer.new()
      |> Writer.allow(Channel,
        validate: fn struct, attrs ->
          attrs = Map.merge(attrs, %{"tenant_id" => tenant_id, "user_id" => user_id})
          Channel.changeset(struct, attrs)
        end,
        insert: [post_apply: create_default_document]
      )
      |> Writer.allow(Document,
        validate: fn struct, attrs ->
          attrs = Map.merge(attrs, %{"tenant_id" => tenant_id, "user_id" => user_id})
          Document.channel_document_changeset(struct, attrs)
        end
      )
      |> Writer.ingest(mutations, format: Writer.Format.TanstackDB)
      |> Writer.transaction(Repo)

    json(conn, %{txid: txid})
  end
end
