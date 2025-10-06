# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# replr - Isolated R REPL

Process-based isolated R REPL implementation that provides secure, sandboxed R code execution using separate worker processes. Designed for running untrusted or potentially problematic R code without affecting the parent process.

## Development Commands

### Testing
```r
# Load package for development
devtools::load_all()

# Run all tests
devtools::test()

# Run specific test file
devtools::test_active_file("tests/testthat/test-session.R")

# Run R CMD check (comprehensive package validation)
devtools::check()

# Generate documentation from roxygen comments
devtools::document()
```

### Docker Support
```r
# Check Docker availability
is_docker_available()

# Clean up orphaned Docker containers
cleanup_docker_containers()

# Clean up orphaned Docker networks
cleanup_docker_networks()

# Enable Docker mode for workers
options(replr.use.docker = TRUE)

# Enable network isolation (requires Docker mode)
options(replr.worker.docker.network.isolation = TRUE)
```

### Debug Logging
```r
# Enable debug logging
enable_debug(TRUE)

# Check debug status
debug_status()

# Disable debug logging
enable_debug(FALSE)
```

## Architecture Overview

The system consists of two main components communicating via `nanonext` sockets:

1. **Controller Process** (`R/session.R`, `R/utils.R`, `R/communication.R`)
   - Main R session managing worker lifecycle
   - Two interfaces: Functional API (start_worker/send_command/stop_worker) and R6 class (RREPLSession)
   - Handles socket communication and process monitoring
   - Supports both native processes and Docker containers

2. **Worker Process** (`inst/worker.R`)
   - Isolated R session executing code using `evaluate` package
   - Runs as separate process (native or Docker container)
   - REP socket listener that processes requests in a loop
   - Captures output, warnings, errors, and plots (as base64-encoded PNGs)

```
Main R Process (Controller) ←──nanonext REQ/REP──→ Worker R Process (inst/worker.R)
  ├─ RREPLSession (R6)                                 ├─ evaluate package
  ├─ start_worker()                                    ├─ Output capture
  ├─ send_command()                                    └─ Plot rendering
  └─ stop_worker()
```

## Key Components

### Core Files
- **R/session.R**: `RREPLSession` R6 class with automatic cleanup via finalizers
- **R/utils.R**: Worker lifecycle management (start_worker, send_command, stop_worker), Docker integration, port allocation
- **R/communication.R**: Socket management (create_req_socket, send_request, close_socket)
- **R/debug.R**: Debug logging system using `cli` package
- **R/ellmer-tools.R**: LLM agent tools for ellmer integration (session management, structured responses)
- **inst/worker.R**: Worker script that runs in isolated process, handles code evaluation

### Worker Process Details
- Located at `inst/worker.R` (or system.file("worker.R", package = "replr") when installed)
- Started with: `Rscript worker.R <port> [--debug] [--listen-all]`
- Uses `evaluate::evaluate()` with `stop_on_error = 2` (continues after errors)
- Plots captured via `recordedplot` objects, converted to base64 PNG data URLs
- Non-blocking message loop allows graceful shutdown via "__SHUTDOWN__" message

### Docker Integration
- Dockerfile in `inst/Dockerfile` based on `rocker/r-ver:4.4`
- Security features: non-root user, read-only filesystem, capability dropping, memory/CPU limits
- Container naming: `replr-worker-<port>-<timestamp>` for cleanup tracking
- Configurable via options: `replr.worker.docker.image`, `replr.worker.docker.memory`, `replr.worker.docker.cpus`
- **Network Isolation (Sidecar Pattern)**: Optional air-gapped execution with `replr.worker.docker.network.isolation`
  - Creates `--internal` bridge network (blocks all outbound traffic including internet)
  - Worker container: Connected to isolated network only (zero internet access)
  - Gateway sidecar: `alpine/socat` container that bridges host ↔ worker communication
  - Architecture:
    ```
    Host (127.0.0.1:<port>) ← Docker publish → Gateway Container ← Internal Network → Worker Container (air-gapped)
    ```
  - Network naming: `replr-network-<port>-<timestamp>`
  - Gateway naming: `replr-gateway-<port>-<timestamp>`
  - Automatic cleanup of worker, gateway, and network when session stops
  - Security: Worker has ZERO external network access while host communication works via gateway proxy

