defmodule LoadBalancer.Analyzer do
  require Logger

  def analyze_logs(results) do
    Logger.info("Analyzing results for each algorithm")

    Enum.each(results, fn {algorithm, data} ->
      analyze_algorithm(algorithm, data)
    end)
  end

  defp analyze_algorithm(algorithm, data) do
    Logger.info("======= Analysis for #{algorithm} =======")

    Logger.info("Server distribution:")
    Enum.each(data.server_distribution, fn {server_id, count} ->
      percentage = count / Enum.sum(Map.values(data.server_distribution)) * 100
      Logger.info("  Server #{server_id}: #{count} requests (#{Float.round(percentage, 2)}%)")
    end)

    response_times = Enum.map(data.responses, fn r -> r.processing_time end)
    min_time = Enum.min(response_times)
    max_time = Enum.max(response_times)
    avg_time = Enum.sum(response_times) / length(response_times)

    Logger.info("Response time statistics:")
    Logger.info("  Min: #{min_time}ms")
    Logger.info("  Max: #{max_time}ms")
    Logger.info("  Avg: #{Float.round(avg_time, 2)}ms")

    server_loads = Enum.group_by(data.responses, fn r -> r.server_id end, fn r -> r.server_load end)

    Logger.info("Server load over time:")
    Enum.each(server_loads, fn {server_id, loads} ->
      avg_load = Enum.sum(loads) / length(loads)
      Logger.info("  Server #{server_id} avg load: #{Float.round(avg_load, 2)}")
    end)

    Logger.info("")
  end
end
