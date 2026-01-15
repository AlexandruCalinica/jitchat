defmodule ComoWeb.Channels.FollowChannel do
  use ComoWeb, :channel
  require Logger

  alias Como.Follow
  alias ComoWeb.Channels.FollowPresence

  @impl true
  def join("follow:" <> target_user_id, _params, socket) do
    user_id = socket.assigns[:user_id]

    cond do
      is_nil(user_id) ->
        {:error, %{reason: "unauthenticated"}}

      user_id != target_user_id ->
        {:error, %{reason: "unauthorized"}}

      true ->
        send(self(), :after_join)
        {:ok, socket}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    %{user_id: user_id, username: username, color: color, tenant_id: tenant_id} = socket.assigns
    topic = presence_topic(tenant_id)

    :ok = Follow.register_user(user_id, username, color, self())

    {:ok, _} =
      FollowPresence.track(self(), topic, user_id, %{
        user_id: user_id,
        username: username,
        color: color,
        current_doc_id: nil,
        online_at: System.system_time(:millisecond)
      })

    Phoenix.PubSub.subscribe(Como.PubSub, topic)
    Phoenix.PubSub.subscribe(Como.PubSub, "follow:#{user_id}")

    push(socket, "presence_state", FollowPresence.list(topic))
    {:noreply, socket}
  end

  def handle_info({:push_event, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(%{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("presence:update", %{"doc_id" => doc_id}, socket) do
    %{user_id: user_id, tenant_id: tenant_id} = socket.assigns
    topic = presence_topic(tenant_id)

    :ok = Follow.update_current_doc(user_id, doc_id)

    FollowPresence.update(self(), topic, user_id, fn meta ->
      Map.put(meta, :current_doc_id, doc_id)
    end)

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("ping:send", payload, socket) do
    user_id = socket.assigns.user_id
    target_ids = Map.get(payload, "target_user_ids", [])
    doc_id = Map.get(payload, "doc_id")
    message = Map.get(payload, "message")

    case Follow.check_ping_rate_limit(user_id) do
      {:error, :rate_limited} ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}

      :ok ->
        targets = resolve_ping_targets(target_ids, user_id)
        {sent_to, offline} = send_pings(socket.assigns, targets, doc_id, message)
        {:reply, {:ok, %{sent_to: sent_to, offline: offline}}, socket}
    end
  end

  @impl true
  def handle_in("follow:start", %{"leader_id" => leader_id}, socket) do
    %{user_id: follower_id, tenant_id: tenant_id} = socket.assigns
    topic = presence_topic(tenant_id)

    cond do
      follower_id == leader_id ->
        {:reply, {:error, %{reason: "cannot_follow_self"}}, socket}

      not user_online_in_presence?(topic, leader_id) ->
        {:reply, {:error, %{reason: "leader_not_found"}}, socket}

      true ->
        :ok = Follow.set_following(follower_id, leader_id)
        notify_leader_follow_started(leader_id, socket.assigns)

        leader_meta = get_presence_meta(topic, leader_id)

        {:reply,
         {:ok,
          %{
            leader: %{
              doc_id: leader_meta[:current_doc_id],
              scroll_top: nil
            }
          }}, socket}
    end
  end

  @impl true
  def handle_in("follow:stop", _payload, socket) do
    follower_id = socket.assigns.user_id

    case Follow.stop_following(follower_id) do
      {:ok, :not_following} ->
        {:reply, :ok, socket}

      {:ok, leader_id} ->
        notify_leader_follow_stopped(leader_id, follower_id)
        {:reply, :ok, socket}

      _ ->
        {:reply, :ok, socket}
    end
  end

  @impl true
  def handle_in("follow:scroll", payload, socket) do
    user_id = socket.assigns.user_id
    doc_id = Map.get(payload, "doc_id")
    scroll_top = Map.get(payload, "scroll_top", 0)
    scroll_left = Map.get(payload, "scroll_left", 0)
    viewport_height = Map.get(payload, "viewport_height")

    case Follow.update_scroll(user_id, doc_id, scroll_top, scroll_left, viewport_height) do
      :ok ->
        broadcast_to_followers(user_id, "follow:scroll", %{
          leader_id: user_id,
          doc_id: doc_id,
          scroll_top: scroll_top,
          scroll_left: scroll_left,
          viewport_height: viewport_height
        })

      {:error, :throttled} ->
        :ok

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("follow:doc_switch", %{"doc_id" => doc_id}, socket) do
    %{user_id: user_id, tenant_id: tenant_id} = socket.assigns
    topic = presence_topic(tenant_id)

    :ok = Follow.update_current_doc(user_id, doc_id)

    FollowPresence.update(self(), topic, user_id, fn meta ->
      Map.put(meta, :current_doc_id, doc_id)
    end)

    broadcast_to_followers(user_id, "follow:doc_switch", %{
      leader_id: user_id,
      doc_id: doc_id
    })

    {:reply, :ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:user_id] do
      nil ->
        :ok

      user_id ->
        handle_user_disconnect(user_id, socket.assigns)
    end
  end

  defp handle_user_disconnect(user_id, assigns) do
    case Follow.get_user_state(user_id) do
      {:ok, %{following: leader_id, followers: followers}} ->
        if leader_id do
          notify_leader_follow_stopped(leader_id, user_id)
        end

        Enum.each(followers, fn follower_id ->
          notify_follower_leader_offline(follower_id, user_id)
        end)

        Follow.unregister_user(user_id)

      _ ->
        :ok
    end

    Logger.info("FollowChannel: user #{assigns.username} (#{user_id}) disconnected")
  end

  defp resolve_ping_targets("all", sender_id) do
    Follow.list_online_users()
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&(&1 == sender_id))
  end

  defp resolve_ping_targets(target_ids, _sender_id) when is_list(target_ids) do
    target_ids
  end

  defp resolve_ping_targets(_, _), do: []

  defp send_pings(sender, target_ids, doc_id, message) do
    topic = presence_topic(sender.tenant_id)

    ping_payload = %{
      from: %{
        user_id: sender.user_id,
        username: sender.username,
        color: sender.color
      },
      doc_id: doc_id,
      message: message,
      timestamp: System.system_time(:millisecond)
    }

    Enum.reduce(target_ids, {[], []}, fn target_id, {sent, offline} ->
      if user_online_in_presence?(topic, target_id) do
        Phoenix.PubSub.broadcast(
          Como.PubSub,
          "follow:#{target_id}",
          %{event: "ping:received", payload: ping_payload}
        )

        {[target_id | sent], offline}
      else
        {sent, [target_id | offline]}
      end
    end)
  end

  defp notify_leader_follow_started(leader_id, follower_assigns) do
    Phoenix.PubSub.broadcast(
      Como.PubSub,
      "follow:#{leader_id}",
      %{
        event: "follow:started",
        payload: %{
          follower: %{
            user_id: follower_assigns.user_id,
            username: follower_assigns.username,
            color: follower_assigns.color
          }
        }
      }
    )
  end

  defp notify_leader_follow_stopped(leader_id, follower_id) do
    Phoenix.PubSub.broadcast(
      Como.PubSub,
      "follow:#{leader_id}",
      %{event: "follow:stopped", payload: %{follower_id: follower_id}}
    )
  end

  defp notify_follower_leader_offline(follower_id, leader_id) do
    Phoenix.PubSub.broadcast(
      Como.PubSub,
      "follow:#{follower_id}",
      %{event: "follow:leader_offline", payload: %{leader_id: leader_id}}
    )
  end

  defp broadcast_to_followers(leader_id, event, payload) do
    case Follow.get_followers(leader_id) do
      {:ok, followers} ->
        Enum.each(followers, fn follower_id ->
          Phoenix.PubSub.broadcast(
            Como.PubSub,
            "follow:#{follower_id}",
            %{event: event, payload: payload}
          )
        end)

      _ ->
        :ok
    end
  end

  defp presence_topic(tenant_id), do: "lobby:#{tenant_id}"

  defp user_online_in_presence?(topic, user_id) do
    case FollowPresence.list(topic)[user_id] do
      nil -> false
      %{metas: [_ | _]} -> true
    end
  end

  defp get_presence_meta(topic, user_id) do
    case FollowPresence.list(topic)[user_id] do
      %{metas: [meta | _]} -> meta
      _ -> %{}
    end
  end
end
