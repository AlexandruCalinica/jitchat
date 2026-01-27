defmodule ComoWeb.SyncController do
  use ComoWeb, :controller
  import Phoenix.Sync.Controller
  import Ecto.Query

  alias Como.Channels.Channel
  alias Como.Documents.Document

  def channels(conn, params) do
    tenant_id = conn.assigns.current_user.tenant_id

    query = from c in Channel, where: c.tenant_id == ^tenant_id

    sync_render(conn, params, query)
  end

  def documents(conn, params) do
    tenant_id = conn.assigns.current_user.tenant_id

    query = from d in Document, where: d.tenant_id == ^tenant_id

    sync_render(conn, params, query)
  end
end
