defmodule ComoWeb.UserSocket do
  @moduledoc """
  Phoenix Socket for WebSocket connections.

  Handles authentication via API tokens or session tokens and assigns
  user information to the socket for use by channels.
  """

  require Logger
  use Phoenix.Socket

  alias Como.ApiTokens
  alias Como.Users
  alias Como.Users.ColorManager

  ## Channels

  channel "documents:*", ComoWeb.Channels.DocumentsChannel
  channel "events:*", ComoWeb.Channels.EventsChannel
  channel "follow:*", ComoWeb.Channels.FollowChannel

  @doc """
  Authenticates the socket connection using a token.

  Supports both API tokens (Bearer format) and session tokens.
  On success, assigns user_id, username, color, and user to the socket.
  """
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case authenticate_token(token) do
      {:ok, user} ->
        {:ok, color} = ColorManager.assign_color(user.id)
        username = extract_username(user.email)

        socket =
          socket
          |> assign(:user_id, user.id)
          |> assign(:user, user)
          |> assign(:username, username)
          |> assign(:color, color)
          |> assign(:tenant_id, user.tenant_id)

        Logger.debug(
          "Socket connected for user #{user.id} (#{username}) in tenant #{user.tenant_id}"
        )

        {:ok, socket}

      {:error, reason} ->
        Logger.warning("Socket connection failed: #{reason}")
        :error
    end
  end

  # Allow unauthenticated connections for backward compatibility with documents channel
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @doc """
  Returns a unique socket ID for the user, enabling targeted disconnects.
  """
  @impl true
  def id(socket) do
    case socket.assigns[:user_id] do
      nil -> nil
      user_id -> "user_socket:#{user_id}"
    end
  end

  defp authenticate_token(token) do
    case try_api_token(token) do
      {:ok, user} -> {:ok, user}
      :not_api_token -> try_session_token(token)
    end
  end

  defp try_api_token(token) do
    case ApiTokens.verify_api_token(token) do
      {:ok, user, _api_token} -> {:ok, user}
      {:error, :invalid_token} -> :not_api_token
    end
  end

  defp try_session_token(token) do
    case Users.get_user_by_session_token(token) do
      %Como.Users.User{} = user -> {:ok, user}
      nil -> {:error, :invalid_session_token}
    end
  end

  defp extract_username(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.capitalize()
  end

  defp extract_username(_), do: "Anonymous"
end
