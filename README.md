# replr

**Isolated REPL functionality for R**

`replr` provides a robust system for executing R code in isolated worker processes, offering complete separation between the main R session and code execution environments. Useful for applications that need to run untrusted or potentially problematic R code without affecting the parent process.

## Installation

You can install the development version of replr like this:

``` r
install.packages("pak")
pak::pak("pkrusche/replr")
# Or using devtools:
# install.packages("devtools")
# devtools::install_github("pkrusche/replr")
```

## How It Works

```
┌─────────────────┐    nanonext     ┌─────────────────┐
│   Main R        │   REQ ──────>   │   Worker R      │
│   Process       │                 │   Process       │
│                 │   <────── REP   │                 │
│ • RREPLSession  │                 │ • evaluate pkg  │
│ • execute()     │     TCP         │ • plot capture  │
│ • stop()        │   Socket        │ • error handling│
└─────────────────┘                 └─────────────────┘
```

1. **Isolation**: Each worker runs as a separate R process with its own memory space
2. **Communication**: Uses `nanonext` REQ-REP pattern over TCP sockets for reliability
3. **Evaluation**: Workers use the `evaluate` package for safe code execution with rich output capture
4. **Error Recovery**: Workers survive errors and continue processing new requests
5. **Resource Management**: Automatic cleanup with proper process lifecycle management

## Quick Start

### R6 Class Interface

```r
library(replr)

# Create a new isolated R session
session <- RREPLSession$new()

# Execute R code in the isolated process
result <- session$execute("2 + 2")
print(result$result$output)  # [1] "[1] 4"

# Check session status
session$is_alive()  # TRUE
session$port        # Port number
session$pid         # Process ID

# Stop the session (or it will auto-cleanup on garbage collection)
session$stop()
```

### Error Handling

```r
library(replr)

session <- RREPLSession$new()

# Handle syntax errors
result1 <- session$execute("1 +")
print(result1$status)         # [1] "error"
print(result1$result$errors)  # [1] "Worker error: <text>:2:0: unexpected end of input\n1: 1 +\n   ^"

# Handle runtime errors
result2 <- session$execute("stop('Custom error')")
print(result2$status)         # [1] "error"
print(result2$result$errors)  # [1] "Worker error: Custom error"

# Worker continues after errors
result3 <- session$execute("3 * 4")
print(result3$status)         # [1] "success" - worker survived!
#
# Code that generates warnings
result4 <- session$execute("
  warning('This is a warning')
  42
")

print(result4$status)             # [1] "success"
print(result4$result$warnings)    # [1] "This is a warning"
print(result4$result$output)      # [1] "[1] 42"


session$stop()
```

### Debug Logging

```r
library(replr)

# Enable debug logging
enable_debug(TRUE)

# Now see output of what is happening
session <- RREPLSession$new()  # Shows startup debug messages

result <- session$execute("sqrt(16)")  # Shows communication debug

# Get logs programmatically
logs <- session$get_debug_logs()
cat("Worker generated", length(logs), "debug messages\n")

session$stop()  # Shows cleanup debug

# Disable debug logging
enable_debug(FALSE)

# Check current debug status
debug_status()
```

### Multiple Concurrent Sessions

```r
library(replr)

# Start multiple isolated sessions
session1 <- RREPLSession$new()
session2 <- RREPLSession$new()

# They run on different ports and are completely isolated
print(session1$port)  # e.g., 5555
print(session2$port)  # e.g., 5556

# Set different variables in each session
session1$execute("my_var <- 'Session 1'")
session2$execute("my_var <- 'Session 2'")

# Verify isolation - each session only sees its own variables
result1 <- session1$execute("my_var")
result2 <- session2$execute("my_var")

print(result1$result$output)  # [1] "[1] \"Session 1\""
print(result2$result$output)  # [1] "[1] \"Session 2\""

# Clean up both sessions
session1$stop()
session2$stop()
```

### Advanced Usage with Timeouts

```r
library(replr)

session <- RREPLSession$new()

# Set custom timeout for long-running operations
result <- session$execute(
  "Sys.sleep(2); 'Completed'",
  timeout = 5  # 5 second timeout
)
print(result$result$output)  # [1] "[1] \"Completed\""

# This would timeout:
# result <- session$execute("Sys.sleep(10)", timeout = 2)

session$stop()
```

## Docker Container Support

`replr` supports running worker processes inside Docker containers for enhanced security and isolation. When Docker is available, it automatically builds a minimal container image and runs workers with stricter security constraints.

### Security Features

- **Non-root execution**: Workers run as user `replr` (UID 1000)
- **Port forwarding**: Containers use port mapping for network communication
- **Read-only filesystem**: Prevents modification of container files
- **Restricted /tmp**: Temporary directory with `noexec,nosuid` restrictions
- **Capability dropping**: All Linux capabilities removed with `--cap-drop ALL`
- **Resource limits**: Configurable memory and CPU constraints (default: 512MB, 1.0 CPU)
- **Privilege prevention**: `--security-opt no-new-privileges`
- **Automatic cleanup**: Containers are automatically removed on shutdown or failure

### Using Docker

