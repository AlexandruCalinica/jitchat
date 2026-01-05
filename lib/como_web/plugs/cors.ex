defmodule ComoWeb.Plugs.CORS do
  @moduledoc """
  CORS plug for Tauri app and other allowed origins.
  """
  import Plug.Conn

  @allowed_origins [
    "tauri://localhost",
    "https://tauri.localhost",
    "http://localhost:1420",
    "http://localhost:4000"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    conn
    |> put_cors_headers(origin)
    |> handle_preflight()
  end

  defp put_cors_headers(conn, origin) when origin in @allowed_origins do
    conn
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "authorization, content-type")
    |> put_resp_header("access-control-allow-credentials", "true")
    |> put_resp_header("access-control-max-age", "86400")
  end

  defp put_cors_headers(conn, _origin), do: conn

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(204, "")
    |> halt()
  end

  defp handle_preflight(conn), do: conn
end
