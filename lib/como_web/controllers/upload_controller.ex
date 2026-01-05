defmodule ComoWeb.UploadController do
  use ComoWeb, :controller

  alias Como.Uploads

  def create(conn, params) do
    with {:ok, file} <- get_file(params),
         {:ok, channel_id} <- get_channel_id(params),
         user <- conn.assigns.current_user,
         {:ok, upload} <- Uploads.create_image_upload(file, channel_id, user.id) do
      base_url = get_base_url(conn)
      url = Uploads.build_url(upload, base_url)

      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          id: upload.id,
          url: url,
          filename: upload.filename,
          content_type: upload.content_type,
          size: upload.size,
          width: upload.width,
          height: upload.height,
          uploaded_by: user.email |> String.split("@") |> List.first(),
          uploaded_at: upload.inserted_at |> DateTime.to_iso8601()
        }
      })
    else
      {:error, :missing_file} ->
        error_response(conn, :bad_request, "missing_file", "No file provided in request")

      {:error, :missing_channel_id} ->
        error_response(conn, :bad_request, "missing_channel_id", "channel_id field not provided")

      {:error, {:invalid_file_type, message}} ->
        error_response(conn, :bad_request, "invalid_file_type", message)

      {:error, {:file_too_large, message}} ->
        error_response(conn, 413, "file_too_large", message)

      {:error, {:dimensions_too_large, message}} ->
        error_response(conn, :bad_request, "dimensions_too_large", message)

      {:error, {:storage_error, message}} ->
        error_response(conn, :internal_server_error, "server_error", message)

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        error_response(conn, :bad_request, "validation_error", format_changeset_errors(changeset))

      _error ->
        error_response(conn, :internal_server_error, "server_error", "Internal server error")
    end
  end

  defp get_file(%{"file" => %Plug.Upload{} = file}), do: {:ok, file}
  defp get_file(_), do: {:error, :missing_file}

  defp get_channel_id(%{"channel_id" => channel_id})
       when is_binary(channel_id) and channel_id != "" do
    {:ok, channel_id}
  end

  defp get_channel_id(_), do: {:error, :missing_channel_id}

  defp get_base_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    port_suffix = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    "#{scheme}://#{conn.host}#{port_suffix}"
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
