# replr

**Isolated REPL functionality for R**

`replr` provides a robust system for executing R code in isolated worker processes, offering complete separation between the main R session and code execution environments. Perfect for applications that need to run untrusted or potentially problematic R code without affecting the parent process.

## ✨ Key Features

- **🔒 Process Isolation**: Complete memory separation using separate R worker processes
- **⚡ Robust Communication**: Built on `nanonext` for reliable inter-process messaging
- **📊 Rich Output Capture**: Captures console output, warnings, errors, and plots via `evaluate`
- **🔄 Error Recovery**: Workers survive errors and continue processing requests
- **⏱️ Configurable Timeouts**: Per-execution and session-level timeout controls
- **🐛 Debug Logging**: Beautiful CLI-styled debug output with configurable verbosity
- **🌐 Cross-Platform**: Works on Windows, macOS, and Linux
- **🎯 Multiple Workers**: Run concurrent isolated sessions simultaneously
- **🔗 Dual Interface**: Both functional API and R6 class with automatic cleanup

## Installation

You can install the development version of replr like so:

``` r
# install.packages("devtools")
devtools::install_github("pkrusche/replr")

# Required dependencies will be installed automatically:
# nanonext, processx, evaluate, R6, uuid, cli
```

## Quick Start

### Functional Interface

```r
library(replr)

# Start an isolated R worker process
worker <- start_worker()

# Execute R code in the isolated process
result <- send_command(worker, "2 + 2")
print(result$result$output)  # [1] "4"

# Stop the worker when done
stop_worker(worker)
```

### Object-Oriented Interface (R6 Class)

```r
library(replr)

# Create a new isolated R session
session <- RREPLSession$new()

# Execute R code in the isolated process
result <- session$execute("2 + 2")
print(result$result$output)  # [1] "4"

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

# Start a worker process
worker <- start_worker()

# Execute simple expressions
result1 <- send_command(worker, "1 + 1")
print(result1$status)           # "success"
print(result1$result$output)    # "2"
print(result1$execution_time)   # execution time in seconds

# Execute more complex code
result2 <- send_command(worker, "
  data <- data.frame(
    x = 1:5,
    y = letters[1:5]
  )
  summary(data)
")
print(result2$result$output)

# Clean up
stop_worker(worker)
```

### Error Handling

```r
library(replr)

worker <- start_worker()

# Handle syntax errors
result1 <- send_command(worker, "1 +")
print(result1$status)         # "error"
print(result1$result$errors)  # Error message

# Handle runtime errors
result2 <- send_command(worker, "stop('Custom error')")
print(result2$status)         # "error"
print(result2$result$errors)  # "Custom error"

# Worker continues after errors
result3 <- send_command(worker, "3 * 4")
print(result3$status)         # "success" - worker survived!

stop_worker(worker)
```

### Working with Warnings

```r
library(replr)

worker <- start_worker()

# Code that generates warnings
result <- send_command(worker, "
  warning('This is a warning')
  42
")

print(result$status)             # "success"
print(result$result$warnings)    # "This is a warning"
print(result$result$output)      # "42"

stop_worker(worker)
```

### Object-Oriented Interface with RREPLSession

The `RREPLSession` R6 class provides a more convenient object-oriented interface with automatic resource management:

```r
library(replr)

# Create a new session (automatically starts worker)
session <- RREPLSession$new()

# Execute code using the object
result1 <- session$execute("x <- 10")
result2 <- session$execute("x * 2")
print(result2$result$output)  # "20"

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

#### Benefits of the R6 Interface

- **Automatic cleanup**: Sessions are automatically stopped when the object is garbage collected
- **Cleaner syntax**: Object-oriented method calls instead of passing worker info around
- **Better encapsulation**: All session state is contained within the object
- **Active bindings**: Easy access to session properties like `port`, `pid`, `started_at`

```r
# Multiple independent sessions
session1 <- RREPLSession$new()
session2 <- RREPLSession$new()

# Each has its own isolated environment
session1$execute("x <- 100")
session2$execute("x <- 200")

session1$execute("x")  # Returns 100
session2$execute("x")  # Returns 200

# Clean up both
session1$stop()
session2$stop()
```

### Debug Logging

```r
library(replr)

# Enable beautiful debug logging
enable_debug(TRUE)

# Now see detailed colored output of what's happening
worker <- start_worker()  # Shows startup debug messages

