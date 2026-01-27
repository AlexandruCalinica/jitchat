defmodule Como.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  alias Como.Users.User
  alias Como.Tenants.Tenant

  @derive {Jason.Encoder, only: [:id, :name, :description, :tenant_id, :inserted_at, :updated_at]}
  @primary_key {:id, :string, autogenerate: false}

  schema "channels" do
    field :name, :string
    field :description, :string

    belongs_to :user, User, type: :string
    belongs_to :tenant, Tenant, type: :string

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :description, :user_id, :tenant_id])
    |> maybe_put_id()
    |> validate_required([:name, :user_id, :tenant_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
  end

  defp maybe_put_id(%Ecto.Changeset{data: %{id: nil}} = changeset) do
    put_change(changeset, :id, Como.Utils.IdGenerator.generate_id_16("chan"))
  end

  defp maybe_put_id(changeset), do: changeset
end
