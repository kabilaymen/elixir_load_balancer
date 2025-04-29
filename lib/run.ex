defmodule LoadBalancer.Run do
  require Logger

  def main do
    Logger.info("Starting test run of load balancer with all algorithms")
    results = LoadBalancer.Client.test_all_algorithms(30)
    LoadBalancer.Analyzer.analyze_logs(results)
    Logger.info("Test run completed")
  end
end
