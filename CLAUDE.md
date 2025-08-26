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
install.packages(c("nanonext", "processx", "evaluate", "R6", "uuid", "here"))

# Optional packages
install.packages(c("pryr", "jsonlite"))
```

## API Reference

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