```r
library(replr)

# Check if Docker is available
is_docker_available()  # TRUE if Docker is present

# Enable Docker mode explicitly
options(replr.use.docker = TRUE)

# Create session with Docker worker
session <- RREPLSession$new(timeout = 15)  # Longer timeout for Docker startup
result <- session$execute("2 + 2")
session$stop()

# Clean up any orphaned containers
cleanup_docker_containers()
```

### Docker Requirements

For Docker support, you need:
- Docker installed and accessible
- Permission to run `docker` commands
- Internet access for initial image build (pulls `rocker/r-ver:4.4`)

The package automatically:
1. Detects Docker availability
2. Builds the minimal worker image on first use

### Security Model

Docker containers provide an additional layer of security beyond process isolation:

| Security Layer | Native | Docker |
|----------------|--------|--------|
| Process isolation | ✅ | ✅ |
| Memory separation | ✅ | ✅ |
| Filesystem isolation | ❌ | ✅ |
| Network communication | Direct | Port-mapped |
| Capability restrictions | ❌ | ✅ |
| Resource limits | ❌ | ✅ |
| Automatic cleanup | ❌ | ✅ |

### Docker Configuration

You can customize Docker worker behavior using global options:

| Option | Default | Description |
|--------|---------|-------------|
| `replr.use.docker` | `FALSE` | Enable/disable Docker mode |
| `replr.worker.docker.image` | `"replr-worker:latest"` | Docker image name for worker containers |
| `replr.worker.docker.memory` | `"512m"` | Memory limit for Docker containers (e.g., "1g", "256m") |
| `replr.worker.docker.cpus` | `"1.0"` | CPU limit for Docker containers (e.g., "2.0", "0.5") |
| `replr.worker.docker.network.isolation` | `FALSE` | Enable isolated Docker networks with no external access |

These options apply to all Docker workers started after they are set. Changes take effect immediately for new worker processes.

```r
# Configure Docker image name (default: "replr-worker:latest")
options(replr.worker.docker.image = "my-custom-r-image:v1.0")

# Configure memory limit (default: "512m")
options(replr.worker.docker.memory = "1g")      # 1GB memory
options(replr.worker.docker.memory = "256m")    # 256MB memory

# Configure CPU limit (default: "1.0")
options(replr.worker.docker.cpus = "2.0")       # 2 CPU cores
options(replr.worker.docker.cpus = "0.5")       # Half a CPU core

# Reset to defaults
options(replr.worker.docker.image = NULL)
options(replr.worker.docker.memory = NULL)
options(replr.worker.docker.cpus = NULL)

# Example: Configure for high-performance workloads
options(
  replr.worker.docker.memory = "2g",
  replr.worker.docker.cpus = "4.0"
)

# Enable network isolation
options(
  replr.worker.docker.network.isolation = TRUE
)

# Start session with custom settings
session <- RREPLSession$new()
```

### Network Isolation

Network isolation provides:
- **No external network access** - Worker cannot connect to internet or external services
- **Isolated bridge network** - Each worker gets its own private network
- **Port-only communication** - Only the worker port is exposed to the host
- **Automatic cleanup** - Networks are removed when workers stop

This matches the security model of Docker Compose's `internal: true` network configuration.

## ellmer Tools for LLM Agents

`replr` includes specialized tools designed for the [ellmer](https://ellmer.tidyverse.org/) package, allowing LLM agents to easily create and manage isolated R REPL sessions. These tools provide a standardized interface with structured responses optimized for LLM consumption.

## Examples

The package includes several demonstration scripts in `inst/examples/`:

### LLM Agent Demo (`llm-agent-demo.R`)

Complete demonstration of an LLM agent performing data analysis using replr tools.

```r
# Install requirements
install.packages(c("replr", "ellmer"))

# Set your API key (required)
Sys.setenv(OPENAI_API_KEY = "your-api-key-here")

# Run the demo
source(system.file("examples", "llm-agent-demo.R", package = "replr"))
```

The demo shows:
1. Initializing an OpenAI chat session with replr tools
2. Registering all replr tools with the LLM agent
3. Sending a data analysis task to the agent
4. Watching the agent automatically create sessions, execute code, and clean up
5. Displaying the complete analysis results and tool usage

### Docker Integration Demo (`docker-integration-demo.R`)

Shows how to use replr with Docker containers for enhanced isolation:

```r
source(system.file("examples", "docker-integration-demo.R", package = "replr"))
```

Demonstrates:
- Checking Docker availability
- Creating sessions with automatic Docker detection
- Executing code in Docker containers
- Session cleanup

### Agentic Coding Evaluation (`agentic-coding.R`)

Compares LLM performance with and without replr tool access:

```r
source(system.file("examples", "agentic-coding.R", package = "replr"))
```

Features:
- Side-by-side comparison of vanilla vs. tool-augmented chat
- Automated evaluation using a judge LLM
- Demonstrates benefit of code execution tools for complex computational tasks

## Development and Testing

This package has comprehensive test coverage and follows R package development best practices:

```r
# Development workflow
devtools::load_all()      # Load package for testing
devtools::test()          # Run all tests (42 test cases)
devtools::check()         # R CMD check (passes cleanly)
devtools::document()      # Generate documentation

# Current test status: ✅ 42 test cases passing, 0 errors/warnings
# Note: Test suite includes comprehensive plot capture validation with PNG comparison
# Note: Includes Docker container functionality tests and debug log capture tests
```

## License

MIT License - see LICENSE file for details.
