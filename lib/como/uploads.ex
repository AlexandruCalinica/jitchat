defmodule Como.Uploads do
  @moduledoc """
  The Uploads context for file upload operations.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Como.Repo
  alias Como.Uploads.Upload

  @uploads_dir "priv/static/uploads/images"
  @max_file_size 10 * 1024 * 1024

  def create_image_upload(%Plug.Upload{} = file, channel_id, user_id) do
    with :ok <- validate_file_type(file),
         :ok <- validate_file_size(file),
         {:ok, dimensions} <- get_image_dimensions(file.path),
         :ok <- validate_dimensions(dimensions),
         {:ok, storage_path, id} <- store_file(file),
         {:ok, upload} <-
           create_upload_record(file, storage_path, id, channel_id, user_id, dimensions) do
      {:ok, upload}
    end
  end

  def get_upload(id) do
    case Repo.get(Upload, id) do
      nil -> {:error, :not_found}
      upload -> {:ok, upload}
    end
  end

  def build_url(%Upload{} = upload, base_url) do
    extension = get_extension(upload.content_type)
    "#{base_url}/uploads/images/#{upload.id}#{extension}"
  end

  defp validate_file_type(%Plug.Upload{content_type: content_type}) do
    if content_type in Upload.allowed_content_types() do
      :ok
    else
      {:error, {:invalid_file_type, "File must be an image (png, jpg, gif, webp, heic, heif)"}}
    end
  end

  defp validate_file_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_file_size ->
        :ok

      {:ok, %{size: _size}} ->
        {:error, {:file_too_large, "File size exceeds maximum allowed (10MB)"}}

      {:error, reason} ->
        {:error, {:file_error, "Could not read file: #{inspect(reason)}"}}
    end
  end

  defp validate_dimensions({width, height}) do
    max = Upload.max_dimension()

    if width <= max and height <= max do
      :ok
    else
      {:error, {:dimensions_too_large, "Image dimensions exceed maximum allowed (#{max}x#{max})"}}
    end
  end

  defp validate_dimensions(nil), do: :ok

  defp get_image_dimensions(path) do
    case identify_image(path) do
      {:ok, dimensions} -> {:ok, dimensions}
      {:error, _} -> {:ok, nil}
    end
  end

  defp identify_image(path) do
    case System.cmd("identify", ["-format", "%w %h", path], stderr_to_stdout: true) do
      {output, 0} ->
        case String.trim(output) |> String.split(" ") do
          [width_str, height_str] ->
            case {Integer.parse(width_str), Integer.parse(height_str)} do
              {{width, _}, {height, _}} -> {:ok, {width, height}}
              _ -> {:error, :parse_error}
            end

          _ ->
            {:error, :parse_error}
        end

      {_error, _code} ->
        {:error, :identify_not_available}
    end
  end

  defp store_file(%Plug.Upload{path: temp_path, content_type: content_type}) do
    id = Como.Utils.IdGenerator.generate_id_16("img")
    extension = get_extension(content_type)
    filename = "#{id}#{extension}"

    upload_dir = uploads_dir()
    File.mkdir_p!(upload_dir)

    dest_path = Path.join(upload_dir, filename)

    case File.cp(temp_path, dest_path) do
      :ok -> {:ok, dest_path, id}
      {:error, reason} -> {:error, {:storage_error, "Failed to store file: #{inspect(reason)}"}}
    end
  end

  defp get_extension("image/png"), do: ".png"
  defp get_extension("image/jpeg"), do: ".jpg"
  defp get_extension("image/gif"), do: ".gif"
  defp get_extension("image/webp"), do: ".webp"
  defp get_extension("image/heic"), do: ".heic"
  defp get_extension("image/heif"), do: ".heif"
  defp get_extension(_), do: ""

  defp uploads_dir do
    Application.app_dir(:como, @uploads_dir)
  end

  defp create_upload_record(file, storage_path, id, channel_id, user_id, dimensions) do
    {width, height} = dimensions || {nil, nil}

    file_size =
      case File.stat(file.path) do
        {:ok, %{size: size}} -> size
        _ -> 0
      end

    attrs = %{
      id: id,
      filename: file.filename || "upload",
      content_type: file.content_type,
      size: file_size,
      width: width,
      height: height,
      storage_path: storage_path,
      channel_id: channel_id,
      user_id: user_id
    }

    %Upload{}
    |> Upload.changeset(attrs)
    |> Repo.insert()
  end
end
