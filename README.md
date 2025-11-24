# repljail

**Isolated REPL functionality for R**

`repljail` provides a robust system for executing R code in isolated worker processes, offering complete separation between the main R session and code execution environments. Useful for applications that need to run untrusted or potentially problematic R code without affecting the parent process.

## ⚠️ Security Disclaimer

**IMPORTANT:** While `replr` provides various isolation mechanisms (process isolation, Docker containers, Firejail sandboxes, macOS sandboxes) to help contain untrusted code execution, **no security solution is 100% foolproof**. These isolation methods can reduce risk but cannot guarantee complete protection against all attack vectors.

**You are solely responsible for any consequences of running malicious or untrusted code.** The maintainers of this package accept no liability for damages, data loss, security breaches, or other issues arising from the execution of code in isolated environments.

Always exercise caution when executing untrusted code, even in isolated environments. Consider additional security measures appropriate for your use case and threat model.

## Installation

You can install the development version of repljail like this:

```r
install.packages("pak")
pak::pak("pkrusche/repljail")
# Or using devtools:
# install.packages("devtools")
# devtools::install_github("pkrusche/repljail")
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
library(repljail)

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

`repljail` supports running worker processes inside Docker containers for enhanced security and isolation. When Docker is available, it automatically builds a minimal container image and runs workers with stricter security constraints.

For Docker support, you need:

- Docker installed and accessible
- Permission to run `docker` commands
- Internet access for initial image build (pulls `rocker/r-ver:4.4`)

The package automatically:

1. Detects Docker availability
2. Builds the minimal worker image on first use (worker images can be configured also)

### Example

```r
library(repljail)

# Check if Docker is available
is_docker_available()  # TRUE if Docker is present

# Enable Docker mode explicitly
options(repljail.worker.type = "docker")

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
| `repljail.worker.type`                     | `"native"`              | Worker type: "native", "docker", "firejail", "macos-sandbox" |
| `repljail.worker.docker.image`             | `"repljail-worker:latest"` | Docker image name for worker containers                 |
| `repljail.worker.docker.memory`            | `"512m"`                | Memory limit for Docker containers (e.g., "1g", "256m") |
| `repljail.worker.docker.cpus`              | `"1.0"`                 | CPU limit for Docker containers (e.g., "2.0", "0.5")    |
| `repljail.worker.docker.network.isolation` | `FALSE`                 | Enable isolated Docker networks with no external access |

These options apply to all Docker workers started after they are set. Changes take effect immediately for new worker processes.

```r
# Configure Docker image name (default: "repljail-worker:latest")
options(repljail.worker.docker.image = "my-custom-r-image:v1.0")

# Configure memory limit (default: "512m")
options(repljail.worker.docker.memory = "1g")      # 1GB memory
options(repljail.worker.docker.memory = "256m")    # 256MB memory

# Configure CPU limit (default: "1.0")
options(repljail.worker.docker.cpus = "2.0")       # 2 CPU cores
options(repljail.worker.docker.cpus = "0.5")       # Half a CPU core

# Reset to defaults
options(repljail.worker.docker.image = NULL)
options(repljail.worker.docker.memory = NULL)
options(repljail.worker.docker.cpus = NULL)

# Example: Configure for high-performance workloads
options(
  repljail.worker.docker.memory = "2g",
  repljail.worker.docker.cpus = "4.0"
)

# Enable network isolation
options(
  repljail.worker.docker.network.isolation = TRUE
)

# Start session with custom settings
session <- RREPLSession$new()
```

## Firejail Sandboxing Support (Linux)

Lightweight process isolation using firejail for Linux systems. Requires `firejail` installed (e.g., `sudo apt install firejail`).

```r
# Check availability and enable
is_firejail_available()
options(repljail.worker.type = "firejail")

# Create sandboxed session
session <- RREPLSession$new()
result <- session$execute("2 + 2")
session$stop()
```

**Default Security**: Network isolation (`--net=lo`), private temp directory, capability dropping, seccomp filtering, no privilege escalation.

**Custom Profiles**: Set `repljail.worker.firejail.profile` to path of custom `.profile` file. See `inst/examples/` for demonstrations.

## macOS Sandbox Support

