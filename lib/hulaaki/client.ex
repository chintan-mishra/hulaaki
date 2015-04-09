defmodule Hulaaki.Client do
  defmacro __using__(_) do
    quote location: :keep do
      use GenServer
      alias Hulaaki.Connection
      alias Hulaaki.Message

      def start_link(initial_state) do
        GenServer.start_link(__MODULE__, initial_state)
      end

      def stop(pid) do
        GenServer.call pid, :stop
      end

      def connect(pid, opts) do
        {:ok, conn_pid} = Connection.start_link(pid)
        GenServer.call pid, {:connect, opts, conn_pid}
      end

      def publish(pid, opts) do
        GenServer.call pid, {:publish, opts}
      end

      def subscribe(pid, opts) do
        GenServer.call pid, {:subscribe, opts}
      end

      def unsubscribe(pid, opts) do
        GenServer.call pid, {:unsubscribe, opts}
      end

      def ping(pid) do
        GenServer.call pid, :ping
      end

      def disconnect(pid) do
        GenServer.call pid, :disconnect
      end

      ## Overrideable callbacks

      def on_connect(options)
      def on_connect_ack(options)
      def on_publish(options)
      def on_publish_receive(options)
      def on_publish_release(options)
      def on_publish_complete(options)
      def on_publish_ack(options)
      def on_subscribe(options)
      def on_subscribe_ack(options)
      def on_unsubscribe(options)
      def on_unsubscribe_ack(options)
      def on_subscribed_publish(options)
      def on_ping(options)
      def on_pong(options)
      def on_disconnect(options)

      defoverridable [on_connect: 1, on_connect_ack: 1,
                      on_publish: 1, on_publish_ack: 1,
                      on_publish_receive: 1, on_publish_release: 1,
                      on_publish_complete: 1,
                      on_subscribe: 1, on_subscribe_ack: 1,
                      on_unsubscribe: 1, on_unsubscribe_ack: 1,
                      on_subscribed_publish: 1,
                      on_ping: 1,    on_pong: 1,
                      on_disconnect: 1]

      ## GenServer callbacks

      def init(%{} = state) do
        {:ok, state}
      end

      def handle_call(:stop, _from, state) do
        {:stop, :normal, :ok, state}
      end

      # collection options for host port ?

      def handle_call({:connect, opts, conn_pid}, _from, state) do
        client_id     = opts |> Keyword.fetch! :client_id
        username      = opts |> Keyword.get :username, ""
        password      = opts |> Keyword.get :password, ""
        will_topic    = opts |> Keyword.get :will_topic, ""
        will_message  = opts |> Keyword.get :will_message, ""
        will_qos      = opts |> Keyword.get :will_qos, 0
        will_retain   = opts |> Keyword.get :will_retain, 0
        clean_session = opts |> Keyword.get :clean_session, 1
        keep_alive    = opts |> Keyword.get :keep_alive, 100

        message = Message.connect(client_id, username, password,
                                  will_topic, will_message, will_qos,
                                  will_retain, clean_session, keep_alive)

        state = Map.merge(%{connection: conn_pid}, state)

        :ok = state.connection |> Connection.connect message
        {:reply, :ok, state}
      end

      def handle_call({:publish, opts}, _from, state) do
        id     = opts |> Keyword.fetch! :id
        topic  = opts |> Keyword.fetch! :topic
        msg    = opts |> Keyword.fetch! :message
        dup    = opts |> Keyword.fetch! :dup
        qos    = opts |> Keyword.fetch! :qos
        retain = opts |> Keyword.fetch! :retain

        message = Message.publish(id, topic, msg, dup, qos, retain)

        :ok = state.connection |> Connection.publish message
        {:reply, :ok, state}
      end

      def handle_call({:subscribe, opts}, _from, state) do
        id     = opts |> Keyword.fetch! :id
        topics = opts |> Keyword.fetch! :topics
        qoses  = opts |> Keyword.fetch! :qoses

        message = Message.subscribe(id, topics, qoses)

        :ok = state.connection |> Connection.subscribe message
        {:reply, :ok, state}
      end

      def handle_call({:unsubscribe, opts}, _from, state) do
        id     = opts |> Keyword.fetch! :id
        topics = opts |> Keyword.fetch! :topics

        message = Message.unsubscribe(id, topics)

        :ok = state.connection |> Connection.unsubscribe message
        {:reply, :ok, state}
      end

      def handle_call(:ping, _from, state) do
        :ok = state.connection |> Connection.ping
        {:reply, :ok, state}
      end

      def handle_call(:disconnect, _from, state) do
        :ok = state.connection |> Connection.disconnect
        {:reply, :ok, state}
      end

      def handle_info({:sent, %Message.Connect{} = message}, state) do
        on_connect [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.ConnAck{} = message}, state) do
        on_connect_ack [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:sent, %Message.Publish{} = message}, state) do
        on_publish [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.Publish{} = message}, state) do
        on_subscribed_publish [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.PubRec{} = message}, state) do
        on_publish_receive [message: message, state: state]

        message = Message.publish_release message.id
        :ok = state.connection |> Connection.publish_release message

        {:noreply, state}
      end

      def handle_info({:sent, %Message.PubRel{} = message}, state) do
        on_publish_release [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.PubComp{} = message}, state) do
        on_publish_complete [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.PubAck{} = message}, state) do
        on_publish_ack [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:sent, %Message.Subscribe{} = message}, state) do
        on_subscribe [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.SubAck{} = message}, state) do
        on_subscribe_ack [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:sent, %Message.Unsubscribe{} = message}, state) do
        on_unsubscribe [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.UnsubAck{} = message}, state) do
        on_unsubscribe_ack [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:sent, %Message.PingReq{} = message}, state) do
        on_ping [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:received, %Message.PingResp{} = message}, state) do
        on_pong [message: message, state: state]
        {:noreply, state}
      end

      def handle_info({:sent, %Message.Disconnect{} = message}, state) do
        on_disconnect [message: message, state: state]
        {:noreply, state}
      end
    end
  end
end
