defmodule ComoWeb.AvatarController do
  use ComoWeb, :controller

  alias Como.Avatars
  alias Como.TauriAuth

  @size_map %{"small" => 64, "medium" => 128, "large" => 256}

  def create(conn, params) do
    user = conn.assigns.current_user

    case get_avatar_file(params) do
      {:ok, file} ->
        case Avatars.upload_avatar(user, file) do
          {:ok, updated_user} ->
            base_url = get_base_url(conn)

            conn
            |> put_status(:ok)
            |> json(%{
              data: %{
                avatar_url: Avatars.build_avatar_url(updated_user.id, base_url),
                sizes: Avatars.build_all_avatar_urls(updated_user.id, base_url)
              }
            })

          {:error, {:invalid_file_type, message}} ->
            error_response(conn, :bad_request, "invalid_file_type", message)

          {:error, {:file_too_large, message}} ->
            error_response(conn, :bad_request, "file_too_large", message)

          {:error, {:convert_failed, _, _}} ->
            error_response(
              conn,
              :unprocessable_entity,
              "processing_failed",
              "Image processing failed"
            )

          {:error, :imagemagick_not_found} ->
            error_response(
              conn,
              :internal_server_error,
              "server_error",
              "Image processor not available"
            )

          {:error, _} ->
            error_response(
              conn,
              :internal_server_error,
              "server_error",
              "Failed to upload avatar"
            )
        end

      {:error, :missing_file} ->
        error_response(conn, :bad_request, "missing_file", "No avatar file provided")
    end
  end

  def show(conn, %{"user_id" => user_id} = params) do
    size = parse_size(params["size"])

    case Avatars.get_avatar_path(user_id, size) do
      {:ok, path} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> put_resp_header("content-type", "image/jpeg")
        |> send_file(200, path)

      {:error, :not_found} ->
        redirect_to_fallback(conn, user_id, size)
    end
  end

  def delete(conn, _params) do
    user = conn.assigns.current_user

    case Avatars.delete_avatar(user) do
      {:ok, _user} ->
        json(conn, %{data: %{avatar_url: nil}})

      {:error, _} ->
        error_response(conn, :internal_server_error, "server_error", "Failed to delete avatar")
    end
  end

  defp get_avatar_file(%{"avatar" => %Plug.Upload{} = file}), do: {:ok, file}
  defp get_avatar_file(_), do: {:error, :missing_file}

  defp parse_size(nil), do: Avatars.default_size()
  defp parse_size(size_name), do: Map.get(@size_map, size_name, Avatars.default_size())

  defp redirect_to_fallback(conn, user_id, size) do
    case Avatars.get_user_with_avatar(user_id) do
      nil ->
        error_response(conn, :not_found, "user_not_found", "User not found")

      user ->
        user_data = TauriAuth.user_to_map(user)
        fallback_url = build_fallback_url(user_data.username, user_data.color, size)

        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> redirect(external: fallback_url)
    end
  end

  defp build_fallback_url(username, color, size) do
    initial = username |> String.first() |> String.upcase()
    bg = String.replace(color, "#", "")

    "https://ui-avatars.com/api/?" <>
      URI.encode_query(%{
        "name" => initial,
        "background" => bg,
        "color" => "fff",
        "size" => size,
        "bold" => "true"
      })
  end

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
end
