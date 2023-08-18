defmodule SocketCandy do
  @moduledoc """
  Documentation for `SocketCandy`.
  """
  alias SocketCandy.Frame

  @type state() :: %__MODULE__.State{}

  use GenServer
  require Logger

  defmodule State do
    defstruct [
      :socket,
      :device,
      auto_start: true,
      address: "localhost",
      port: 29536,
      retries: 0,
      max_retries: 5,
      waiting_for_open: []
    ]
  end

  @init_args ~w(address device port max_retries auto_start)a

  @spec start_link(keyword()) :: GenServer.start_link()
  def start_link(args) do
    opts = Keyword.get(args, :opts, [])

    init_args = Keyword.take(args, @init_args)
    state = struct!(__MODULE__.State, init_args)

    GenServer.start_link(__MODULE__, state, opts)
  end

  def open(server, device) do
    GenServer.call(server, {:open, device})
  end

  def stop(server) do
    GenServer.stop(server)
  end

  def subscribe(message_id) do
    Registry.register(SocketCandy.Registry, message_id, nil)
  end

  def unsubscribe(message_id) do
    Registry.unregister(SocketCandy.Registry, message_id)
  end

  @impl true
  def init(state) do
    case Map.get(state, :auto_start, true) do
      true ->
        state.device ||
          raise "Device was not specified (:device must be an argument to SocketCandy.start_link/1 when :auto_start is true)"

        {:ok, state, {:continue, :open}}

      _not_true ->
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:open, device}, from, state) do
    state =
      state
      |> Map.update(:waiting_for_open, [], &[from | &1])
      |> Map.put(:device, device)

    do_open(state)
  end

  @impl true
  def handle_continue(:open, state), do: do_open(state)

  @impl true
  def handle_info(:open, state), do: do_open(state)

  ## TCP HANDLERS

  def handle_info({:tcp, _port, data}, state) do
    state =
      Regex.scan(~r"< (.*?) >", "#{data}", capture: :all_but_first)
      |> List.flatten()
      |> Enum.reduce(state, &process_message/2)

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _port}, state) do
    Logger.warning("SocketCAN connection closed")
    do_retry(%{state | socket: nil})
  end

  defp process_message("ok", state) do
    state
    |> Map.get(:waiting_for_open)
    |> Enum.each(&GenServer.reply(&1, :ok))

    %{state | waiting_for_open: []}
  end

  defp process_message("error could not open bus", state) do
    state
    |> Map.get(:waiting_for_open)
    |> Enum.each(&GenServer.reply(&1, {:error, :invalid_device}))

    %{state | waiting_for_open: []}
  end

  defp process_message("hi", %{socket: socket, device: device} = state) do
    Logger.info("Opening SocketCAN device #{device}")
    :ok = :gen_tcp.send(socket, ~c"< open #{device} >< rawmode >")
    state
  end

  defp process_message("frame " <> data, state) do
    frame = Frame.from_message(data)

    Registry.dispatch(SocketCandy.Registry, frame.id, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:can_frame, frame})
    end)

    state
  end

  ## PRIVATE FUNCTIONS

  defp do_open(%{socket: socket} = state) when not is_nil(socket) do
    Logger.warning("SocketCAN connection is already open")
    {:noreply, state}
  end

  defp do_open(%{address: address, port: port} = state) do
    case :gen_tcp.connect(String.to_charlist(address), port, []) do
      {:ok, socket} ->
        {:noreply, %{state | socket: socket}}

      {:error, reason} ->
        Logger.warning("SocketCAN failed to connect: #{inspect(reason)}")
        do_retry(state)
    end
  end

  defp do_retry(%{retries: retries, max_retries: max_retries} = state) do
    if max_retries == :infinity || retries < max_retries do
      Process.send_after(self(), :open, 1000)
      {:noreply, %{state | retries: retries + 1}}
    else
      {:stop, :max_retry_limit, state}
    end
  end
end
