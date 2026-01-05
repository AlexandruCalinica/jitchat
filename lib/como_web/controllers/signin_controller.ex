defmodule ComoWeb.AuthController do
  use ComoWeb, :controller
  alias Como.Users
  alias Como.Users.User

  def index(conn, _params) do
    conn
    |> render(:index)
  end

  def send_magic_link(conn, %{"email" => email}) do
    case Users.login_or_register_user(email) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Check your email for a magic link!")
        |> redirect(to: ~p"/signin")

      {:error, _errors} ->
        conn
        |> put_flash(:error, "Something went wrong. Please try again.")
        |> redirect(to: ~p"/signin")
    end
  end

  def signin_with_token(conn, %{"token" => token} = _params) do
    case Users.get_user_by_email_token(token, "magic_link") do
      %User{} = user ->
        {:ok, user} = Users.confirm_user(user)

        conn
        |> put_flash(:info, "Logged in successfully.")
        |> ComoWeb.UserAuth.login_user(user)

      _ ->
        conn
        |> put_flash(:error, "That link didn't seem to work. Please try again.")
        |> redirect(to: ~p"/signin")
    end
  end

  def signup_with_token(conn, %{"token" => token} = _params) do
    case Users.get_user_by_email_token(token, "magic_link") do
      %User{} = user ->
        {:ok, user} = Users.confirm_user(user)

        conn
        |> put_flash(:info, "Logged in successfully.")
        |> ComoWeb.UserAuth.signup_user(user)

      _ ->
        conn
        |> put_flash(:error, "That link didn't seem to work. Please try again.")
        |> redirect(to: ~p"/signin")
    end
  end
end
