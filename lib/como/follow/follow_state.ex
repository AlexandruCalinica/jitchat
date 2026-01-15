defmodule Como.Follow.FollowState do
  use GenServer
  require Logger

  @name __MODULE__
  @table :follow_user_state
  @ping_limit_table :follow_ping_limits
  @ping_limit 10
  @ping_window_ms 60_000
  @scroll_throttle_ms 50

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@ping_limit_table, [:set, :named_table, :public])
    {:ok, %{monitors: %{}}}
  end

  def register(user_id, username, color, socket_pid) do
    GenServer.call(@name, {:register, user_id, username, color, socket_pid})
  end

  def unregister(user_id) do
    GenServer.call(@name, {:unregister, user_id})
  end

  def get(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  def get_socket_pid(user_id) do
    case get(user_id) do
      {:ok, %{socket_pid: pid}} -> {:ok, pid}
      error -> error
    end
  end

  def update_doc(user_id, doc_id) do
    update_field(user_id, :current_doc_id, doc_id)
  end

  def set_following(follower_id, leader_id) do
    GenServer.call(@name, {:set_following, follower_id, leader_id})
  end

  def clear_following(follower_id) do
    GenServer.call(@name, {:clear_following, follower_id})
  end

  def add_follower(leader_id, follower_id) do
    GenServer.call(@name, {:add_follower, leader_id, follower_id})
  end

  def remove_follower(leader_id, follower_id) do
    GenServer.call(@name, {:remove_follower, leader_id, follower_id})
  end

  def get_followers(leader_id) do
    case get(leader_id) do
      {:ok, %{followers: followers}} -> {:ok, followers}
      error -> error
    end
  end

  def update_scroll(user_id, scroll_state) do
    now = System.system_time(:millisecond)

    case get(user_id) do
      {:ok, %{last_scroll: %{timestamp: last_ts}}} when now - last_ts < @scroll_throttle_ms ->
        {:error, :throttled}

      {:ok, _state} ->
        scroll_with_ts = Map.put(scroll_state, :timestamp, now)
        update_field(user_id, :last_scroll, scroll_with_ts)

      error ->
        error
    end
  end

  def check_ping_limit(user_id) do
    now = System.system_time(:millisecond)
    window_start = now - @ping_window_ms

    case :ets.lookup(@ping_limit_table, user_id) do
      [{^user_id, timestamps}] ->
        recent = Enum.filter(timestamps, &(&1 > window_start))

        if length(recent) >= @ping_limit do
          {:error, :rate_limited}
        else
          :ets.insert(@ping_limit_table, {user_id, [now | recent]})
          :ok
        end

      [] ->
        :ets.insert(@ping_limit_table, {user_id, [now]})
        :ok
    end
  end

  def list_online_users do
    :ets.tab2list(@table)
    |> Enum.map(fn {_user_id, state} -> state end)
  end

  @impl true
  def handle_call({:register, user_id, username, color, socket_pid}, _from, state) do
    ref = Process.monitor(socket_pid)

    user_state = %{
      user_id: user_id,
      username: username,
      color: color,
      current_doc_id: nil,
      followers: MapSet.new(),
      following: nil,
      last_scroll: nil,
      socket_pid: socket_pid
    }

    :ets.insert(@table, {user_id, user_state})
    monitors = Map.put(state.monitors, ref, user_id)

    Logger.info("FollowState: registered user #{user_id}")
    {:reply, :ok, %{state | monitors: monitors}}
  end

  @impl true
  def handle_call({:unregister, user_id}, _from, state) do
    cleanup_user(user_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_following, follower_id, leader_id}, _from, state) do
    result = update_field(follower_id, :following, leader_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:clear_following, follower_id}, _from, state) do
    result = update_field(follower_id, :following, nil)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:add_follower, leader_id, follower_id}, _from, state) do
    result =
      case get(leader_id) do
        {:ok, leader_state} ->
          new_followers = MapSet.put(leader_state.followers, follower_id)
          update_field(leader_id, :followers, new_followers)

        {:error, :not_found} ->
          :ets.insert(@table, {leader_id, %{followers: MapSet.new([follower_id])}})
          :ok
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_follower, leader_id, follower_id}, _from, state) do
    result =
      case get(leader_id) do
        {:ok, leader_state} ->
          new_followers = MapSet.delete(leader_state.followers, follower_id)
          update_field(leader_id, :followers, new_followers)

        error ->
          error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {user_id, monitors} ->
        Logger.info("FollowState: user #{user_id} disconnected, cleaning up")
        cleanup_user(user_id)
        {:noreply, %{state | monitors: monitors}}
    end
  end

  defp update_field(user_id, field, value) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, user_state}] ->
        updated = Map.put(user_state, field, value)
        :ets.insert(@table, {user_id, updated})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp cleanup_user(user_id) do
    case get(user_id) do
      {:ok, %{following: leader_id, followers: followers}} ->
        if leader_id, do: remove_follower(leader_id, user_id)

        Enum.each(followers, fn follower_id ->
          update_field(follower_id, :following, nil)
        end)

      _ ->
        :ok
    end

    :ets.delete(@table, user_id)
    :ets.delete(@ping_limit_table, user_id)
  end
end
