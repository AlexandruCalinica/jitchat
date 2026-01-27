defmodule Como.Avatars.ImageProcessor do
  @moduledoc """
  Image processing for avatars using Vix/libvips via the Image library.
  """

  require Logger

  @spec process(Path.t(), Path.t(), pos_integer()) :: :ok | {:error, term()}
  def process(input_path, output_path, size) when is_integer(size) and size > 0 do
    with {:ok, thumb} <- Image.thumbnail(input_path, size, crop: :center),
         {:ok, _} <- Image.write(thumb, output_path, quality: 85, strip_metadata: true) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Image processing failed: #{inspect(reason)}")
        {:error, {:processing_failed, reason}}
    end
  end

  @spec process_all_sizes(Path.t(), Path.t(), [pos_integer()]) ::
          {:ok, %{pos_integer() => Path.t()}} | {:error, term()}
  def process_all_sizes(input_path, output_dir, sizes) do
    File.mkdir_p!(output_dir)

    Enum.reduce_while(sizes, {:ok, %{}}, fn size, {:ok, acc} ->
      output_path = Path.join(output_dir, "#{size}.jpg")

      case process(input_path, output_path, size) do
        :ok -> {:cont, {:ok, Map.put(acc, size, output_path)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @spec available?() :: boolean()
  def available? do
    match?({:ok, _}, Image.new(1, 1))
  end
end
