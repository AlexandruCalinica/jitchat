defmodule Como.Follow do
  alias Como.Follow.FollowState

  def register_user(user_id, username, color, socket_pid) do
    FollowState.register(user_id, username, color, socket_pid)
  end

  def unregister_user(user_id) do
    FollowState.unregister(user_id)
  end

  def get_user_state(user_id) do
    FollowState.get(user_id)
  end

  def get_socket_pid(user_id) do
    FollowState.get_socket_pid(user_id)
  end

  def update_current_doc(user_id, doc_id) do
    FollowState.update_doc(user_id, doc_id)
  end

  def start_following(follower_id, leader_id) when follower_id == leader_id do
    {:error, :cannot_follow_self}
  end

  def start_following(follower_id, leader_id) do
    with {:ok, follower_state} <- FollowState.get(follower_id),
         {:ok, _leader_state} <- FollowState.get(leader_id) do
      if follower_state.following do
        stop_following(follower_id)
      end

      :ok = FollowState.set_following(follower_id, leader_id)
      :ok = FollowState.add_follower(leader_id, follower_id)

      {:ok, leader_id}
    end
  end

  def set_following(follower_id, leader_id) do
    case FollowState.get(follower_id) do
      {:ok, %{following: current_leader}} when not is_nil(current_leader) ->
        stop_following(follower_id)
        do_set_following(follower_id, leader_id)

      {:ok, _} ->
        do_set_following(follower_id, leader_id)

      {:error, :not_found} ->
        FollowState.add_follower(leader_id, follower_id)
        :ok
    end
  end

  defp do_set_following(follower_id, leader_id) do
    FollowState.set_following(follower_id, leader_id)
    FollowState.add_follower(leader_id, follower_id)
    :ok
  end

  def stop_following(follower_id) do
    case FollowState.get(follower_id) do
      {:ok, %{following: nil}} ->
        {:ok, :not_following}

      {:ok, %{following: leader_id}} ->
        :ok = FollowState.clear_following(follower_id)
        FollowState.remove_follower(leader_id, follower_id)
        {:ok, leader_id}

      error ->
        error
    end
  end

  def get_followers(user_id) do
    FollowState.get_followers(user_id)
  end

  def update_scroll(user_id, doc_id, scroll_top, scroll_left \\ 0, viewport_height \\ nil) do
    scroll_state = %{
      doc_id: doc_id,
      scroll_top: scroll_top,
      scroll_left: scroll_left,
      viewport_height: viewport_height
    }

    FollowState.update_scroll(user_id, scroll_state)
  end

  def check_ping_rate_limit(user_id) do
    FollowState.check_ping_limit(user_id)
  end

  def list_online_users do
    FollowState.list_online_users()
  end

  def user_online?(user_id) do
    case FollowState.get(user_id) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
