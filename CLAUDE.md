# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# repljail - Isolated R REPL

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

### Isolation Methods

The package supports multiple sandboxing/isolation strategies:

**Docker Support**
```r
# Check Docker availability
is_docker_available()

# Clean up orphaned Docker containers
cleanup_docker_containers()

# Clean up orphaned Docker networks
cleanup_docker_networks()

# Enable Docker mode for workers
options(repljail.worker.type = "docker")

# Enable network isolation (requires Docker mode)
options(repljail.worker.docker.network.isolation = TRUE)
```

**Firejail Support (Linux)**
```r
# Check Firejail availability
is_firejail_available()

# Enable Firejail mode for workers
options(repljail.worker.type = "firejail")

# Use custom Firejail profile (optional)
options(repljail.worker.firejail.profile = "/path/to/profile.profile")
```

**macOS Sandbox Support (macOS only)**
```r
# Check macOS sandbox availability
is_macos_sandbox_available()

# Enable macOS sandbox mode for workers
options(repljail.worker.type = "macos-sandbox")

# Use custom sandbox profile (optional)
options(repljail.worker.macos.sandbox.profile = "/path/to/profile.sb")
```

**Worker Type Selection**: Set `repljail.worker.type` to one of: `"native"`, `"docker"`, `"firejail"`, or `"macos-sandbox"` (default: `"native"`)

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

1. **Controller Process** (`R/session.R`, `R/utils.R`, `R/communication.R`, `R/worker-wrappers.R`)
   - Main R session managing worker lifecycle
   - Two interfaces: Functional API (start_worker/send_command/stop_worker) and R6 class (RREPLSession)
   - Handles socket communication and process monitoring
   - Supports multiple isolation methods: Native processes, Docker containers, Firejail sandboxes (Linux), and macOS sandboxes (macOS)

2. **Worker Process** (`inst/worker.R`)
   - Isolated R session executing code using `evaluate` package
   - Runs as separate process (native, Firejail sandbox, macOS sandbox, or Docker container)
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
- **R/worker-wrappers.R**: Worker wrapper implementations (NativeWorkerWrapper, DockerWorkerWrapper, FirejailWorkerWrapper, MacOSSandboxWorkerWrapper)
- **R/communication.R**: Socket management (create_req_socket, send_request, close_socket)
- **R/debug.R**: Debug logging system using `cli` package
- **R/ellmer-tools.R**: LLM agent tools for ellmer integration (session management, structured responses)
- **R/conversation-logger.R**: Conversation logging system for ellmer chat sessions (markdown format)
- **inst/worker.R**: Worker script that runs in isolated process, handles code evaluation

### Worker Process Details
- Located at `inst/worker.R` (or system.file("worker.R", package = "repljail") when installed)
- Started with: `Rscript worker.R <port> [--debug] [--listen-all]`
- Uses `evaluate::evaluate()` with `stop_on_error = 2` (continues after errors)
- Plots captured via `recordedplot` objects, converted to base64 PNG data URLs
- Non-blocking message loop allows graceful shutdown via "__SHUTDOWN__" message

### Docker Integration
- Dockerfile in `inst/Dockerfile` based on `rocker/r-ver:4.4`
- Security features: non-root user, read-only filesystem, capability dropping, memory/CPU limits
- Container naming: `repljail-worker-<port>-<timestamp>` for cleanup tracking
- Configurable via options: `repljail.worker.docker.image`, `repljail.worker.docker.memory`, `repljail.worker.docker.cpus`
- **Network Isolation (Sidecar Pattern)**: Optional air-gapped execution with `repljail.worker.docker.network.isolation`
  - Creates `--internal` bridge network (blocks all outbound traffic including internet)
  - Worker container: Connected to isolated network only (zero internet access)
  - Gateway sidecar: `alpine/socat` container that bridges host ↔ worker communication
  - Architecture:
    ```
    Host (127.0.0.1:<port>) ← Docker publish → Gateway Container ← Internal Network → Worker Container (air-gapped)
    ```
  - Network naming: `repljail-network-<port>-<timestamp>`
  - Gateway naming: `repljail-gateway-<port>-<timestamp>`
  - Automatic cleanup of worker, gateway, and network when session stops
  - Security: Worker has ZERO external network access while host communication works via gateway proxy

### Firejail Integration (Linux)
- Lightweight sandboxing for Linux systems using firejail
- Implemented in `R/worker-wrappers.R` via `FirejailWorkerWrapper` R6 class
- Availability detection: `is_firejail_available()` checks for firejail command
- Configurable via options: `repljail.worker.type = "firejail"`, `repljail.worker.firejail.profile`
- **Default Security Settings**:
  - Network isolation: `--net=lo` (loopback only, blocks external access)
  - Filesystem isolation: `--private-tmp` (isolated temp directory)
  - Capability dropping: `--caps.drop=all` (drop all Linux capabilities)
  - Seccomp filtering: `--seccomp` (restrict system calls)
  - No privilege escalation: `--nonewprivs`, `--noroot`
  - Hardware restrictions: `--nosound`, `--novideo`, `--no3d`, `--nodvd`, `--notv`
- **Custom Profiles**: Support for custom firejail profile files via `repljail.worker.firejail.profile` option
- **Process Management**: Worker executed as `firejail [options] Rscript worker.R <port>`
- **Tests**: `tests/testthat/test-firejail.R` (skipped on CI and non-Linux systems)
- **Demo**: `inst/examples/firejail-demo.R` shows complete usage

