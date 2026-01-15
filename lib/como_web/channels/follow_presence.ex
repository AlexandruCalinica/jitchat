defmodule ComoWeb.Channels.FollowPresence do
  use Phoenix.Presence,
    otp_app: :como,
    pubsub_server: Como.PubSub
end
