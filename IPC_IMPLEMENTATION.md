# IPC Socket Implementation Documentation

## Overview

This document describes the IPC (Inter-Process Communication) socket implementation for the replr package. IPC sockets provide better security and performance for local worker communication compared to TCP sockets.

## Changes Summary

### 1. Worker Script (inst/worker.R)
- **Modified argument parsing**: Now accepts both port numbers (for TCP) and socket paths (for IPC)
- **Automatic mode detection**: Determines mode based on argument type (numeric = TCP, string = IPC)
- **IPC socket URL support**: Uses `ipc://path` URL format for Unix domain sockets  
- **Socket file cleanup**: Removes socket files on worker shutdown

### 2. Communication Layer (R/communication.R)
- **Updated `create_req_socket()`**: Now supports both modes via optional parameters
  - `port`: For TCP mode
  - `socket_path`: For IPC mode
- **Socket URL construction**: Builds appropriate URL based on provided parameter

### 3. Worker Wrappers (R/worker-wrappers.R)
- **NativeWorkerWrapper**: Uses IPC sockets by default for local communication
- **FirejailWorkerWrapper**: Uses IPC sockets for sandboxed communication
- **DockerWorkerWrapper**: Continues to use TCP (required for container networking)
- **MacOSSandboxWorkerWrapper**: Continues to use TCP

### 4. Utility Functions (R/utils.R)
- **Added `get_ipc_socket_path()`**: Generates unique socket paths in temp directory
- **Updated `send_command()`**: Handles both IPC and TCP based on worker_info
- **Updated `stop_worker()`**: Cleans up IPC socket files after shutdown
- **Updated `start_worker()`**: Tests connections using appropriate socket type

### 5. Session Class (R/session.R)
- **Updated `get_info()`**: Exposes `socket_path` field for IPC workers

### 6. Tests (tests/testthat/test-ipc.R)
- Comprehensive test suite for IPC functionality
- Tests socket path generation
- Tests native and firejail worker IPC usage
- Tests Docker worker still uses TCP
- Tests end-to-end IPC communication

## Usage

IPC is automatically used for native and firejail workers:

```r
library(replr)

# Native worker uses IPC by default
options(replr.worker.type = "native")
session <- RREPLSession$new()
info <- session$get_info()
print(info$socket_path)  # Shows IPC socket path
print(info$wrapper_type)  # "native"

# Firejail worker uses IPC if available
options(replr.worker.type = "firejail")
session2 <- RREPLSession$new()
info2 <- session2$get_info()
print(info2$socket_path)  # Shows IPC socket path

# Docker worker still uses TCP
options(replr.worker.type = "docker")
session3 <- RREPLSession$new()
info3 <- session3$get_info()
print(info3$port)  # Shows TCP port
print(is.null(info3$socket_path))  # TRUE
```

## Benefits of IPC over TCP

1. **Security**: No network exposure - socket files are only accessible via filesystem permissions
2. **Performance**: Lower overhead than TCP stack
3. **Simplicity**: No port allocation conflicts
4. **Cleanup**: Socket files are automatically removed on worker shutdown

## Technical Details

### Socket Path Format
- Generated using `tempfile(pattern = "replr_socket_", tmpdir = tempdir())`
- Example: `/tmp/RtmpXXXXXX/replr_socket_123456`

### nanonext URL Format
- IPC: `ipc:///path/to/socket` (Unix/Linux/macOS)
- TCP: `tcp://127.0.0.1:port`

### Worker Detection Logic
The worker script determines mode based on the first argument:
```r
port <- suppressWarnings(as.integer(args[1]))
if (is.NA(port)) {
  # Not a number, treat as socket path (IPC mode)
  use_ipc <- TRUE
  socket_path <- args[1]
} else {
  # Number, treat as port (TCP mode)
  use_ipc <- FALSE
}
```

## Backward Compatibility

All changes maintain backward compatibility:
- Docker workers continue to use TCP (required for networking)
- macOS sandbox workers continue to use TCP
- Port-based API remains available
- `worker_info$port` still exists for all workers (even if unused)

## Testing

Run IPC-specific tests:
```r
devtools::test_file("tests/testthat/test-ipc.R")
```

## Troubleshooting

### Socket file not cleaned up
If socket files persist after crashes:
```r
# List orphaned socket files
list.files(tempdir(), pattern = "replr_socket_", full.names = TRUE)

# Clean up manually if needed
unlink(list.files(tempdir(), pattern = "replr_socket_", full.names = TRUE))
```

### Permission denied on socket file
This can occur if filesystem permissions are incorrect. The socket file should have same owner/permissions as the R process.