### macOS Sandbox Integration (macOS)
- Native sandboxing for macOS using Apple's `sandbox-exec` command
- Implemented in `R/worker-wrappers.R` via `MacOSSandboxWorkerWrapper` R6 class
- Availability detection: `is_macos_sandbox_available()` checks for macOS and sandbox-exec command
- Configurable via options: `repljail.worker.type = "macos-sandbox"`, `repljail.worker.macos.sandbox.profile`
- **Default Security Profile** (auto-generated using Sandbox Profile Language):
  - **Filesystem access**:
    - Read: All files (allows R to read system files, libraries, data)
    - Write: Only `/tmp`, `/private/tmp`, `/var/tmp` and `.Rtmp*` directories
    - Blocked: Home directory writes (except temp directories)
  - **Network access**:
    - Allowed: Localhost only (for IPC with host process)
    - Blocked: All outbound external network access
  - **Other operations**: Allows process execution, IPC, and system calls needed for R to function
  - **Implementation**: Uses `(allow default)` with specific denials for network-outbound and home directory writes
- **Custom Profiles**: Support for custom `.sb` profile files using Sandbox Profile Language (SBPL)
- **Profile Management**: Default profiles auto-generated at runtime, temporary profiles cleaned up via finalizer
- **Process Management**: Worker executed as `sandbox-exec -f <profile> Rscript worker.R <port>`
- **Tests**: `tests/testthat/test-macos-sandbox.R` (skipped on CI and non-macOS systems)
- **Demo**: `inst/examples/macos-sandbox-demo.R` shows complete usage
- **SBPL Resources**: `man sandbox-exec`, Apple Sandbox Guide, `/System/Library/Sandbox/Profiles/`

### ellmer Integration
- Functions in `R/ellmer-tools.R` provide LLM agent tools for the ellmer package
- Global session registry (`.repljail_sessions`) tracks active sessions across tool calls
- Auto-generated session IDs: `<color>-<animal>-<number>` (e.g., "red-eagle-742")
- All tools return standardized responses: `list(success, message, data, error)`
- Plot handling: Converts base64 plots to temporary PNG files for LLM consumption
- Demo: `inst/examples/llm-agent-demo.R` shows complete LLM agent workflow

### Conversation Logging
- `R/conversation-logger.R` provides markdown-formatted logging for ellmer chat sessions
- `ConversationLogger` R6 class attaches to ellmer Chat objects via callbacks
- Logs captured in markdown format with:
  - User prompts and assistant responses
  - Tool calls with R code formatted in markdown code blocks
  - Tool results with output, warnings, errors, and execution time
  - Timestamp tracking for each turn
- Usage:
  ```r
  # Create and attach logger
  logger <- create_conversation_logger(log_file = "chat.md", auto_save = TRUE)
  logger$attach(chat)

  # Chat normally - logging happens automatically
  chat$chat("Analyze this data...")

  # Access or save log
  logger$save()  # or logger$get_log()
  ```
- Demo: `inst/examples/conversation-logging-demo.R` shows complete logging workflow
- Tests: `tests/testthat/test-conversation-logger.R` with mock Chat objects

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
1. **Start**: `start_worker()` spawns worker via appropriate wrapper (native Rscript, Firejail sandbox, macOS sandbox, or Docker container), waits for readiness via ping test
2. **Execute**: `send_command()` creates REQ socket, sends code, receives response, closes socket
3. **Stop**: `stop_worker()` sends "__SHUTDOWN__" message, then SIGINT, then force kill if needed
4. **Cleanup**:
   - Docker: Container removed via `docker rm -f`, network/gateway cleanup if using network isolation
   - Firejail/macOS Sandbox: Process termination via processx cleanup
   - macOS Sandbox: Temporary profile files cleaned up via finalizer

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

Test suite in `tests/testthat/`:
- **test-session.R**: RREPLSession R6 class functionality
- **test-worker.R**: Worker process communication
- **test-end-to-end.R**: Full execution workflows
- **test-plots.R**: Plot capture with PNG comparison against reference images
- **test-docker.R**: Docker container functionality (skipped if Docker unavailable)
- **test-firejail.R**: Firejail sandbox functionality (skipped on CI and non-Linux systems)
- **test-macos-sandbox.R**: macOS sandbox functionality (skipped on CI and non-macOS systems)
- **test-ellmer-tools.R**: LLM agent tool interfaces
- **test-conversation-logger.R**: Conversation logging with mock Chat objects
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

**General:**
- `repljail.debug` (logical): Enable debug logging

**Worker Type Selection:**
- `repljail.worker.type` (string): Worker isolation method - one of "native", "docker", "firejail", "macos-sandbox" (default: "native")
  - Legacy boolean options (`repljail.use.docker`, `repljail.use.firejail`, `repljail.use.macos.sandbox`) are deprecated but supported with warnings

**Docker Configuration:**
- `repljail.worker.docker.image` (string): Docker image name (default: "repljail-worker:latest")
- `repljail.worker.docker.memory` (string): Memory limit (default: "512m")
- `repljail.worker.docker.cpus` (string): CPU limit (default: "1.0")
- `repljail.worker.docker.network.isolation` (logical): Enable isolated Docker networks (default: FALSE)

**Firejail Configuration:**
- `repljail.worker.firejail.profile` (string): Path to custom firejail profile file (default: NULL)

**macOS Sandbox Configuration:**
- `repljail.worker.macos.sandbox.profile` (string): Path to custom sandbox profile (.sb) file (default: NULL)
- to memorize : when testing scripts and examples, always use devtools::load_all() and source from within an R session instead of using Rscript