defmodule Como.Avatars do
  @moduledoc false

  require Logger

  alias Como.Repo
  alias Como.Users.User
  alias Como.Avatars.ImageProcessor

  @avatars_dir "priv/static/avatars"
  @sizes [64, 128, 256]
  @default_size 256
  @max_file_size 5 * 1024 * 1024
  @allowed_types ~w(image/jpeg image/png image/webp)

  def upload_avatar(%User{} = user, %Plug.Upload{} = file) do
    with :ok <- validate_file_type(file),
         :ok <- validate_file_size(file),
         {:ok, _paths} <- process_and_store(user.id, file.path),
         {:ok, user} <- update_user_avatar(user) do
      {:ok, user}
    end
  end

  def delete_avatar(%User{} = user) do
    user_dir = avatar_dir(user.id)

    if File.exists?(user_dir) do
      File.rm_rf!(user_dir)
    end

    user
    |> Ecto.Changeset.change(avatar_url: nil)
    |> Repo.update()
  end

  def get_avatar_path(user_id, size \\ @default_size) when size in @sizes do
    path = Path.join([avatars_base_dir(), user_id, "#{size}.jpg"])

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :not_found}
    end
  end

  def build_avatar_url(user_id, base_url, size \\ @default_size) do
    "#{base_url}/avatars/#{user_id}/#{size}.jpg"
  end

  def build_all_avatar_urls(user_id, base_url) do
    %{
      small: build_avatar_url(user_id, base_url, 64),
      medium: build_avatar_url(user_id, base_url, 128),
      large: build_avatar_url(user_id, base_url, 256)
    }
  end

  def get_user_with_avatar(user_id) do
    Repo.get(User, user_id)
  end

  def sizes, do: @sizes
  def default_size, do: @default_size

  defp validate_file_type(%Plug.Upload{content_type: content_type}) do
    if content_type in @allowed_types do
      :ok
    else
      {:error, {:invalid_file_type, "File must be JPEG, PNG, or WebP"}}
    end
  end

  defp validate_file_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_file_size ->
        :ok

      {:ok, %{size: _}} ->
        {:error, {:file_too_large, "File exceeds 5MB limit"}}

      {:error, reason} ->
        {:error, {:file_error, "Could not read file: #{inspect(reason)}"}}
    end
  end

  defp process_and_store(user_id, input_path) do
    output_dir = avatar_dir(user_id)

    if File.exists?(output_dir) do
      File.rm_rf!(output_dir)
    end

    ImageProcessor.process_all_sizes(input_path, output_dir, @sizes)
  end

  defp update_user_avatar(%User{id: user_id} = user) do
    avatar_path = "avatars/#{user_id}/#{@default_size}.jpg"

    user
    |> Ecto.Changeset.change(avatar_url: avatar_path)
    |> Repo.update()
  end

  defp avatar_dir(user_id) do
    Path.join(avatars_base_dir(), user_id)
  end

  defp avatars_base_dir do
    Application.app_dir(:como, @avatars_dir)
  end
end
