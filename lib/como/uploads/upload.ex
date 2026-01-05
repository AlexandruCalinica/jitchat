defmodule Como.Uploads.Upload do
  @moduledoc """
  Schema for tracking uploaded files.

  Stores metadata about uploaded images/files including:
  - Original filename
  - Content type (MIME type)
  - File size in bytes
  - Image dimensions (width/height) when applicable
  - Storage path on disk
  - Associated channel and user
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :filename,
             :content_type,
             :size,
             :width,
             :height,
             :channel_id,
             :user_id,
             :inserted_at
           ]}
  @primary_key {:id, :string, autogenerate: false}
  schema "uploads" do
    field(:filename, :string)
    field(:content_type, :string)
    field(:size, :integer)
    field(:width, :integer)
    field(:height, :integer)
    field(:storage_path, :string)
    field(:channel_id, :string)
    field(:user_id, :string)

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          filename: String.t(),
          content_type: String.t(),
          size: integer(),
          width: integer() | nil,
          height: integer() | nil,
          storage_path: String.t(),
          channel_id: String.t(),
          user_id: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @allowed_content_types ~w(image/png image/jpeg image/gif image/webp image/heic image/heif)
  @max_file_size 10 * 1024 * 1024
  @max_dimension 4096

  def allowed_content_types, do: @allowed_content_types
  def max_file_size, do: @max_file_size
  def max_dimension, do: @max_dimension

  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [
      :filename,
      :content_type,
      :size,
      :width,
      :height,
      :storage_path,
      :channel_id,
      :user_id
    ])
    |> maybe_put_id()
    |> validate_required([:filename, :content_type, :size, :storage_path, :channel_id, :user_id])
    |> validate_content_type()
    |> validate_file_size()
    |> validate_dimensions()
  end

  defp maybe_put_id(%Ecto.Changeset{data: %{id: nil}} = changeset) do
    put_change(changeset, :id, Como.Utils.IdGenerator.generate_id_16("img"))
  end

  defp maybe_put_id(changeset), do: changeset

  defp validate_content_type(changeset) do
    validate_change(changeset, :content_type, fn :content_type, content_type ->
      if content_type in @allowed_content_types do
        []
      else
        [content_type: "must be an image (png, jpg, gif, webp, heic, heif)"]
      end
    end)
  end

  defp validate_file_size(changeset) do
    validate_change(changeset, :size, fn :size, size ->
      if size <= @max_file_size do
        []
      else
        [size: "exceeds maximum allowed (10MB)"]
      end
    end)
  end

  defp validate_dimensions(changeset) do
    changeset
    |> validate_number(:width, less_than_or_equal_to: @max_dimension)
    |> validate_number(:height, less_than_or_equal_to: @max_dimension)
  end
end
