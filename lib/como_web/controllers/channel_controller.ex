defmodule ComoWeb.ChannelController do
  use ComoWeb, :controller

  alias Como.Channels

  def index(conn, _params) do
    user = conn.assigns.current_user
    channels = Channels.list_channels_for_tenant(user.tenant_id)

    json(conn, %{data: Enum.map(channels, &serialize_channel/1)})
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Channels.get_channel(id, user.tenant_id) do
      {:ok, channel} ->
        json(conn, %{data: serialize_channel(channel)})

      {:error, :not_found} ->
        error_response(conn, :not_found, "not_found", "Channel not found")

      {:error, :forbidden} ->
        error_response(conn, :forbidden, "forbidden", "Channel belongs to another tenant")
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    name = Map.get(params, "name")
    description = Map.get(params, "description")

    if is_nil(name) or String.trim(name) == "" do
      error_response(conn, :bad_request, "invalid_name", "Name is required")
    else
      attrs = %{name: name, description: description}

      case Channels.create_channel_with_document(user, attrs) do
        {:ok, channel} ->
          conn
          |> put_status(:created)
          |> json(%{data: serialize_channel(channel)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: %{code: "validation_error", message: format_errors(changeset)}})
      end
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    attrs =
      %{
        name: Map.get(params, "name"),
        description: Map.get(params, "description")
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    case Channels.update_channel(id, user.tenant_id, attrs) do
      {:ok, channel} ->
        json(conn, %{data: serialize_channel(channel)})

      {:error, :not_found} ->
        error_response(conn, :not_found, "not_found", "Channel not found")

      {:error, :forbidden} ->
        error_response(conn, :forbidden, "forbidden", "Channel belongs to another tenant")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "validation_error", message: format_errors(changeset)}})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Channels.delete_channel(id, user.tenant_id) do
      {:ok, _channel} ->
        json(conn, %{data: %{deleted: true}})

      {:error, :not_found} ->
        error_response(conn, :not_found, "not_found", "Channel not found")

      {:error, :forbidden} ->
        error_response(conn, :forbidden, "forbidden", "Channel belongs to another tenant")
    end
  end

  def create_document(conn, %{"channel_id" => channel_id} = params) do
    user = conn.assigns.current_user
    title = Map.get(params, "title")
    attrs = %{name: title}

    case Channels.create_document(channel_id, user, attrs) do
      {:ok, document} ->
        conn
        |> put_status(:created)
        |> json(%{data: serialize_document(document)})

      {:error, :not_found} ->
        error_response(conn, :not_found, "not_found", "Channel not found")

      {:error, :forbidden} ->
        error_response(conn, :forbidden, "forbidden", "Channel belongs to another tenant")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "validation_error", message: format_errors(changeset)}})
    end
  end

  def update_document(conn, %{"channel_id" => channel_id, "id" => document_id} = params) do
    user = conn.assigns.current_user
    title = Map.get(params, "title")

    case Channels.update_document(channel_id, document_id, user.tenant_id, %{name: title}) do
      {:ok, document} ->
        json(conn, %{data: serialize_document(document)})

      {:error, :not_found} ->
        error_response(conn, :not_found, "not_found", "Document not found")

      {:error, :forbidden} ->
        error_response(conn, :forbidden, "forbidden", "Channel belongs to another tenant")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "validation_error", message: format_errors(changeset)}})
    end
  end

  def delete_document(conn, %{"channel_id" => channel_id, "id" => document_id}) do
    user = conn.assigns.current_user

    case Channels.delete_document(channel_id, document_id, user.tenant_id) do
      {:ok, _document} ->
        json(conn, %{data: %{deleted: true}})

      {:error, :not_found} ->
        error_response(conn, :not_found, "not_found", "Document not found")

      {:error, :forbidden} ->
        error_response(conn, :forbidden, "forbidden", "Channel belongs to another tenant")
    end
  end

  defp serialize_channel(channel) do
    %{
      id: channel.id,
      name: channel.name,
      description: channel.description,
      documents: Enum.map(channel.documents || [], &serialize_document/1),
      created_at: format_datetime(channel.inserted_at),
      updated_at: format_datetime(channel.updated_at)
    }
  end

  defp serialize_document(document) do
    %{
      id: document.id,
      title: document.name,
      created_at: format_datetime(document.inserted_at),
      updated_at: format_datetime(document.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
