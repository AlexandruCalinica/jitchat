defmodule Como.Tenants do
  @moduledoc """
  The Tenants context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Como.Repo
  alias Como.Tenants.Tenant

  ## Database getters

  def get_tenant_by_name(name) when is_binary(name) do
    case Repo.get_by(Tenant, name: name) do
      %Tenant{} = tenant -> {:ok, tenant}
      nil -> {:error, :not_found}
    end
  end

  def get_tenant_by_id(tenant_id) when is_binary(tenant_id) do
    case Repo.get_by(Tenant, id: tenant_id) do
      %Tenant{} = tenant -> {:ok, tenant}
      nil -> {:error, :not_found}
    end
  end

  ## Tenant updates

  @spec set_tenant_workspace_name(binary(), binary()) :: :ok | {:error, any()}
  def set_tenant_workspace_name(tenant_id, workspace_name)
      when is_binary(tenant_id) do
    with {:ok, tenant} <- get_tenant_by_id(tenant_id),
         {:ok, _updated_tenant} <-
           update_tenant(tenant, %{workspace_name: workspace_name}) do
      :ok
    else
      {:error, :not_found} -> {:error, :tenant_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec set_tenant_workspace_icon_key(binary(), binary()) ::
          :ok | {:error, any()}
  def set_tenant_workspace_icon_key(tenant_id, icon_key)
      when is_binary(tenant_id) do
    with {:ok, tenant} <- get_tenant_by_id(tenant_id),
         {:ok, _updated_tenant} <-
           update_tenant(tenant, %{workspace_icon_key: icon_key}) do
      :ok
    else
      {:error, :not_found} -> {:error, :tenant_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_tenant(tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_tenant} ->
        {:ok, updated_tenant}

      {:error, changeset} ->
        Logger.error("Failed to update tenant #{tenant.name}: #{inspect(changeset.errors)}")

        {:error, changeset}
    end
  end

  ## Tenant registration
  def create_tenant(name, domain) do
    case insert_tenant(name, domain) do
      {:ok, _tenant} = result ->
        result

      {:error, _changeset} = error ->
        error
    end
  end

  def get_or_create_tenant(tenant_name, domain) do
    case get_tenant_by_name(tenant_name) do
      {:error, :not_found} ->
        case create_tenant(tenant_name, domain) do
          {:ok, tenant} -> {:ok, tenant.id}
          error -> error
        end

      {:ok, tenant} ->
        {:ok, tenant.id}
    end
  end

  ## Private functions

  defp insert_tenant(name, domain) do
    %Tenant{}
    |> Tenant.changeset(%{name: name, domain: domain})
    |> Repo.insert()
  end

  def get_all_tenants do
    Repo.all(Tenant)
    |> Enum.map(fn tenant ->
      %{
        id: tenant.id,
        workspace_name: tenant.workspace_name,
        name: tenant.name,
        workspace_icon_key: tenant.workspace_icon_key
      }
    end)
    |> Enum.sort_by(& &1.workspace_name)
  end
end
