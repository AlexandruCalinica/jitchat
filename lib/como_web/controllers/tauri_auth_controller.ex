defmodule ComoWeb.TauriAuthController do
  use ComoWeb, :controller

  alias Como.TauriAuth

  def login(conn, params) do
    redirect_uri = Map.get(params, "redirect_uri")
    state = Map.get(params, "state")

    cond do
      is_nil(redirect_uri) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "missing_redirect_uri", message: "redirect_uri is required"}})

      is_nil(conn.assigns[:current_user]) ->
        conn
        |> put_session(:tauri_redirect_uri, redirect_uri)
        |> put_session(:tauri_state, state)
        |> put_session(:user_return_to, ~p"/auth/tauri/callback")
        |> redirect(to: ~p"/signin")

      true ->
        handle_authenticated_login(conn, redirect_uri, state)
    end
  end

  def callback(conn, _params) do
    redirect_uri = get_session(conn, :tauri_redirect_uri)
    state = get_session(conn, :tauri_state)
    user = conn.assigns[:current_user]

    cond do
      is_nil(redirect_uri) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "missing_session", message: "No pending Tauri auth session"}})

      is_nil(user) ->
        conn
        |> redirect(to: ~p"/signin")

      true ->
        conn
        |> delete_session(:tauri_redirect_uri)
        |> delete_session(:tauri_state)
        |> handle_authenticated_login(redirect_uri, state)
    end
  end

  def token(conn, params) do
    code = Map.get(params, "code")
    redirect_uri = Map.get(params, "redirect_uri")

    cond do
      is_nil(code) ->
        error_response(conn, :bad_request, "missing_code", "code is required")

      is_nil(redirect_uri) ->
        error_response(conn, :bad_request, "missing_redirect_uri", "redirect_uri is required")

      true ->
        case TauriAuth.exchange_code_for_token(code, redirect_uri) do
          {:ok, token_string, user} ->
            conn
            |> put_status(:created)
            |> json(%{
              data: %{
                token: token_string,
                user: TauriAuth.user_to_map(user),
                expires_at: nil
              }
            })

          {:error, :invalid_code} ->
            error_response(conn, :bad_request, "invalid_code", "Auth code is invalid or expired")

          {:error, :invalid_redirect_uri} ->
            error_response(
              conn,
              :bad_request,
              "redirect_uri_mismatch",
              "Redirect URI does not match"
            )

          {:error, _} ->
            error_response(
              conn,
              :internal_server_error,
              "server_error",
              "Failed to exchange code"
            )
        end
    end
  end

  def me(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        error_response(conn, :unauthorized, "invalid_token", "Token is invalid or revoked")

      user ->
        conn
        |> json(%{data: TauriAuth.user_to_map(user)})
    end
  end

  def logout(conn, _params) do
    token = extract_token(conn)

    case TauriAuth.revoke_token(token) do
      {:ok, _} ->
        conn
        |> json(%{data: %{message: "Token revoked"}})

      {:error, :invalid_token} ->
        error_response(conn, :unauthorized, "invalid_token", "Token is invalid or revoked")

      {:error, _} ->
        error_response(conn, :internal_server_error, "server_error", "Failed to revoke token")
    end
  end

  defp handle_authenticated_login(conn, redirect_uri, state) do
    user = conn.assigns.current_user

    case TauriAuth.create_auth_code(user, redirect_uri, state) do
      {:ok, code} ->
        deep_link_url = build_redirect_url(redirect_uri, code, state)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, deep_link_redirect_html(deep_link_url))

      {:error, :invalid_redirect_uri} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "invalid_redirect_uri", message: "Invalid redirect URI scheme"}})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: %{code: "server_error", message: "Failed to create auth code"}})
    end
  end

  defp deep_link_redirect_html(deep_link_url) do
    escaped_url = Phoenix.HTML.html_escape(deep_link_url) |> Phoenix.HTML.safe_to_string()
    js_url = Jason.encode!(deep_link_url)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Redirecting to app...</title>
      <style>
        body { font-family: system-ui, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
        .container { text-align: center; padding: 2rem; }
        .btn { display: inline-block; margin-top: 1rem; padding: 0.75rem 1.5rem; background: #3182ce; color: white; text-decoration: none; border-radius: 0.5rem; }
        .btn:hover { background: #2c5282; }
        .debug { margin-top: 2rem; padding: 1rem; background: #eee; border-radius: 0.5rem; font-family: monospace; font-size: 0.75rem; word-break: break-all; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Opening app...</h1>
        <p>If the app doesn't open automatically, click the button below.</p>
        <a href="#{escaped_url}" class="btn">Open App</a>
        <div class="debug">Debug URL: #{escaped_url}</div>
      </div>
      <script>
        window.location.href = #{js_url};
      </script>
    </body>
    </html>
    """
  end

  defp build_redirect_url(redirect_uri, code, nil) do
    "#{redirect_uri}?code=#{code}"
  end

  defp build_redirect_url(redirect_uri, code, state) do
    "#{redirect_uri}?code=#{code}&state=#{URI.encode_www_form(state)}"
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      [token] -> token
      _ -> nil
    end
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
