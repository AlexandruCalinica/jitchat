defmodule Como.Documents.Document do
  @moduledoc """
  Defines the Document schema and related functions for document management.

  This module manages:
  * Document schema definition
  * Changeset validation
  * Document creation and updates
  * Account brief generation
  * Document metadata handling

  It provides the core schema and functions for managing documents
  in the system, including collaborative documents and account briefs.
  The module handles document validation, ID generation, and proper
  serialization of document data.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :body,
             :lexical_state,
             :tenant_id,
             :user_id,
             :icon,
             :color,
             :ref_id,
             :inserted_at,
             :updated_at
           ]}
  @primary_key {:id, :string, autogenerate: false}
  schema "documents" do
    field(:name, :string)
    field(:body, :string)
    field(:lexical_state, :string)
    field(:tenant_id, :string)
    field(:user_id, :string)
    field(:icon, :string)
    field(:color, :string)
    field(:ref_id, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :name,
      :body,
      :lexical_state,
      :tenant_id,
      :user_id,
      :icon,
      :color
    ])
    |> maybe_put_id()
    |> validate_required([:name, :tenant_id, :body, :user_id, :icon, :color])
  end

  def channel_document_changeset(document, attrs) do
    document
    |> cast(attrs, [:name, :tenant_id, :user_id, :body, :icon, :color, :ref_id])
    |> maybe_put_id()
    |> maybe_put_title()
    |> put_defaults()
    |> validate_required([:name, :tenant_id, :user_id, :ref_id])
  end

  defp put_defaults(changeset) do
    changeset
    |> put_default(:body, "")
    |> put_default(:icon, "file-02")
    |> put_default(:color, "#6b7280")
  end

  defp put_default(changeset, field, value) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, value)
      _ -> changeset
    end
  end

  defp maybe_put_title(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :name) do
      nil -> put_change(changeset, :name, generate_title())
      "" -> put_change(changeset, :name, generate_title())
      _ -> changeset
    end
  end

  defp generate_title do
    Calendar.strftime(DateTime.utc_now(), "%d %b %Y")
  end

  def update_changeset(document, attrs) do
    document
    |> cast(attrs, [:id, :name, :icon, :color, :lexical_state])
    |> validate_required([:id, :name, :icon, :color])
  end

  def new_account_brief(tenant_id, lead_id, body) do
    %{
      id: Como.Utils.IdGenerator.generate_id_16("doc"),
      tenant_id: tenant_id,
      user_id: "system",
      name: "Account Brief",
      body: body,
      icon: "check-01",
      color: "#1b1b1b",
      ref_id: lead_id
    }
  end

  defp maybe_put_id(%Ecto.Changeset{data: %{id: nil}} = changeset) do
    put_change(
      changeset,
      :id,
      Como.Utils.IdGenerator.generate_id_16("doc")
    )
  end

  defp maybe_put_id(changeset), do: changeset
end
