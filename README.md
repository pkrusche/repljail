# replr

**Isolated REPL functionality for R**

`replr` provides a robust system for executing R code in isolated worker processes, offering complete separation between the main R session and code execution environments. Useful for applications that need to run untrusted or potentially problematic R code without affecting the parent process.

## Installation

You can install the development version of replr like this:

```r
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

```r
library(replr)

# Create a new isolated R session
session <- RREPLSession$new()

# Execute R code in the isolated process
result <- session$execute("2 + 2")
print(result$result$output)  # [1] "[1] 4"

# Workers survive errors and continue processing
result <- session$execute("stop('error')")  # Returns error status
result <- session$execute("3 + 3")          # Still works!

# Stop the session (or it will auto-cleanup on garbage collection)
session$stop()
```

For detailed examples including error handling, debug logging, multiple sessions, and timeouts, see `vignette("getting-started")`.

## Docker Container Support

`replr` supports running worker processes inside Docker containers for enhanced security and isolation. When Docker is available, it automatically builds a minimal container image and runs workers with stricter security constraints.

For Docker support, you need:

- Docker installed and accessible
- Permission to run `docker` commands
- Internet access for initial image build (pulls `rocker/r-ver:4.4`)

The package automatically:

1. Detects Docker availability
2. Builds the minimal worker image on first use (worker images can be configured also)

### Example

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

See also `inst/examples/docker-integration-demo.R`.

### Docker Security Model

Docker containers can provide an additional layer of security beyond process isolation:

| Security Layer          | Native | Docker      | Network Isolation           |
| ----------------------- | ------ | ----------- | --------------------------- |
| Process isolation       | ✅     | ✅          | ✅                          |
| Memory separation       | ✅     | ✅          | ✅                          |
| Filesystem isolation    | ❌     | ✅          | ✅                          |
| Network communication   | Direct | Port-mapped | Proxied, no external access |
| Capability restrictions | ❌     | ✅          | ✅                          |
| Resource limits         | ❌     | ✅          | ✅                          |
| Automatic cleanup       | ❌     | ✅          | ✅                          |

For detailed architecture and implementation, see `vignette("network-isolation")`.

### Docker Configuration

You can customize Docker worker behavior using global options:

| Option                                  | Default                 | Description                                             |
| --------------------------------------- | ----------------------- | ------------------------------------------------------- |
| `replr.use.docker`                      | `FALSE`                 | Enable/disable Docker mode                              |
| `replr.worker.docker.image`             | `"replr-worker:latest"` | Docker image name for worker containers                 |
| `replr.worker.docker.memory`            | `"512m"`                | Memory limit for Docker containers (e.g., "1g", "256m") |
| `replr.worker.docker.cpus`              | `"1.0"`                 | CPU limit for Docker containers (e.g., "2.0", "0.5")    |
| `replr.worker.docker.network.isolation` | `FALSE`                 | Enable isolated Docker networks with no external access |

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

## ellmer Tools for LLM Agents

`replr` includes specialized tools designed for the [ellmer](https://ellmer.tidyverse.org/) package, allowing LLM agents to easily create and manage isolated R REPL sessions. These tools provide a standardized interface with structured responses optimized for LLM consumption.

### Available Tools

Each tool function has a corresponding `*_tool()` function that returns a tool definition for use with ellmer or other LLM agent frameworks.

The package includes several demonstration scripts in `inst/examples/` for this.

#### Simple One-Off Execution & R Syntax Checking

- **replr_check_syntax()** - Check R code syntax without execution (safe validation)
- **replr_run_r_code()** - One-off code execution with automatic cleanup
- **replr_lint_code()** - Analyze code for style issues without executing it

#### Full Session Management

- **replr_create_repl_session()** - Create isolated R sessions
- **replr_execute_code()** - Execute R code in a session
- **replr_get_session_info()** - Get session status and details
- **replr_list_sessions()** - List all active sessions
- **replr_stop_session()** - Stop a specific session
- **replr_cleanup_sessions()** - Remove dead sessions
- **replr_stop_all_sessions()** - Stop all active sessions

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
covr::report(covr::package_coverage(), file = NULL)
                          # Generate an in-terminal coverage summary
devtools::document()      # Generate documentation
```

## License

MIT License - see LICENSE file for details.