Native sandboxing using `sandbox-exec` (pre-installed on macOS). Uses Sandbox Profile Language (SBPL) for comprehensive isolation.

```r
# Check availability and enable
is_macos_sandbox_available()
options(repljail.worker.type = "macos-sandbox")

# Create sandboxed session
session <- RREPLSession$new()
result <- session$execute("2 + 2")
session$stop()
```

**Default Security**: Filesystem isolation (read-only system, write to `/tmp` only), network restricted to localhost, IPC restrictions, system call filtering.

**Custom Profiles**: Set `repljail.worker.macos.sandbox.profile` to path of custom `.sb` file. See `man sandbox-exec` and `inst/examples/macos-sandbox-demo.R`.

## Security Comparison

| Security Layer          | Native | Firejail (Linux) | macOS Sandbox | Docker      |
| ----------------------- | ------ | ---------------- | ------------- | ----------- |
| Process isolation       | ✅     | ✅               | ✅            | ✅          |
| Memory separation       | ✅     | ✅               | ✅            | ✅          |
| Filesystem isolation    | ❌     | ✅               | ✅            | ✅          |
| Network isolation       | ❌     | ✅               | ✅            | ✅          |
| System call filtering   | ❌     | ✅               | ✅            | ✅          |
| Resource limits         | ❌     | ❌               | ❌            | ✅          |
| Platform                | All    | Linux only       | macOS only    | All         |

## Choosing an Isolation Strategy

| Use Case                          | Recommended Strategy           |
| --------------------------------- | ------------------------------ |
| Development/testing               | Native                         |
| Untrusted code (macOS)            | macOS Sandbox                  |
| Untrusted code (Linux)            | Firejail                       |
| Untrusted code (cross-platform)   | Docker                         |
| Maximum security                  | Docker + Network Isolation     |
| Resource limits needed            | Docker                         |

```r
# Development
options(repljail.worker.type = "native")

# Platform-specific sandboxing
options(repljail.worker.type = "macos-sandbox")  # macOS
options(repljail.worker.type = "firejail")       # Linux

# Maximum security (any platform)
options(repljail.worker.type = "docker")
options(repljail.worker.docker.network.isolation = TRUE)

session <- RREPLSession$new()
```

## ellmer Tools for LLM Agents

`repljail` includes specialized tools designed for the [ellmer](https://ellmer.tidyverse.org/) package, allowing LLM agents to easily create and manage isolated R REPL sessions. These tools provide a standardized interface with structured responses optimized for LLM consumption.

### Available Tools

Each tool function has a corresponding `*_tool()` function that returns a tool definition for use with ellmer or other LLM agent frameworks.

The package includes several demonstration scripts in `inst/examples/` for this.

#### Simple One-Off Execution & R Syntax Checking

- **repljail_check_syntax()** - Check R code syntax without execution (safe validation)
- **repljail_run_r_code()** - One-off code execution with automatic cleanup
- **repljail_lint_code()** - Analyze code for style issues without executing it

#### Full Session Management

- **repljail_create_repl_session()** - Create isolated R sessions
- **repljail_execute_code()** - Execute R code in a session
- **repljail_get_session_info()** - Get session status and details
- **repljail_list_sessions()** - List all active sessions
- **repljail_stop_session()** - Stop a specific session
- **repljail_cleanup_sessions()** - Remove dead sessions
- **repljail_stop_all_sessions()** - Stop all active sessions

### LLM Agent Demo (`llm-agent-demo.R`)

Complete demonstration of an LLM agent performing data analysis using repljail tools.

```r
# Install requirements
install.packages(c("repljail", "ellmer"))

# Set your API key (required)
Sys.setenv(OPENAI_API_KEY = "your-api-key-here")

# Run the demo
source(system.file("examples", "llm-agent-demo.R", package = "repljail"))
```

The demo shows:

1. Initializing an OpenAI chat session with repljail tools
2. Registering all repljail tools with the LLM agent
3. Sending a data analysis task to the agent
4. Watching the agent automatically create sessions, execute code, and clean up
5. Displaying the complete analysis results and tool usage

### Agentic Coding Evaluation (`agentic-coding.R`)

Compares LLM performance with and without repljail tool access:

```r
source(system.file("examples", "agentic-coding.R", package = "repljail"))
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
