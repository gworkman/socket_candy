defmodule SocketCandy.Frame do
  @frame_regex ~r/(\d+) (\d+\.\d+) ([A-F0-9\s]+)/

  defstruct [:id, :data, :timestamp]

  @spec to_message(%__MODULE__{}) :: String.t()

  def to_message(%__MODULE__{id: id, data: nil}), do: "#{Integer.to_string(id, 16)} 0"

  def to_message(%__MODULE__{id: id, data: data}) when is_binary(data) do
    id_string = Integer.to_string(id, 16)
    dlc = byte_size(data)

    data_string =
      data
      |> :erlang.binary_to_list()
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.join(" ")

    "#{id_string} #{dlc} #{data_string}"
  end

  @spec from_message(String.t()) :: %__MODULE__{}

  def from_message(data) when is_binary(data) do
    Regex.run(@frame_regex, data, capture: :all_but_first)
    |> then(fn [id_string, timestamp_string, data_string] ->
      id = String.to_integer(id_string, 16)

      timestamp =
        timestamp_string
        |> String.to_float()
        |> then(fn timestamp -> round(timestamp * 1_000_000) end)
        |> DateTime.from_unix!(:microsecond)

      data = Base.decode16!(data_string)

      %__MODULE__{id: id, timestamp: timestamp, data: data}
    end)
  end
end
