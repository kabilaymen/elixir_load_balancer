defmodule LoadBalancer.Client do
  require Logger

  @doc """
  Send requests with configurable concurrency level
  """
  def send_requests(count, algorithm \\ :round_robin, concurrency \\ 1) do
    Logger.info("Client sending #{count} requests using algorithm: #{algorithm} with concurrency: #{concurrency}")

    1..count
    |> Task.async_stream(
      fn i ->
        client_ip = "#{:rand.uniform(255)}.#{:rand.uniform(255)}.#{:rand.uniform(255)}.#{:rand.uniform(255)}"

        response = LoadBalancer.LoadBalancer.handle_request(i, algorithm, client_ip)

        Logger.info("Client received response for request #{i} from server #{response.server_id}")
        response
      end,
      max_concurrency: concurrency,
      timeout: 30_000
    )
    |> Enum.map(fn {:ok, response} -> response end)
  end

  @doc """
  Test all algorithms with a specified number of requests and concurrency level
  """
  def test_all_algorithms(requests_per_algorithm \\ 30, concurrency \\ 1) do
    algorithms = [
      :round_robin,
      :random,
      :least_connections,
      :dynamic_weighted_round_robin,
      :static_weighted_round_robin,
      :ip_hash,
      :least_response_time
    ]

    Logger.info("Testing all load balancing algorithms with #{requests_per_algorithm} requests each (concurrency: #{concurrency})")

    results = Enum.map(algorithms, fn algorithm ->
      Logger.info("Starting test for #{algorithm}...")

      Process.sleep(1000)

      responses = send_requests(requests_per_algorithm, algorithm, concurrency)

      server_distribution = Enum.frequencies_by(responses, fn response -> response.server_id end)
      avg_response_time = Enum.sum(Enum.map(responses, fn r -> r.processing_time end)) / length(responses)

      {algorithm, %{
        server_distribution: server_distribution,
        avg_response_time: avg_response_time,
        responses: responses
      }}
    end)

    results
  end
end
