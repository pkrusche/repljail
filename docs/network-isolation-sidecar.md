# Network Isolation: Sidecar Gateway Pattern

## Overview

The `replr` package implements **true air-gapped execution** for R worker processes using Docker's `--internal` network flag combined with a gateway sidecar pattern. This provides complete internet isolation while maintaining host-to-worker communication.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Host Machine (127.0.0.1)                                        │
│                                                                 │
│  Controller Process                                             │
│  └─ nanonext REQ socket                                         │
│     connects to: tcp://127.0.0.1:<port>                         │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ Port publish (-p 127.0.0.1:<port>:8080)
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ Gateway Container (alpine/socat)                                │
│                                                                 │
│  TCP-LISTEN:8080 → TCP:worker-container:<port>                  │
│  └─ Forwards all traffic from host to worker                    │
│                                                                 │
│  Connected to BOTH:                                             │
│  - Default bridge (for host access)                             │
│  - Internal network (for worker access)                         │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ Docker internal network (--internal)
                        │ NO EXTERNAL/INTERNET ACCESS
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│ Worker Container (replr-worker)                                 │
│                                                                 │
│  R Process                                                      │
│  └─ nanonext REP socket                                         │
│     listens on: tcp://*:<port>                                  │
│                                                                 │
│  ✅ Can receive from gateway                                    │
│  ❌ CANNOT access internet (--internal blocks outbound)          │
│  ❌ CANNOT access other containers                               │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Details

### Network Creation (`R/utils.R:create_docker_network()`)

```r
docker network create \
  --driver bridge \
  --internal \              # Blocks ALL external access
  --subnet 172.28.0.0/16 \  # Custom subnet to avoid conflicts
  replr-network-<port>-<timestamp>
```

**Key change**: Removed `--opt com.docker.network.bridge.enable_icc=false` which was blocking gateway→worker communication.

### Worker Container (`R/utils.R:start_docker_worker()`)

```r
docker run \
  --name replr-worker-<port>-<timestamp> \
  --network replr-network-<id> \  # Isolated network only, no port publish
  --user replr \                   # Non-root user
  --memory 512m \
  --cpus 1.0 \
  --read-only \                    # Read-only filesystem
  --tmpfs /tmp:noexec,nosuid \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  replr-worker:latest \
  Rscript /app/worker.R <port> --listen-all --debug
```

### Gateway Sidecar (`R/utils.R:start_docker_worker()`)

```r
# Step 1: Start gateway with port publish for host access
docker run -d \
  --name replr-gateway-<port>-<timestamp> \
  -p 127.0.0.1:<port>:8080 \
  alpine/socat \
  TCP-LISTEN:8080,fork,reuseaddr TCP:replr-worker-<id>:<port>

# Step 2: Connect gateway to internal network for worker access
docker network connect replr-network-<id> replr-gateway-<id>
```

## Security Properties

### ✅ What IS blocked:
- **Internet access**: Worker cannot reach external IPs or DNS
- **Package installation**: No access to CRAN mirrors or GitHub
- **Data exfiltration**: Cannot send HTTP requests outside
- **Network scanning**: Cannot probe other hosts

### ✅ What WORKS:
- **Host communication**: nanonext socket communication via gateway
- **Code execution**: Full R capabilities (compute, plots, local data)
- **Package usage**: Pre-installed packages work normally

## Usage

```r
# Enable Docker with network isolation
options(replr.use.docker = TRUE)
options(replr.worker.docker.network.isolation = TRUE)

# Create isolated session
session <- RREPLSession$new()

# This works (local execution)
session$execute("2 + 2")
#> [1] 4

# This fails (internet blocked)
session$execute('readLines(url("http://example.com"))')
#> Error: cannot open connection

session$stop()
```

## Configuration Options

```r
# Enable Docker workers
options(replr.use.docker = TRUE)

# Enable network isolation (requires Docker)
options(replr.worker.docker.network.isolation = TRUE)

# Optional: Customize Docker image
options(replr.worker.docker.image = "replr-worker:latest")

# Optional: Resource limits
options(replr.worker.docker.memory = "512m")
options(replr.worker.docker.cpus = "1.0")
```

## Cleanup

All resources are automatically cleaned up when the session stops:

```r
session$stop()
# Automatically removes:
# 1. Worker container (replr-worker-*)
# 2. Gateway container (replr-gateway-*)
# 3. Internal network (replr-network-*)
```

Manual cleanup of orphaned resources:
```r
cleanup_docker_containers()  # Remove orphaned worker/gateway containers
cleanup_docker_networks()    # Remove orphaned networks
```

## Comparison with Standard Docker Mode

| Feature | Standard Docker | Network Isolation (Sidecar) |
|---------|----------------|----------------------------|
| Internet access | ✅ Available | ❌ Blocked |
| Port publishing | Direct `-p <port>:<port>` | Via gateway `-p <port>:8080` |
| Containers | 1 (worker) | 2 (worker + gateway) |
| Network | Default bridge | Custom `--internal` network |
| Security | Standard isolation | Air-gapped execution |

## Troubleshooting

Enable debug logging to see detailed network setup:
```r
enable_debug(TRUE)
```

Check Docker resources:
```bash
# List worker containers
docker ps -a --filter "name=replr-worker-"

# List gateway containers
docker ps -a --filter "name=replr-gateway-"

# List networks
docker network ls --filter "name=replr-network-"
```
