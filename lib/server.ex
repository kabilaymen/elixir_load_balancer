defmodule LoadBalancer.Server do
  use GenServer
  require Logger

  @max_concurrent_requests 20
  @cpu_capacity 10
  @memory_capacity 100
  @request_cpu_cost 1
  @request_memory_cost 20

  def start_link(id) do
    GenServer.start_link(__MODULE__, id, name: via_tuple(id))
  end

  def via_tuple(id) do
    {:via, Registry, {LoadBalancer.ServerRegistry, "server_#{id}"}}
  end

  def handle_request(server_id, request_id) do
    GenServer.call(via_tuple(server_id), {:request, request_id})
  end

  def get_load(server_id) do
    GenServer.call(via_tuple(server_id), :get_load)
  end

  def init(id) do
    schedule_maintenance()

    {:ok,
     %{
       id: id,
       active_requests: 0,
       cpu_usage: baseline_cpu_usage(),
       memory_usage: baseline_memory_usage(),
       requests_handled: 0,
       request_history: [],
       last_maintenance: System.monotonic_time(:millisecond),
       load: 0
     }}
  end

  def handle_call({:request, request_id}, from, state) do
    state = add_active_request(state)

    load_factor = calculate_load_factor(state)

    state = %{state | load: load_factor}

    process_time = base_process_time(load_factor)

    Task.start(fn ->
      Process.sleep(process_time)

      response = %{
        server_id: state.id,
        request_id: request_id,
        processing_time: process_time,
        server_load: load_factor
      }

      GenServer.cast(via_tuple(state.id), {:complete_request, process_time})
      GenServer.reply(from, response)
    end)

    {:noreply, state}
  end

  def handle_call(:get_load, _from, state) do
    load_factor = calculate_load_factor(state)
    state = %{state | load: load_factor}

    load_details = %{
      load: state.load,
      load_factor: load_factor,
      active_requests: state.active_requests,
      cpu_usage: state.cpu_usage,
      memory_usage: state.memory_usage,
      requests_handled: state.requests_handled
    }

    {:reply, load_details, state}
  end

  def handle_cast({:complete_request, process_time}, state) do
    new_state =
      state
      |> remove_active_request()
      |> add_to_history(process_time)
      |> increment_requests_handled()

    {:noreply, new_state}
  end

  def handle_info(:maintenance, state) do
    current_time = System.monotonic_time(:millisecond)
    time_diff = current_time - state.last_maintenance

    new_state = %{
      state
      | cpu_usage: adjust_cpu_usage(state.cpu_usage, time_diff, state.active_requests),
        memory_usage: adjust_memory_usage(state.memory_usage, time_diff, state.active_requests),
        last_maintenance: current_time
    }

    load_factor = calculate_load_factor(new_state)
    new_state = %{new_state | load: load_factor}

    schedule_maintenance()

    {:noreply, new_state}
  end

  defp add_active_request(state) do
    %{
      state
      | active_requests: state.active_requests + 1,
        cpu_usage: min(@cpu_capacity, state.cpu_usage + @request_cpu_cost),
        memory_usage: min(@memory_capacity, state.memory_usage + @request_memory_cost)
    }
  end

  defp remove_active_request(state) do
    %{state | active_requests: max(0, state.active_requests - 1)}
  end

  defp add_to_history(state, process_time) do
    history = [process_time | state.request_history] |> Enum.take(10)
    %{state | request_history: history}
  end

  defp increment_requests_handled(state) do
    %{state | requests_handled: state.requests_handled + 1}
  end

  defp calculate_load_factor(state) do
    cpu_factor = state.cpu_usage / @cpu_capacity * 10
    memory_factor = state.memory_usage / @memory_capacity * 10
    queue_factor = state.active_requests / @max_concurrent_requests * 10

    load = cpu_factor * 0.5 + memory_factor * 0.3 + queue_factor * 0.2

    max(1, min(10, round(load)))
  end

  defp base_process_time(load_factor) do
    base_time = load_factor * 15
    variance = base_time * 0.2
    variation = :rand.uniform() * variance * 2 - variance

    round(base_time + variation)
  end

  defp baseline_cpu_usage do
    5 + :rand.uniform(10)
  end

  defp baseline_memory_usage do
    100 + :rand.uniform(100)
  end

  defp adjust_cpu_usage(current_usage, time_diff, active_requests) do
    base_recovery = time_diff / 1000 * 2

    actual_recovery = base_recovery * (1 - min(1, active_requests / @max_concurrent_requests))

    fluctuation = :rand.normal() * 2

    new_usage = current_usage - actual_recovery + fluctuation
    min(@cpu_capacity, max(baseline_cpu_usage(), new_usage))
  end

  defp adjust_memory_usage(current_usage, time_diff, active_requests) do
    base_recovery = time_diff / 1000 * 5

    active_factor = active_requests / @max_concurrent_requests

    load_adjustment =
      if active_factor > 0.7 do
        active_factor * 3
      else
        -1 * (0.7 - active_factor) * 2
      end

    fluctuation = :rand.normal() * 1.5

    new_usage = current_usage - base_recovery + load_adjustment + fluctuation
    min(@memory_capacity, max(baseline_memory_usage(), new_usage))
  end

  defp schedule_maintenance do
    Process.send_after(self(), :maintenance, 100)
  end
end