result <- send_command(worker, "sqrt(16)")  # Shows communication debug

stop_worker(worker)  # Shows cleanup debug

# Disable debug logging
enable_debug(FALSE)

# Check current debug status
debug_status()
```

### Multiple Concurrent Workers

```r
library(replr)

# Start multiple isolated workers
worker1 <- start_worker()
worker2 <- start_worker()

# They run on different ports and are completely isolated
print(worker1$port)  # e.g., 5555
print(worker2$port)  # e.g., 5556

# Set different variables in each worker
send_command(worker1, "my_var <- 'Worker 1'")
send_command(worker2, "my_var <- 'Worker 2'")

# Verify isolation - each worker only sees its own variables
result1 <- send_command(worker1, "my_var")
result2 <- send_command(worker2, "my_var")

print(result1$result$output)  # "Worker 1"
print(result2$result$output)  # "Worker 2"

# Clean up both workers
stop_worker(worker1)
stop_worker(worker2)
```

### Advanced Usage with Timeouts

```r
library(replr)

worker <- start_worker()

# Set custom timeout for long-running operations
result <- send_command(
  worker,
  "Sys.sleep(2); 'Completed'",
  timeout = 5  # 5 second timeout
)
print(result$result$output)  # "Completed"

# This would timeout:
# result <- send_command(worker, "Sys.sleep(10)", timeout = 2)

stop_worker(worker)
```

## API Reference

### Core Functions (Functional Interface)

- **`start_worker(port = NULL, timeout = 10)`** - Start an isolated R worker process
- **`send_command(worker_info, code, timeout = 30)`** - Execute R code in worker
- **`stop_worker(worker_info, timeout = 5)`** - Gracefully stop worker process

### RREPLSession R6 Class (Object-Oriented Interface)

- **`RREPLSession$new(port = NULL, timeout = 10)`** - Create new session
- **`session$execute(code, timeout = 30)`** - Execute R code
- **`session$is_alive()`** - Check if worker process is running
- **`session$stop(timeout = 5)`** - Stop the session
- **`session$get_info()`** - Get session information
- **`session$port`** - Active binding for port number
- **`session$pid`** - Active binding for process ID
- **`session$started_at`** - Active binding for start timestamp

### Debug Functions

- **`enable_debug(enable = TRUE)`** - Enable/disable debug logging
- **`debug_status()`** - Check current debug logging status

### Response Structure

All `send_command()` calls return a structured response:

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
│ • start_worker  │                 │ • evaluate pkg  │
│ • send_command  │     TCP         │ • plot capture  │
│ • stop_worker   │   Socket        │ • error handling│
└─────────────────┘                 └─────────────────┘
```

1. **Isolation**: Each worker runs as a separate R process with its own memory space
2. **Communication**: Uses `nanonext` REQ-REP pattern over TCP sockets for reliability
3. **Evaluation**: Workers use the `evaluate` package for safe code execution with rich output capture
4. **Error Recovery**: Workers survive errors and continue processing new requests
5. **Resource Management**: Automatic cleanup with proper process lifecycle management

## Use Cases

- **🤖 AI/LLM Integration**: Safe execution of AI-generated R code
- **🔬 Interactive Analysis**: Isolated environments for experimental code
- **🎓 Educational Tools**: Safe execution of student code submissions
- **☁️ Cloud Services**: Secure R code execution in multi-tenant environments
- **🧪 Testing Frameworks**: Isolated test environments that don't pollute the main session
- **📊 Report Generation**: Isolated rendering without affecting the main analysis
- **🤖 ellmer Integration**: Specialized tools for LLM agents to create and manage REPL sessions

## ellmer Tools for LLM Agents

`replr` includes specialized tools designed for the ellmer package, allowing LLM agents to easily create and manage isolated R REPL sessions. These tools provide a standardized interface with structured responses optimized for LLM consumption.

### ellmer Tools Overview

The ellmer tools provide session management with automatic cleanup and structured responses:

```r
# Create a new REPL session for an LLM agent
result <- replr_create_repl_session()
session_id <- result$data$session_id

# Execute R code in the session
exec_result <- replr_execute_code(session_id, "data <- mtcars; summary(data$mpg)")
if (exec_result$success) {
  cat("Output:", exec_result$data$output)
}

# List all active sessions
sessions <- replr_list_sessions()
cat("Active sessions:", sessions$data$count)

# Clean up when done
replr_stop_session(session_id)
```

