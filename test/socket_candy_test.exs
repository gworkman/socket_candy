defmodule SocketCandyTest do
  use ExUnit.Case
  doctest SocketCandy

  @test_address Application.compile_env!(:socket_candy, SocketCandyTest)[:address]
  @test_port Application.compile_env!(:socket_candy, SocketCandyTest)[:address]

  test "open the server" do
    {:ok, pid} = SocketCandy.start_link(address: @test_address, auto_start: false)
    assert SocketCandy.open(pid, "can0") == :ok
  end

  describe "serialize frame to send" do
    test "frame with no data" do
      frame = %SocketCandy.Frame{id: 0x123}
      assert SocketCandy.Frame.to_message(frame) == "123 0"
    end

    test "frame with data" do
      frame = %SocketCandy.Frame{id: 0x123, data: <<0x01, 0xF1>>}
      assert SocketCandy.Frame.to_message(frame) == "123 2 1 F1"
    end
  end

  test "parse frame with data" do
    frame = SocketCandy.Frame.from_message("123 23.424242 1A220344")

    assert frame.id == 0x123
    assert frame.data == <<0x1A, 0x22, 0x03, 0x44>>
    assert !is_nil(frame.timestamp)
  end

  describe "subscribe to frames" do
    test "perform subscription" do
      {:ok, pid} = SocketCandy.start_link(address: @test_address, auto_start: true)

      {:ok, _pid} = SocketCandy.subscribe(0x081)

      receive do
        {:can_frame, frame} -> assert frame.id == 0x081
      after
        1000 -> raise "receive message timed out"
      end
    end
  end
end
