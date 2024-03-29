defmodule StreamLiveBot.StreamStatus do
  use Plug.Router
  use Plug.ErrorHandler
  require Logger

  @repo StreamLiveBot.Repo

  plug(Plug.Parsers, parsers: [:json, :urlencoded], json_decoder: Poison)
  plug(:match)
  plug(:dispatch)

  defp twitch_user_link(username), do: "twitch.tv/#{username}"

  defp send_notifications(subscribers, text) do
    Enum.map(
      subscribers,
      &Task.start(fn -> Nadia.send_message(&1, text) end)
    )
  end

  get "/stream_changed" do
    query_params = Plug.Conn.fetch_query_params(conn).query_params
    challenge_token = Map.get(query_params, "hub.challenge")

    if challenge_token do
      Logger.info("Server responded with a challenge token.")

      send_resp(conn, 200, challenge_token)
    else
      send_resp(conn, 400, "Your URL doesn't contain 'hub.challenge' query parameter.")
    end
  end

  post "/stream_changed" do
    stream_online = System.get_env("STREAM_ONLINE")
    streams_data = Map.get(conn.params, "data")

    cond do
      streams_data != [] and stream_online == "false" ->
        Logger.info("Stream started")

        System.put_env(
          "STREAM_ONLINE",
          "true"
        )

        twitch_streamer_link =
          twitch_user_link(Application.get_env(:stream_live_bot, :streamer_username))

        send_notifications(
          @repo.get_subscribers(),
          "Stream started!\n#{twitch_streamer_link}"
        )

      streams_data == [] ->
        Logger.info("Stream finished")

        System.put_env(
          "STREAM_ONLINE",
          "false"
        )

      true ->
        nil
    end

    send_resp(conn, 200, "")
  end

  get "/online" do
    send_resp(conn, 200, System.get_env("STREAM_ONLINE"))
  end

  match _ do
    send_resp(conn, 404, "Oops!")
  end

  defp handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    IO.inspect(kind, label: :kind)
    IO.inspect(reason, label: :reason)
    IO.inspect(stack, label: :stack)

    send_resp(conn, conn.status, "Something went wrong")
  end
end
