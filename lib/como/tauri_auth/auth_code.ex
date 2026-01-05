defmodule Como.TauriAuth.AuthCode do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :string, autogenerate: false}
  schema "tauri_auth_codes" do
    field(:code, :binary)
    field(:redirect_uri, :string)
    field(:state, :string)
    field(:user_id, :string)
    field(:expires_at, :utc_datetime)
    field(:used, :boolean, default: false)

    timestamps(updated_at: false)
  end

  @code_validity_seconds 300
  @rand_size 32

  def build(user, redirect_uri, state) do
    code = :crypto.strong_rand_bytes(@rand_size)
    hashed_code = :crypto.hash(:sha256, code)
    encoded_code = Base.url_encode64(code, padding: false)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@code_validity_seconds, :second)
      |> DateTime.truncate(:second)

    auth_code = %__MODULE__{
      id: Como.Utils.IdGenerator.generate_id_16("authcode"),
      code: hashed_code,
      redirect_uri: redirect_uri,
      state: state,
      user_id: user.id,
      expires_at: expires_at,
      used: false
    }

    {encoded_code, auth_code}
  end

  def verify_query(code_string, redirect_uri) do
    case Base.url_decode64(code_string, padding: false) do
      {:ok, raw_code} ->
        hashed_code = :crypto.hash(:sha256, raw_code)
        now = DateTime.utc_now()

        query =
          from(c in __MODULE__,
            where:
              c.code == ^hashed_code and
                c.redirect_uri == ^redirect_uri and
                c.used == false and
                c.expires_at > ^now,
            select: c
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  def mark_used_query(auth_code) do
    from(c in __MODULE__,
      where: c.id == ^auth_code.id,
      update: [set: [used: true]]
    )
  end

  def cleanup_expired_query do
    now = DateTime.utc_now()

    from(c in __MODULE__,
      where: c.expires_at < ^now or c.used == true
    )
  end
end
