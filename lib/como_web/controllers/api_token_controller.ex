defmodule ComoWeb.ApiTokenController do
  use ComoWeb, :controller

  alias Como.ApiTokens

  def create(conn, params) do
    user = conn.assigns.current_user
    name = Map.get(params, "name", "API Token")
    scopes = Map.get(params, "scopes", ["read"])
    expires_in_days = Map.get(params, "expires_in_days", 365)

    case ApiTokens.create_api_token(user, name, scopes: scopes, expires_in_days: expires_in_days) do
      {:ok, token_string, api_token} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            id: api_token.id,
            token: token_string,
            name: api_token.name,
            scopes: api_token.scopes,
            expires_at: api_token.expires_at |> DateTime.to_iso8601(),
            created_at: api_token.inserted_at |> DateTime.to_iso8601()
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "validation_error", message: format_errors(changeset)}})
    end
  end

  def index(conn, params) do
    user = conn.assigns.current_user
    active_only = Map.get(params, "active_only", "false") == "true"

    tokens = ApiTokens.list_user_api_tokens(user, active_only: active_only)

    conn
    |> json(%{
      data:
        Enum.map(tokens, fn token ->
          %{
            id: token.id,
            name: token.name,
            scopes: token.scopes,
            active: token.active,
            last_used_at: format_datetime(token.last_used_at),
            expires_at: format_datetime(token.expires_at),
            created_at: format_datetime(token.inserted_at)
          }
        end)
    })
  end

  def delete(conn, %{"id" => token_id}) do
    user = conn.assigns.current_user

    case ApiTokens.deactivate_user_api_token(user, token_id) do
      {:ok, _token} ->
        conn
        |> put_status(:ok)
        |> json(%{data: %{message: "Token deactivated"}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "not_found", message: "Token not found"}})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: %{code: "server_error", message: "Failed to deactivate token"}})
    end
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

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