### ellmer Integration
- Functions in `R/ellmer-tools.R` provide LLM agent tools for the ellmer package
- Global session registry (`.replr_sessions`) tracks active sessions across tool calls
- Auto-generated session IDs: `<color>-<animal>-<number>` (e.g., "red-eagle-742")
- All tools return standardized responses: `list(success, message, data, error)`
- Plot handling: Converts base64 plots to temporary PNG files for LLM consumption
- Demo: `inst/examples/llm-agent-demo.R` shows complete LLM agent workflow

## Response Format

All code execution returns structured results:
```r
list(
  id = "unique_request_id",
  status = "success" | "error" | "timeout",
  result = list(
    output = character(),      # Console output
    warnings = character(),    # Warning messages
    errors = character(),      # Error messages
    visible = logical(1),      # Whether result should print
    plots = list()             # Base64-encoded PNG data URLs
  ),
  execution_time = numeric(1)  # Seconds
)
```

## Important Implementation Details

### Process Lifecycle
1. **Start**: `start_worker()` spawns Rscript or Docker container, waits for readiness via ping test
2. **Execute**: `send_command()` creates REQ socket, sends code, receives response, closes socket
3. **Stop**: `stop_worker()` sends "__SHUTDOWN__" message, then SIGINT, then force kill if needed
4. **Docker cleanup**: Container removed via `docker rm -f` in stop_worker()

### Socket Communication
- Each execution creates a new REQ socket connection (not persistent)
- Socket URLs: `tcp://127.0.0.1:<port>` (native) or `tcp://*:<port>` (Docker with --listen-all)
- Built-in serialization via nanonext handles R objects automatically
- Timeout handling at socket level with `timeout` parameter

### Error Recovery
- Workers survive errors during code execution and continue processing
- Worker crashes detected via `process$is_alive()` check
- Debug logs available via `get_worker_debug_logs()` for troubleshooting
- R6 finalizers ensure cleanup even if session object is garbage collected

### Plot Handling
- Plots captured as `recordedplot` objects from `evaluate`
- Rendered to temporary PNG files with `png()` device
- Encoded to base64 with `base64enc::base64encode()`
- Returned as data URLs: `"data:image/png;base64,<data>"`
- In ellmer tools, converted to temporary file paths for LLM vision models

## Testing

Test suite (42 test cases) in `tests/testthat/`:
- **test-session.R**: RREPLSession R6 class functionality
- **test-worker.R**: Worker process communication
- **test-end-to-end.R**: Full execution workflows
- **test-plots.R**: Plot capture with PNG comparison against reference images
- **test-docker.R**: Docker container functionality (skipped if Docker unavailable)
- **test-ellmer-tools.R**: LLM agent tool interfaces
- **test-debug-integration.R**: Debug logging system
- **helper.R**: Test utilities and shared fixtures

## Version Control Workflow

**IMPORTANT**: Before substantial changes, always run:
```bash
jj new
```

This creates a new Jujutsu revision, allowing easy tracking and reverting of changes. After completing work:
```bash
jj describe -m "Descriptive commit message"
```

## Configuration Options

Global options control package behavior:
- `replr.debug` (logical): Enable debug logging
- `replr.use.docker` (logical): Use Docker containers for workers
- `replr.worker.docker.image` (string): Docker image name (default: "replr-worker:latest")
- `replr.worker.docker.memory` (string): Memory limit (default: "512m")
- `replr.worker.docker.cpus` (string): CPU limit (default: "1.0")
- `replr.worker.docker.network.isolation` (logical): Enable isolated Docker networks (default: FALSE)
