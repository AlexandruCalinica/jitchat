defmodule Como.TauriAuth do
  @moduledoc """
  Context for Tauri desktop app authentication.

  Handles the OAuth-like flow where users authenticate via browser
  and receive a token for the desktop app via deep link.
  """

  alias Como.Repo
  alias Como.TauriAuth.AuthCode
  alias Como.ApiTokens
  alias Como.Users.User

  @allowed_redirect_schemes ["jitchat"]

  def create_auth_code(%User{} = user, redirect_uri, state \\ nil) do
    with :ok <- validate_redirect_uri(redirect_uri) do
      {code_string, auth_code} = AuthCode.build(user, redirect_uri, state)

      case Repo.insert(auth_code) do
        {:ok, _} -> {:ok, code_string}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def exchange_code_for_token(code_string, redirect_uri) do
    with :ok <- validate_redirect_uri(redirect_uri),
         {:ok, query} <- AuthCode.verify_query(code_string, redirect_uri),
         %AuthCode{} = auth_code <- Repo.one(query),
         {:ok, user} <- get_user(auth_code.user_id),
         :ok <- mark_code_used(auth_code),
         {:ok, token_string, _api_token} <- create_app_token(user) do
      {:ok, token_string, user}
    else
      nil -> {:error, :invalid_code}
      :error -> {:error, :invalid_code}
      {:error, :invalid_redirect_uri} = err -> err
      {:error, :user_not_found} -> {:error, :invalid_code}
      {:error, _} = err -> err
    end
  end

  def get_user_by_token(token_string) do
    case ApiTokens.verify_api_token(token_string) do
      {:ok, user, _api_token} -> {:ok, user}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  def revoke_token(token_string) do
    case ApiTokens.verify_api_token(token_string) do
      {:ok, _user, api_token} ->
        ApiTokens.deactivate_api_token(api_token)

      {:error, _} ->
        {:error, :invalid_token}
    end
  end

  def cleanup_expired_codes do
    AuthCode.cleanup_expired_query()
    |> Repo.delete_all()
  end

  def user_to_map(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      username: extract_username(user.email),
      color: generate_user_color(user.id)
    }
  end

  defp validate_redirect_uri(redirect_uri) do
    case URI.parse(redirect_uri) do
      %URI{scheme: scheme} when scheme in @allowed_redirect_schemes ->
        :ok

      _ ->
        {:error, :invalid_redirect_uri}
    end
  end

  defp get_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp mark_code_used(auth_code) do
    {1, _} =
      auth_code
      |> AuthCode.mark_used_query()
      |> Repo.update_all([])

    :ok
  end

  defp create_app_token(user) do
    ApiTokens.create_api_token(
      user,
      "Tauri Desktop App",
      scopes: ["read", "write"],
      expires_in_days: nil,
      prefix: "app_"
    )
  end

  defp extract_username(email) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp extract_username(_), do: "user"

  @colors [
    "#F97066",
    "#F63D68",
    "#9C4221",
    "#ED8936",
    "#FDB022",
    "#ECC94B",
    "#86CB3C",
    "#38A169",
    "#3B7C0F",
    "#0BC5EA",
    "#2ED3B7",
    "#3182ce",
    "#004EEB",
    "#9E77ED",
    "#7839EE",
    "#D444F1",
    "#9F1AB1",
    "#D53F8C"
  ]

  defp generate_user_color(user_id) when is_binary(user_id) do
    hash = :erlang.phash2(user_id, length(@colors))
    Enum.at(@colors, hash)
  end

  defp generate_user_color(_), do: "#3182ce"
end
