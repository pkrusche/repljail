#!/usr/bin/env Rscript
# Example: Using Docker Network Isolation in replr
#
# This example demonstrates how to use the network isolation feature
# which creates isolated Docker networks with no external access.

library(replr)

cat("=== Docker Network Isolation Example ===\n\n")

# Step 1: Check if Docker is available
cat("1. Checking Docker availability...\n")
if (!is_docker_available()) {
  stop("Docker is not available. Please install Docker to use this feature.")
}
cat("   Docker is available ✓\n\n")

# Step 2: Enable Docker mode with network isolation
cat("2. Enabling Docker mode with network isolation...\n")
options(
  replr.use.docker = TRUE,
  replr.worker.docker.network.isolation = TRUE
)
cat("   Configuration set:\n")
cat("     - replr.use.docker = TRUE\n")
cat("     - replr.worker.docker.network.isolation = TRUE\n\n")

# Step 3: Create a session
cat("3. Creating an isolated R session...\n")
session <- RREPLSession$new(timeout = 30)
cat("   Session created ✓\n")
cat("   Worker is running in an isolated Docker network\n")
cat("   No external network access available to the worker\n\n")

# Step 4: Execute some code
cat("4. Executing code in the isolated session...\n")

# Basic arithmetic
result1 <- session$execute("2 + 2")
cat("   2 + 2 =", result1$result$output, "\n")

# Install and use a package (from cache if available)
result2 <- session$execute("library(stats); mean(c(1, 2, 3, 4, 5))")
cat("   mean(1:5) =", result2$result$output, "\n")

# Create a simple plot
result3 <- session$execute("plot(1:10); title('Test Plot')")
cat("   Plot created:", length(result3$result$plots), "plot(s)\n\n")

# Step 5: Demonstrate network isolation
cat("5. Demonstrating network isolation...\n")
cat("   The worker cannot access external networks.\n")
cat("   Attempting to download from the internet would fail.\n")
cat("   (We're not actually testing this to avoid errors)\n\n")

# Step 6: Stop the session
cat("6. Stopping the session...\n")
session$stop(timeout = 10)
cat("   Session stopped ✓\n")
cat("   Docker container and network automatically cleaned up\n\n")

# Step 7: Clean up any orphaned resources
cat("7. Cleaning up any orphaned resources...\n")
cleanup_docker_containers()
cleanup_docker_networks()
cat("   Cleanup complete ✓\n\n")

cat("=== Example Complete ===\n\n")
