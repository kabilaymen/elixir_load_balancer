# Elixir Load Balancer

A high-performance, configurable load balancer implementation in Elixir with support for multiple load balancing algorithms.

## Features

- Multiple load balancing algorithms:
  - Round Robin
  - Random
  - Least Connections
  - Static Weighted Round Robin
  - Dynamic Weighted Round Robin
  - IP Hash
  - Least Response Time
- Real-time server load monitoring
- Dynamic resource utilization (CPU and memory)
- Comprehensive metrics and analysis
- Configurable concurrency levels
- Simulated processing with realistic performance characteristics

## Architecture

The load balancer is built on Elixir's GenServer architecture and consists of the following components:

- **LoadBalancer.LoadBalancer**: The main load balancing service that distributes requests
- **LoadBalancer.Server**: Individual server implementations that handle requests
- **LoadBalancer.Client**: Test client that generates traffic
- **LoadBalancer.Analyzer**: Analytics component that evaluates performance
- **LoadBalancer.Application**: OTP application that ties everything together
- **LoadBalancer.Run**: Entry point for running tests

## Load Balancing Algorithms

### Round Robin
Simple sequential distribution of requests across all servers.

### Random
Random server selection, providing basic load distribution.

### Least Connections
Selects the server with the fewest active connections, considering historical load.

### Static Weighted Round Robin
Uses predefined weights to favor certain servers over others.

### Dynamic Weighted Round Robin
Adjusts server weights based on real-time server load metrics.

### IP Hash
Routes requests from the same IP address to the same server, ensuring session consistency.

### Least Response Time
Selects servers based on a combination of response time, current load, and historical performance.

## Performance Metrics

Each algorithm is evaluated based on:
- Request distribution across servers
- Response times (minimum, maximum, average)
- Server load over time
- Processing overhead

## Getting Started

### Prerequisites

- Elixir 1.14 or later
- Erlang OTP 25 or later

### Installation

1. Clone the repository:
```bash
git clone https://github.com/kabilaymen/elixir_load_balancer.git
cd elixir_load_balancer
```

2. Install dependencies:
```bash
mix deps.get
```

3. Compile the project:
```bash
mix compile
```

### Running the Load Balancer

Start the application:
```bash
mix run --no-halt
```

To run the test suite with all algorithms:
```bash
mix run -e "LoadBalancer.Run.main()"
```

## Configuration

You can adjust the following parameters:

- Server capacity (CPU and memory)
- Number of requests per test
- Concurrency level
- Request processing characteristics

Edit the constants in the modules to adjust these parameters:

```elixir
# In LoadBalancer.Server
@max_concurrent_requests 20
@cpu_capacity 10
@memory_capacity 100
@request_cpu_cost 1
@request_memory_cost 20
```

## Example Usage

```elixir
# Send 50 requests using the least connections algorithm with concurrency of 5
responses = LoadBalancer.Client.send_requests(50, :least_connections, 5)

# Test all algorithms with 30 requests each
results = LoadBalancer.Client.test_all_algorithms(30)

# Analyze and print results
LoadBalancer.Analyzer.analyze_logs(results)
```

## Sample Output

```
======= Analysis for round_robin =======
Server distribution:
  Server 1: 10 requests (33.33%)
  Server 2: 10 requests (33.33%)
  Server 3: 10 requests (33.33%)
Response time statistics:
  Min: 75ms
  Max: 124ms
  Avg: 98.45ms
Server load over time:
  Server 1 avg load: 4.6
  Server 2 avg load: 5.2
  Server 3 avg load: 4.8

======= Analysis for least_response_time =======
Server distribution:
  Server 1: 15 requests (50.00%)
  Server 2: 8 requests (26.67%)
  Server 3: 7 requests (23.33%)
Response time statistics:
  Min: 65ms
  Max: 110ms
  Avg: 79.21ms
Server load over time:
  Server 1 avg load: 5.7
  Server 2 avg load: 6.3
  Server 3 avg load: 6.1
```

## Implementation Details

### Server Simulation

Each server simulates real-world behavior:
- CPU and memory usage that fluctuates over time
- Resource consumption per request
- Recovery of resources during idle periods
- Variable processing times based on current load

### Load Calculation

Server load is calculated as a weighted combination of:
- CPU usage (50%)
- Memory usage (30%)
- Active request queue (20%)