### Tool Integration

`replr` provides ellmer-compatible tool definitions that wrap the core functions for LLM agent integration:

```r
# Get ellmer tool definitions
create_tool <- replr_create_repl_session_tool()
execute_tool <- replr_execute_code_tool()
list_tool <- replr_list_sessions_tool()

# Tools provide structured metadata for LLM agents
print(create_tool$name)        # "replr_create_repl_session"
print(create_tool$description) # Tool description
print(create_tool$parameters)  # Parameter schema
```

When ellmer is available, these functions return proper `ellmer::tool()` objects. When ellmer is not installed, they return compatible structures that can still be used programmatically.

### ellmer API Functions

**Core Functions:**
- **`replr_create_repl_session(session_id = NULL, timeout = 10)`** - Create a new isolated REPL session
- **`replr_execute_code(session_id, code, timeout = 30)`** - Execute R code in a session
- **`replr_get_session_info(session_id)`** - Get detailed session information
- **`replr_list_sessions()`** - List all active sessions with their status
- **`replr_stop_session(session_id, timeout = 5)`** - Stop a specific session
- **`replr_cleanup_sessions()`** - Remove dead sessions from registry
- **`replr_stop_all_sessions(timeout = 5)`** - Stop all active sessions

**Tool Definitions:**
- **`replr_create_repl_session_tool()`** - ellmer tool wrapper for session creation
- **`replr_execute_code_tool()`** - ellmer tool wrapper for code execution
- **`replr_get_session_info_tool()`** - ellmer tool wrapper for session info
- **`replr_list_sessions_tool()`** - ellmer tool wrapper for listing sessions
- **`replr_stop_session_tool()`** - ellmer tool wrapper for stopping sessions
- **`replr_cleanup_sessions_tool()`** - ellmer tool wrapper for cleanup
- **`replr_stop_all_sessions_tool()`** - ellmer tool wrapper for stopping all sessions

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

### Multiple Session Management

Tools support multiple concurrent sessions with automatic isolation:

```r
# Create multiple sessions for different analyses
analysis1 <- replr_create_repl_session("data_exploration")
analysis2 <- replr_create_repl_session("model_building")

# Each session maintains its own isolated environment
replr_execute_code("data_exploration", "dataset <- mtcars")
replr_execute_code("model_building", "dataset <- iris")

# Sessions are completely isolated
result1 <- replr_execute_code("data_exploration", "names(dataset)")
result2 <- replr_execute_code("model_building", "names(dataset)")
# result1 shows mtcars columns, result2 shows iris columns

# Clean up all sessions at once
replr_stop_all_sessions()
```

### Error Handling in tools

Tools provide robust error handling while maintaining session stability:

```r
# Execute code that generates an error
error_result <- replr_execute_code(session_id, "stop('Something went wrong')")
# Returns: success = FALSE, data$status = "error", data$errors = ["Something went wrong"]

# Session continues to work after errors
recovery <- replr_execute_code(session_id, "2 + 2")
# Returns: success = TRUE, data$output = "4"
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

### Local Development with Dev Containers

1. Install Docker and VS Code with Dev Containers extension
2. Clone this repository
3. Open in VS Code and select "Reopen in Container"
4. Environment will build automatically with all dependencies

The custom environment includes:
- R 4.3.2 with all dependencies pre-installed
- Development tools: `devtools`, `roxygen2`, `testthat`, `lintr`
- GitHub Copilot extensions enabled

## Contributing

This package has comprehensive test coverage and follows R package development best practices:

```r
# Development workflow
devtools::load_all()      # Load package for testing
devtools::test()          # Run all tests (122 tests)
devtools::check()         # R CMD check (passes cleanly)
devtools::document()      # Generate documentation

# Current test status: ✅ 122 tests passing, 0 errors/warnings
```

### Architecture Notes

- **Dual Interface**: Both functional (`start_worker()` / `send_command()` / `stop_worker()`) AND R6 class (`RREPLSession`)
- **Automatic Cleanup**: R6 class provides finalizers for automatic resource management
- **Process-based isolation**: True isolation via separate R processes, not just environments
- **Robust communication**: Built on `nanonext` for reliable messaging with automatic serialization
- **Error resilience**: Workers survive crashes and continue processing requests
- **Cross-platform**: Works on Windows, macOS, and Linux

## License

MIT License - see LICENSE file for details.
