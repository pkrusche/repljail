# replr

**Isolated REPL functionality for R**

`replr` provides a robust system for executing R code in isolated worker processes, offering complete separation between the main R session and code execution environments. Perfect for applications that need to run untrusted or potentially problematic R code without affecting the parent process.

## ✨ Key Features

- **🔒 Process Isolation**: Complete memory separation using separate R worker processes
- **🐳 Docker Support**: Optional Docker container execution with security hardening
- **⚡ Robust Communication**: Built on `nanonext` for reliable inter-process messaging
- **📊 Rich Output Capture**: Captures console output, warnings, errors, and plots via `evaluate`
- **🔄 Error Recovery**: Workers survive errors and continue processing requests
- **⏱️ Configurable Timeouts**: Per-execution and session-level timeout controls
- **🐛 Debug Logging**: Beautiful CLI-styled debug output with configurable verbosity
- **🌐 Cross-Platform**: Works on Windows, macOS, and Linux
- **🎯 Multiple Workers**: Run concurrent isolated sessions simultaneously
- **🔗 R6 Class Interface**: Object-oriented interface with automatic cleanup

## Installation

You can install the development version of replr like so:

``` r
# install.packages("devtools")
devtools::install_github("pkrusche/replr")

# Required dependencies will be installed automatically:
# nanonext, processx, evaluate, R6, uuid, cli
```

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

## Detailed Usage Examples

### Basic Code Execution

```r
library(replr)

# Create a session
session <- RREPLSession$new()

# Execute simple expressions
result1 <- session$execute("1 + 1")
print(result1$status)           # [1] "success"
print(result1$result$output)    # [1] "[1] 2"
print(result1$execution_time)   # execution time in seconds

# Execute more complex code
result2 <- session$execute("
  data <- data.frame(
    x = 1:5,
    y = letters[1:5]
  )
  summary(data)
")
print(result2$result$output)

# Clean up
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

session$stop()
```

### Working with Warnings

```r
library(replr)

session <- RREPLSession$new()

# Code that generates warnings
result <- session$execute("
  warning('This is a warning')
  42
")

print(result$status)             # [1] "success"
print(result$result$warnings)    # [1] "This is a warning"
print(result$result$output)      # [1] "[1] 42"

session$stop()
```

### R6 Session Management

The `RREPLSession` R6 class provides a convenient object-oriented interface with automatic resource management:

```r
library(replr)

# Create a new session (automatically starts worker)
session <- RREPLSession$new()

# Execute code using the object
result1 <- session$execute("x <- 10")
result2 <- session$execute("x * 2")
print(result2$result$output)  # [1] "[1] 20"

# Access session information
session$is_alive()    # TRUE
session$port          # Port number (e.g., 5555)
session$pid           # Process ID
session$started_at    # Start timestamp

# Get detailed session info
info <- session$get_info()
print(info)

# Session automatically cleans up when object is garbage collected
# Or explicitly stop it:
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

### Debug Log Capture

Worker processes capture their debug logs internally, which can be retrieved by the parent process:

```r
library(replr)
enable_debug(TRUE)

# R6 API
session <- RREPLSession$new()
session$execute("plot(1:10)")

# Get logs as character vector for processing
logs <- session$get_debug_logs()

session$stop()
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

## 🐳 Docker Container Support

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

# Start session with custom settings
session <- RREPLSession$new()
```

### Available Options

| Option | Default | Description |
|--------|---------|-------------|
| `replr.use.docker` | `FALSE` | Enable/disable Docker mode |
| `replr.worker.docker.image` | `"replr-worker:latest"` | Docker image name for worker containers |
| `replr.worker.docker.memory` | `"512m"` | Memory limit for Docker containers (e.g., "1g", "256m") |
| `replr.worker.docker.cpus` | `"1.0"` | CPU limit for Docker containers (e.g., "2.0", "0.5") |

These options apply to all Docker workers started after they are set. Changes take effect immediately for new worker processes.

## API Reference

### RREPLSession R6 Class

- **`RREPLSession$new(port = NULL, timeout = 10)`** - Create new session
- **`session$execute(code, timeout = 30)`** - Execute R code
- **`session$is_alive()`** - Check if worker process is running
- **`session$stop(timeout = 5)`** - Stop the session
- **`session$get_info()`** - Get session information
- **`session$get_debug_logs()`** - Retrieve debug logs from worker process
- **`session$port`** - Active binding for port number
- **`session$pid`** - Active binding for process ID
- **`session$started_at`** - Active binding for start timestamp
- **`session$is_docker`** - Active binding for Docker status

### Utility Functions

- **`is_docker_available()`** - Check if Docker is available on the system
- **`cleanup_docker_containers()`** - Clean up any orphaned replr Docker containers
- **`check_dependencies()`** - Verify that all required packages are available

### Debug Functions

- **`enable_debug(enable = TRUE)`** - Enable/disable debug logging
- **`debug_status()`** - Check current debug logging status

### Response Structure

All `session$execute()` calls return a structured response:

```r
list(
  id = "unique_request_id",
  status = "success",  # "success", "error", or "timeout"
  result = list(
    output = character(),      # Console output lines
    warnings = character(),    # Warning messages
    errors = character(),      # Error messages
    visible = logical(1),      # Whether result should be printed
    plots = list()             # Plot objects (if any)
  ),
  execution_time = numeric(1)  # Execution time in seconds
)
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

## 🤖 ellmer Tools for LLM Agents

`replr` includes specialized tools designed for the [ellmer](https://ellmer.tidyverse.org/) package, allowing LLM agents to easily create and manage isolated R REPL sessions. These tools provide a standardized interface with structured responses optimized for LLM consumption.

### Examples

The package includes several demonstration scripts in `inst/examples/`:

#### LLM Agent Demo (`llm-agent-demo.R`)

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

#### Docker Integration Demo (`docker-integration-demo.R`)

Shows how to use replr with Docker containers for enhanced isolation:

```r
source(system.file("examples", "docker-integration-demo.R", package = "replr"))
```

Demonstrates:
- Checking Docker availability
- Creating sessions with automatic Docker detection
- Executing code in Docker containers
- Session cleanup

#### Agentic Coding Evaluation (`agentic-coding.R`)

Compares LLM performance with and without replr tool access:

```r
source(system.file("examples", "agentic-coding.R", package = "replr"))
```

Features:
- Side-by-side comparison of vanilla vs. tool-augmented chat
- Automated evaluation using a judge LLM
- Demonstrates benefit of code execution tools for complex computational tasks

### Response Format

All tools return standardized responses:

```r
list(
  success = TRUE/FALSE,           # Operation success status
  message = "descriptive text",   # Human-readable message
  data = list(...),              # Operation-specific data
  error = "error details"        # Error information (if applicable)
)
```

## Development Environment

This repository includes a custom GitHub Copilot environment with R and all required packages pre-installed. The environment is configured using:

- **Dev Container**: `.devcontainer/` directory with Docker configuration
- **GitHub Codespaces**: Optimized settings for cloud development
- **Pre-installed packages**: All dependencies ready for immediate use

### Quick Start with Codespaces

1. Click "Code" → "Open with Codespaces" → "New codespace"
2. Wait for the environment to build (first time takes ~5-10 minutes)
3. Start developing with R and all dependencies ready!

## Contributing

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
