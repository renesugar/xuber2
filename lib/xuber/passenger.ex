defmodule XUber.Passenger do
  use GenStateMachine, restart: :transient

  alias XUber.{
    Grid,
    Pickup,
    DispatcherSupervisor
  }

  @search_radius 5
  @search_interval 1000

  def start_link([user, coordinates]) do
    data = %{
      user: user,
      coordinates: coordinates,
      nearby: [],
      request: nil,
      pickup: nil,
      ride: nil,
      driver: nil
    }

    GenStateMachine.start_link(__MODULE__, data, [])
  end

  def init(data) do
    Grid.join(self(), data.coordinates, [:passenger])

    :timer.send_interval(@search_interval, :nearby)

    {:ok, :online, data}
  end

  def handle_call(:offline, _from, state),
    do: {:stop, :normal, :ok, state}

  def handle_event({:call, from}, {:request, coordinates}, :online, data) do
    {:ok, request} = DispatcherSupervisor.start_child(self(), coordinates)
    reply = {:reply, from, {:ok, request}}
    new_data = %{data | request: request}

    {:next_state, :requesting, new_data, reply}
  end

  def handle_event({:call, from}, {:dispatched, pickup, driver}, :requesting, data) do
    reply = {:reply, from, {:ok, pickup}}
    new_data = %{data | pickup: pickup, driver: driver, request: nil}

    {:next_state, :waiting, new_data, reply}
  end

  def handle_event({:call, from}, :cancel, :waiting, data) do
    reply = {:reply, from, Pickup.cancel(data.pickup)}
    new_data = %{data | pickup: nil}

    {:next_state, :online, new_data, reply}
  end

  def handle_event({:call, from}, {:depart, ride}, :waiting, data=%{pickup: pickup, driver: driver}) when not is_nil(driver) and not is_nil(pickup) do
    reply = {:reply, from, :ok}
    new_data = %{data | ride: ride, pickup: nil}

    {:next_state, :riding, new_data, reply}
  end

  def handle_event({:call, from}, :arrive, :riding, data=%{ride: ride}) when not is_nil(ride) do
    reply = {:reply, from, :ok}
    new_data = %{data | ride: nil, driver: nil}

    {:next_state, :online, new_data, reply}
  end

  def handle_event({:call, from}, {:move, coordinates}, _state, data) do
    Grid.update(self(), data.coordinates, coordinates)

    reply = {:reply, from, :ok}
    new_data = %{data | coordinates: coordinates}

    {:keep_state, new_data, reply}
  end

  def handle_event(:info, :nearby, _state, data) do
    nearby = Grid.nearby(data.coordinates, @search_radius, [:driver])

    {:keep_state, %{data | nearby: nearby}}
  end

  def offline(pid),
    do: GenStateMachine.call(pid, :offline)

  def request(pid, coordinates),
    do: GenStateMachine.call(pid, {:request, coordinates})

  def cancel(pid),
    do: GenStateMachine.call(pid, :cancel)

  def dispatched(pid, pickup, driver),
    do: GenStateMachine.call(pid, {:dispatched, pickup, driver})

  def depart(pid, ride),
    do: GenStateMachine.call(pid, {:depart, ride})

  def arrive(pid),
    do: GenStateMachine.call(pid, :arrive)

  def move(pid, coordinates),
    do: GenStateMachine.call(pid, {:move, coordinates})
end
