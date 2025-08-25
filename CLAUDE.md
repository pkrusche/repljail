# Isolated R REPL

A process-based isolated R REPL implementation that provides secure, sandboxed R code execution using separate worker processes.

## Overview

This project implements a robust system for executing R code in isolated processes, providing complete separation between the main R session and code execution environments. It's designed for applications that need to run untrusted or potentially problematic R code without affecting the parent process.

## Architecture

The system consists of two main components:

- **Controller Process**: Main R session that manages worker processes and handles communication
- **Worker Process**: Isolated R session that executes code using the `evaluate` package

Communication between processes uses the `nanonext` package with a REQ-REP (request-reply) pattern over TCP sockets.

```
Main R Process → nanonext REQ → Worker R Process (nanonext REP + evaluate)
```

## Key Features

- **True Process Isolation**: Each execution environment runs in a separate R process
- **Robust Communication**: Built on `nanonext` for reliable inter-process messaging
- **Rich Output Capture**: Captures console output, warnings, errors, and plots via `evaluate`
- **Resource Management**: Process lifecycle management with automatic cleanup
- **Error Recovery**: Automatic worker restart on crashes with exponential backoff
- **Configurable Timeouts**: Per-execution and session-level timeout controls
- **Cross-Platform**: Works on Windows, macOS, and Linux

## Dependencies

### Required Packages
- `nanonext` - Inter-process communication
- `processx` - Process spawning and management  
- `evaluate` - Safe R code evaluation with output capture
- `R6` - Object-oriented programming framework
- `uuid` - Unique request ID generation

### Optional Packages
- `pryr` - Memory usage monitoring
- `jsonlite` - Alternative serialization (if needed)

## Installation

```r
# Install required packages
install.packages(c("nanonext", "processx", "evaluate", "R6", "uuid"))

# Optional packages
install.packages(c("pryr", "jsonlite"))
```

## Basic Usage

```r
# Load the package (assuming it's built as a package)
library(isolatedrepl)

# Create a new isolated session
session <- RREPLSession$new()

# Execute R code
result1 <- session$execute("x <- 1:10")
result2 <- session$execute("summary(x)")
result3 <- session$execute("plot(x)")

# Access results
result2$result$output    # Console output
result3$result$plots     # Plot objects
result1$execution_time   # Execution time

# Check if session is alive
session$is_alive()

# Clean shutdown (automatic via finalizer)
session$terminate()
```

## API Reference

### RREPLSession Class

#### Methods

**`$new(timeout = 30)`**
- Creates a new isolated R session
- `timeout`: Default timeout for executions (seconds)

**`$execute(code, timeout = NULL, options = list())`**
- Executes R code in the isolated process
- `code`: R code string to execute
- `timeout`: Execution timeout (uses default if NULL)
- `options`: Additional execution options
- Returns: List with execution results

**`$is_alive()`**
- Checks if the worker process is running
- Returns: Boolean

**`$terminate()`**
- Gracefully shuts down the worker process
- Automatically called by finalizer

**`$kill()`**
- Forcefully terminates the worker process
- Use only when graceful shutdown fails

### Response Format

Execution results are returned as a list with the following structure:

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

## Implementation Details

### Process Management

Worker processes are spawned using `processx::process$new()` with the following configuration:

```r
process$new(
  command = "Rscript",
  args = c("worker.R", port),
  cleanup = TRUE,
  cleanup_tree = TRUE
)
```

### Communication Protocol

Uses `nanonext` REQ-REP sockets with automatic R object serialization:

- **Request**: List containing code, options, and metadata
- **Response**: Structured result with output, errors, and execution info
- **Timeout Handling**: Built-in nanonext timeout mechanisms
- **Error Recovery**: Automatic socket reconnection on failures

### Security Considerations

- **Process Isolation**: Complete memory separation between processes
- **Resource Limits**: Configurable execution timeouts
- **Clean Shutdown**: Proper process cleanup on exit
- **Error Containment**: Worker crashes don't affect controller

**Note**: This provides process-level isolation but does not implement filesystem sandboxing or network restrictions. For high-security environments, consider running in containers.

## File Structure

```
isolatedrepl/
├── R/
│   ├── session.R          # RREPLSession class implementation
│   ├── worker.R           # Worker process script
│   ├── utils.R            # Utility functions
│   └── communication.R    # nanonext communication helpers
├── inst/
│   └── worker.R           # Standalone worker script
├── tests/
│   ├── testthat/
│   │   ├── test-session.R
│   │   ├── test-communication.R
│   │   └── test-integration.R
│   └── testthat.R
├── DESCRIPTION
├── NAMESPACE
└── README.md
```

## Development Workflow

### Phase 1: Basic Infrastructure
1. Implement basic process spawning with `processx`
2. Set up nanonext REQ-REP communication
3. Create minimal worker script with `evaluate` integration
4. Basic session management and cleanup

### Phase 2: Robust Communication
1. Enhanced error handling and recovery
2. Process health monitoring and restart logic
3. Resource management and memory monitoring
4. Comprehensive timeout handling

## Testing

### Unit Tests
```r
# Test communication
test_that("nanonext messaging works", {
  # Test request/response serialization
  # Test timeout handling
  # Test error propagation
})

# Test process management
test_that("worker lifecycle management", {
  # Test process spawning
  # Test graceful shutdown
  # Test forced termination
})
```

### Integration Tests
```r
# Test full workflow
test_that("complete execution workflow", {
  session <- RREPLSession$new()
  result <- session$execute("1 + 1")
  expect_equal(result$status, "success")
  session$terminate()
})
```

### Stress Tests
```r
# Test concurrent sessions
# Test memory-intensive operations  
# Test long-running computations
# Test error recovery scenarios
```

## Performance Characteristics

- **Startup Time**: ~200-500ms per session (R process + nanonext setup)
- **Memory Overhead**: One R process per session (~50-100MB baseline)
- **Execution Overhead**: Minimal (nanonext serialization + process communication)
- **Throughput**: Limited by R execution speed, not communication layer

## Troubleshooting

### Common Issues

**Worker Process Won't Start**
- Check that R is in PATH
- Verify nanonext installation in worker environment
- Check port availability

**Communication Timeouts**
- Increase timeout values for long-running operations
- Check network/firewall settings for local TCP connections
- Monitor worker process memory usage

**Memory Leaks**
- Ensure proper session cleanup with `$terminate()`
- Monitor worker process memory growth
- Consider periodic worker restart for long-running sessions

### Debug Mode

Enable verbose logging:
```r
options(isolatedrepl.debug = TRUE)
session <- RREPLSession$new()
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

[Specify license here]

## Acknowledgments

- `nanonext` package by Charlie Gao for robust messaging
- `processx` package by Gábor Csárdi for process management
- `evaluate` package by Hadley Wickham for safe R code evaluation