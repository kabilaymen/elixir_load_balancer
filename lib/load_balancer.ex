defmodule LoadBalancer.LoadBalancer do
  use GenServer
  require Logger

  @algorithms [
    :round_robin,
    :random,
    :least_connections,
    :dynamic_weighted_round_robin,
    :static_weighted_round_robin,
    :ip_hash,
    :least_response_time
  ]

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def handle_request(request_id, algorithm \\ :round_robin, client_ip \\ nil) do
    GenServer.call(__MODULE__, {:request, request_id, algorithm, client_ip})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def init(_) do
    server_ids = [1, 2, 3]

    initial_response_times = Map.new(server_ids, fn id -> {id, 100} end)

    Logger.info("Load balancer started with algorithms: #{inspect(@algorithms)}")

    {:ok,
     %{
       servers: server_ids,
       current_index: 0,
       global_index_wrr: 0,
       stats: %{
         round_robin: %{requests: 0, total_time: 0},
         random: %{requests: 0, total_time: 0},
         least_connections: %{requests: 0, total_time: 0},
         static_weighted_round_robin: %{requests: 0, total_time: 0},
         dynamic_weighted_round_robin: %{requests: 0, total_time: 0},
         ip_hash: %{requests: 0, total_time: 0},
         least_response_time: %{requests: 0, total_time: 0}
       },
       response_times: initial_response_times,
       server_request_counts: Map.new(server_ids, fn id -> {id, 0} end)
     }}
  end

  def handle_call({:request, request_id, algorithm, client_ip}, _from, state) do
    Logger.info("Load balancer received request #{request_id} using algorithm: #{algorithm}")

    start_time = System.monotonic_time(:millisecond)

    case select_server(algorithm, state, request_id, client_ip) do
      nil ->
        Logger.error(
          "Could not select a server for request #{request_id} using algorithm #{algorithm}. No servers available or algorithm failed."
        )

        {:reply, {:error, :no_server_available}, state}

      server_id ->
        Logger.info("Request #{request_id} routed to server #{server_id}")

        server_request_counts =
          Map.update!(state.server_request_counts, server_id, fn count -> count + 1 end)

        response = LoadBalancer.Server.handle_request(server_id, request_id)

        end_time = System.monotonic_time(:millisecond)
        server_processing_time = response.processing_time
        lb_overhead_time = end_time - start_time

        stats =
          Map.update!(state.stats, algorithm, fn alg_stats ->
            %{
              requests: alg_stats.requests + 1,
              total_time: alg_stats.total_time + lb_overhead_time
            }
          end)

        response_times = Map.put(state.response_times, server_id, server_processing_time)

        new_state =
          case algorithm do
            :static_weighted_round_robin ->
              Map.merge(state, %{
                global_index_wrr: state.global_index_wrr + 1,
                stats: stats,
                response_times: response_times,
                server_request_counts: server_request_counts
              })

            :dynamic_weighted_round_robin ->
              Map.merge(state, %{
                global_index_wrr: state.global_index_wrr + 1,
                stats: stats,
                response_times: response_times,
                server_request_counts: server_request_counts
              })

            _ ->
              Map.merge(state, %{
                current_index: rem(state.current_index + 1, length(state.servers)),
                stats: stats,
                response_times: response_times,
                server_request_counts: server_request_counts
              })
          end

        {:reply, response, new_state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Round Robin simple
  defp select_server(:round_robin, state, _request_id, _client_ip) do
    if Enum.empty?(state.servers) do
      Logger.error("Round Robin: No servers available.")
      nil
    else
      index = rem(state.current_index, length(state.servers))
      Enum.at(state.servers, index)
    end
  end

  # Random Selection
  defp select_server(:random, state, _request_id, _client_ip) do
    if Enum.empty?(state.servers) do
      Logger.error("Random: No servers available.")
      nil
    else
      Enum.random(state.servers)
    end
  end

  defp select_server(:least_connections, state, request_id, _client_ip) do
    server_loads =
      Enum.map(state.servers, fn id ->
        try do
          {id, LoadBalancer.Server.get_load(id)}
        rescue
          e ->
            Logger.error("Failed to get load for server #{id}: #{inspect(e)}")
            {id, nil}
        end
      end)
      |> Enum.filter(fn {_, info} -> info != nil end)

    if Enum.empty?(server_loads) do
      Logger.error("Least Connections: Could not get load from any server.")
      nil
    else
      ranked_servers =
        Enum.map(server_loads, fn {id, info} ->
          historical_requests = Map.get(state.server_request_counts, id, 0)

          history_factor = :math.log(historical_requests + 1) / 10

          score = info.active_requests + history_factor

          Logger.debug(
            "Least Connections [Req:#{request_id}] Server #{id}: active=#{info.active_requests}, history=#{historical_requests}, history_factor=#{history_factor}, score=#{score}"
          )

          {id, score}
        end)

      {server_id, score} = Enum.min_by(ranked_servers, fn {_, score} -> score end)

      Logger.debug(
        "Least Connections [Req:#{request_id}] Selected server #{server_id} with score #{score}"
      )

      server_id
    end
  end

  # Static Weighted Round Robin
  defp select_server(:static_weighted_round_robin, state, request_id, client_ip) do
    weights = %{1 => 9, 2 => 1, 3 => 1}
    Logger.debug("[Static WRR Req:#{request_id}] Using weights: #{inspect(weights)}")
    Logger.debug("[Static WRR Req:#{request_id}] Servers in state: #{inspect(state.servers)}")

    weighted_servers =
      Enum.flat_map(state.servers, fn id ->
        weight = Map.get(weights, id, 1)
        actual_weight = max(0, weight)
        List.duplicate(id, actual_weight)
      end)

    Logger.debug(
      "[Static WRR Req:#{request_id}] Generated weighted_servers (size #{length(weighted_servers)}): #{inspect(weighted_servers)}"
    )

    if Enum.empty?(weighted_servers) do
      Logger.warning(
        "[Static WRR Req:#{request_id}] weighted_servers list is empty. Falling back."
      )

      select_server(:random, state, request_id, client_ip)
    else
      list_length = length(weighted_servers)
      current_idx = state.global_index_wrr
      index = rem(current_idx, list_length)
      selected_server = Enum.at(weighted_servers, index)

      Logger.debug(
        "[Static WRR Req:#{request_id}] List Length: #{list_length}, Global Index (global_index_wrr): #{current_idx}, Calculated Index: #{index}, Selected Server: #{selected_server}"
      )

      selected_server
    end
  end

  # Dynamic Weighted Round Robin
  defp select_server(:dynamic_weighted_round_robin, state, request_id, client_ip) do
    server_loads =
      Enum.map(state.servers, fn id ->
        try do
          {id, LoadBalancer.Server.get_load(id)}
        rescue
          e ->
            Logger.error(
              "[Dynamic WRR Req:#{request_id}] Failed to get load for server #{id}: #{inspect(e)}"
            )

            {id, nil}
        end
      end)
      |> Enum.filter(fn {_, info} -> info != nil end)

    Logger.debug(
      "[Dynamic WRR Req:#{request_id}] Filtered server_loads: #{inspect(server_loads)}"
    )

    if Enum.empty?(server_loads) do
      Logger.error("[Dynamic WRR Req:#{request_id}] Could not get load from any server.")
      nil
    else
      weighted_servers =
        Enum.flat_map(server_loads, fn {id, info} ->
          weight = 11 - info.load
          actual_weight = max(0, weight)
          List.duplicate(id, actual_weight)
        end)

      Logger.debug(
        "[Dynamic WRR Req:#{request_id}] Generated weighted_servers (size #{length(weighted_servers)}): #{inspect(weighted_servers)}"
      )

      if Enum.empty?(weighted_servers) do
        Logger.warning(
          "[Dynamic WRR Req:#{request_id}] weighted_servers list is empty after weighting. Falling back."
        )

        select_server(:random, state, request_id, client_ip)
      else
        list_length = length(weighted_servers)
        current_idx = state.global_index_wrr
        index = rem(current_idx, list_length)
        selected_server = Enum.at(weighted_servers, index)

        Logger.debug(
          "[Dynamic WRR Req:#{request_id}] List Length: #{list_length}, Global Index (global_index_wrr): #{current_idx}, Calculated Index: #{index}, Selected Server: #{selected_server}"
        )

        selected_server
      end
    end
  end

  # IP Hash
  defp select_server(:ip_hash, state, _request_id, client_ip) do
    if Enum.empty?(state.servers) do
      Logger.error("IP Hash: No servers available.")
      nil
    else
      ip =
        client_ip ||
          "#{:rand.uniform(255)}.#{:rand.uniform(255)}.#{:rand.uniform(255)}.#{:rand.uniform(255)}"

      hash = :erlang.phash2(ip, length(state.servers))
      Enum.at(state.servers, hash)
    end
  end

  defp select_server(:least_response_time, state, request_id, client_ip) do
    if Enum.empty?(state.response_times) do
      Logger.error("Least Response Time: No response time data available.")

      if Enum.empty?(state.servers) do
        nil
      else
        select_server(:random, state, request_id, client_ip)
      end
    else
      server_loads =
        Enum.map(state.servers, fn id ->
          try do
            {id, LoadBalancer.Server.get_load(id)}
          rescue
            e ->
              Logger.error(
                "Least Response Time [Req:#{request_id}] Failed to get load for server #{id}: #{inspect(e)}"
              )

              {id, nil}
          end
        end)
        |> Enum.filter(fn {_, info} -> info != nil end)
        |> Enum.into(%{})

      scores =
        Enum.map(state.response_times, fn {id, time} ->
          normalized_time = min(10, time / 15)

          load =
            case Map.get(server_loads, id) do
              nil -> 5
              info -> info.load
            end

          historical_bias = :math.sqrt(Map.get(state.server_request_counts, id, 0)) / 10

          score = normalized_time * 0.3 + load * 0.6 + historical_bias * 0.1

          Logger.debug(
            "Least Response Time [Req:#{request_id}] Server #{id}: time=#{time}ms, load=#{load}, history=#{historical_bias}, score=#{score}"
          )

          {id, score}
        end)

      if Enum.empty?(scores) do
        select_server(:random, state, request_id, client_ip)
      else
        {server_id, score} = Enum.min_by(scores, fn {_, score} -> score end)

        Logger.debug(
          "Least Response Time [Req:#{request_id}] Selected server #{server_id} with score #{score}"
        )

        server_id
      end
    end
  end
end
