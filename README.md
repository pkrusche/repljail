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

## Installation

You can install the development version of replr like so:

``` r
# install.packages("devtools")
devtools::install_github("pkrusche/replr")

# Required dependencies will be installed automatically:
# nanonext, processx, evaluate, R6, uuid, cli
```

## Quick Start

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

### Core Functions

- **`start_worker(port = NULL, timeout = 10)`** - Start an isolated R worker process
- **`send_command(worker_info, code, timeout = 30)`** - Execute R code in worker 
- **`stop_worker(worker_info, timeout = 5)`** - Gracefully stop worker process

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
devtools::test()          # Run all tests (74 tests)
devtools::check()         # R CMD check (passes cleanly)  
devtools::document()      # Generate documentation

# Current test status: ✅ 74 tests passing, 0 errors/warnings
```

### Architecture Notes

- **Functional API**: Uses `start_worker()` / `send_command()` / `stop_worker()` pattern rather than R6 classes
- **Process-based isolation**: True isolation via separate R processes, not just environments
- **Robust communication**: Built on `nanonext` for reliable messaging with automatic serialization
- **Error resilience**: Workers survive crashes and continue processing requests
- **Cross-platform**: Works on Windows, macOS, and Linux

## License

MIT License - see LICENSE file for details.
