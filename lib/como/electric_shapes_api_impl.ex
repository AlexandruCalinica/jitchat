defimpl Phoenix.Sync.Adapter.PlugApi, for: Electric.Shapes.Api do
  alias Electric.Shapes
  alias Phoenix.Sync.PredefinedShape
  alias Phoenix.Sync.Electric.ApiAdapter

  def predefined_shape(api, %PredefinedShape{} = shape) do
    ApiAdapter.new(api, shape)
  end

  def call(api, %{method: "GET"} = conn, params) do
    case Shapes.Api.validate(api, params) do
      {:ok, request} ->
        conn
        |> content_type()
        |> Plug.Conn.assign(:request, request)
        |> Shapes.Api.serve_shape_log(request)

      {:error, response} ->
        conn
        |> content_type()
        |> Shapes.Api.Response.send(response)
        |> Plug.Conn.halt()
    end
  end

  def call(api, %{method: "DELETE"} = conn, params) do
    case Shapes.Api.validate_for_delete(api, params) do
      {:ok, request} ->
        conn
        |> content_type()
        |> Plug.Conn.assign(:request, request)
        |> Shapes.Api.delete_shape(request)

      {:error, response} ->
        conn
        |> content_type()
        |> Shapes.Api.Response.send(response)
        |> Plug.Conn.halt()
    end
  end

  def call(_api, %{method: "OPTIONS"} = conn, _params) do
    Shapes.Api.options(conn)
  end

  def call(_api, conn, _params) do
    Plug.Conn.send_resp(conn, 405, "Method Not Allowed")
  end

  def response(api, _conn, params) do
    case Shapes.Api.validate(api, params) do
      {:ok, request} ->
        {
          request,
          Shapes.Api.serve_shape_log(request) |> Phoenix.Sync.Electric.consume_response_stream()
        }

      {:error, response} ->
        {nil, response}
    end
  end

  def send_response(_api, conn, {request, response}) do
    conn
    |> content_type()
    |> Plug.Conn.assign(:request, request)
    |> Plug.Conn.assign(:response, response)
    |> Shapes.Api.Response.send(response)
  end

  defp content_type(conn) do
    Plug.Conn.put_resp_content_type(conn, "application/json")
  end
end
