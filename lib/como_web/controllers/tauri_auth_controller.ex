defmodule ComoWeb.TauriAuthController do
  use ComoWeb, :controller

  alias Como.TauriAuth

  def login(conn, params) do
    redirect_uri = Map.get(params, "redirect_uri")
    state = Map.get(params, "state")
    prompt = Map.get(params, "prompt")
    current_user = conn.assigns[:current_user]

    cond do
      is_nil(redirect_uri) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "missing_redirect_uri", message: "redirect_uri is required"}})

      is_nil(current_user) ->
        conn
        |> put_session(:tauri_redirect_uri, redirect_uri)
        |> put_session(:tauri_state, state)
        |> put_session(:user_return_to, ~p"/auth/tauri/callback")
        |> redirect(to: ~p"/signin")

      prompt == "select_account" ->
        conn
        |> put_session(:tauri_redirect_uri, redirect_uri)
        |> put_session(:tauri_state, state)
        |> put_resp_content_type("text/html")
        |> send_resp(200, account_picker_html(conn, current_user))

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

  def choose(conn, %{"choice" => "continue"}) do
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
        |> put_session(:user_return_to, ~p"/auth/tauri/callback")
        |> redirect(to: ~p"/signin")

      true ->
        conn
        |> delete_session(:tauri_redirect_uri)
        |> delete_session(:tauri_state)
        |> handle_authenticated_login(redirect_uri, state)
    end
  end

  def choose(conn, %{"choice" => "different"}) do
    redirect_uri = get_session(conn, :tauri_redirect_uri)
    state = get_session(conn, :tauri_state)

    if is_nil(redirect_uri) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: %{code: "missing_session", message: "No pending Tauri auth session"}})
    else
      # Clear the user from this auth flow only (don't log out of web app entirely)
      # We configure_session(renew: true) to get a fresh session, but keep tauri params
      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> put_session(:tauri_redirect_uri, redirect_uri)
      |> put_session(:tauri_state, state)
      |> put_session(:user_return_to, ~p"/auth/tauri/callback")
      |> redirect(to: ~p"/signin")
    end
  end

  def choose(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{code: "invalid_choice", message: "choice must be 'continue' or 'different'"}
    })
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

  defp account_picker_html(_conn, user) do
    csrf_token = Plug.CSRFProtection.get_csrf_token()
    email = user.email
    initial = String.first(email) |> String.upcase()

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Choose an account</title>
      <style>
        body { font-family: system-ui, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
        .container { text-align: center; padding: 2rem; background: white; border-radius: 1rem; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 400px; width: 90%; }
        h1 { margin: 0 0 0.5rem 0; font-size: 1.5rem; color: #1a202c; }
        .subtitle { color: #718096; margin-bottom: 2rem; }
        .account { display: flex; align-items: center; gap: 1rem; padding: 1rem; background: #f7fafc; border-radius: 0.5rem; margin-bottom: 1.5rem; }
        .avatar { width: 48px; height: 48px; border-radius: 50%; background: #3182ce; color: white; display: flex; align-items: center; justify-content: center; font-size: 1.25rem; font-weight: 600; }
        .email { text-align: left; font-weight: 500; color: #2d3748; word-break: break-all; }
        .actions { display: flex; flex-direction: column; gap: 0.75rem; }
        .btn { display: block; width: 100%; padding: 0.75rem 1.5rem; border: none; border-radius: 0.5rem; font-size: 1rem; cursor: pointer; text-decoration: none; box-sizing: border-box; }
        .btn-primary { background: #3182ce; color: white; }
        .btn-primary:hover { background: #2c5282; }
        .btn-secondary { background: transparent; color: #3182ce; border: 1px solid #3182ce; }
        .btn-secondary:hover { background: #ebf8ff; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Choose an account</h1>
        <p class="subtitle">to continue to the app</p>
        
        <div class="account">
          <div class="avatar">#{initial}</div>
          <div class="email">#{Phoenix.HTML.html_escape(email) |> Phoenix.HTML.safe_to_string()}</div>
        </div>
        
        <div class="actions">
          <form action="/auth/tauri/choose" method="post">
            <input type="hidden" name="_csrf_token" value="#{csrf_token}" />
            <input type="hidden" name="choice" value="continue" />
            <button type="submit" class="btn btn-primary">Continue as #{Phoenix.HTML.html_escape(email) |> Phoenix.HTML.safe_to_string()}</button>
          </form>
          
          <form action="/auth/tauri/choose" method="post">
            <input type="hidden" name="_csrf_token" value="#{csrf_token}" />
            <input type="hidden" name="choice" value="different" />
            <button type="submit" class="btn btn-secondary">Use a different account</button>
          </form>
        </div>
      </div>
    </body>
    </html>
    """
  end
end
