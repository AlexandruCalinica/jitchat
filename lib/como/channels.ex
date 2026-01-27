defmodule Como.Channels do
  @moduledoc false

  import Ecto.Query

  alias Como.Repo
  alias Como.Channels.Channel
  alias Como.Documents.Document
  alias Como.Documents.RefDocument

  def list_channels_for_tenant(tenant_id) do
    Channel
    |> where([c], c.tenant_id == ^tenant_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
    |> Enum.map(&load_documents/1)
  end

  def get_channel(id, tenant_id) do
    Channel
    |> where([c], c.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      %Channel{tenant_id: ^tenant_id} = channel -> {:ok, load_documents(channel)}
      %Channel{} -> {:error, :forbidden}
    end
  end

  def create_channel(user, attrs) do
    %Channel{}
    |> Channel.changeset(Map.merge(attrs, %{user_id: user.id, tenant_id: user.tenant_id}))
    |> Repo.insert()
    |> case do
      {:ok, channel} -> {:ok, load_documents(channel)}
      error -> error
    end
  end

  def create_channel_with_document(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:channel, fn _ ->
      Channel.changeset(
        %Channel{},
        Map.merge(attrs, %{user_id: user.id, tenant_id: user.tenant_id})
      )
    end)
    |> Ecto.Multi.insert(:document, fn %{channel: _channel} ->
      Document.channel_document_changeset(%Document{}, %{
        name: "Today",
        user_id: user.id,
        tenant_id: user.tenant_id
      })
    end)
    |> Ecto.Multi.insert(:ref_document, fn %{channel: channel, document: document} ->
      RefDocument.changeset(%RefDocument{}, %{
        ref_id: channel.id,
        document_id: document.id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} ->
        {:ok, load_documents(channel)}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def update_channel(channel_id, tenant_id, attrs) do
    with {:ok, channel} <- get_channel(channel_id, tenant_id) do
      channel
      |> Ecto.Changeset.change(Map.take(attrs, [:name, :description]))
      |> Repo.update()
      |> case do
        {:ok, channel} -> {:ok, load_documents(channel)}
        error -> error
      end
    end
  end

  def delete_channel(channel_id, tenant_id) do
    with {:ok, channel} <- get_channel(channel_id, tenant_id) do
      document_ids =
        from(rd in RefDocument, where: rd.ref_id == ^channel_id, select: rd.document_id)
        |> Repo.all()

      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :ref_documents,
        from(rd in RefDocument, where: rd.ref_id == ^channel_id)
      )
      |> Ecto.Multi.delete_all(:documents, from(d in Document, where: d.id in ^document_ids))
      |> Ecto.Multi.delete(:channel, channel)
      |> Repo.transaction()
      |> case do
        {:ok, _} -> {:ok, channel}
        {:error, _op, error, _changes} -> {:error, error}
      end
    end
  end

  def create_document(channel_id, user, attrs) do
    with {:ok, channel} <- get_channel(channel_id, user.tenant_id) do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:document, fn _ ->
        Document.channel_document_changeset(
          %Document{},
          Map.merge(attrs, %{
            user_id: user.id,
            tenant_id: user.tenant_id
          })
        )
      end)
      |> Ecto.Multi.insert(:ref_document, fn %{document: document} ->
        RefDocument.changeset(%RefDocument{}, %{
          ref_id: channel.id,
          document_id: document.id
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{document: document}} -> {:ok, document}
        {:error, _op, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  def update_document(channel_id, document_id, tenant_id, attrs) do
    with {:ok, _channel} <- get_channel(channel_id, tenant_id),
         {:ok, document} <- get_document_in_channel(document_id, channel_id) do
      document
      |> Ecto.Changeset.change(name: attrs[:name] || attrs["title"])
      |> Repo.update()
    end
  end

  def delete_document(channel_id, document_id, tenant_id) do
    with {:ok, _channel} <- get_channel(channel_id, tenant_id),
         {:ok, document} <- get_document_in_channel(document_id, channel_id) do
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :ref_documents,
        from(rd in RefDocument,
          where: rd.document_id == ^document_id and rd.ref_id == ^channel_id
        )
      )
      |> Ecto.Multi.delete(:document, document)
      |> Repo.transaction()
      |> case do
        {:ok, %{document: document}} -> {:ok, document}
        {:error, _op, error, _changes} -> {:error, error}
      end
    end
  end

  defp get_document_in_channel(document_id, channel_id) do
    query =
      from d in Document,
        join: rd in RefDocument,
        on: rd.document_id == d.id,
        where: d.id == ^document_id and rd.ref_id == ^channel_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      document -> {:ok, document}
    end
  end

  defp load_documents(%Channel{} = channel) do
    documents =
      from(d in Document,
        join: rd in RefDocument,
        on: rd.document_id == d.id,
        where: rd.ref_id == ^channel.id,
        order_by: [desc: d.inserted_at]
      )
      |> Repo.all()

    Map.put(channel, :documents, documents)
  end
end
