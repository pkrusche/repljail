# Docker Integration Example for replr
#
# This example demonstrates how to use replr with Docker containers
# for enhanced isolation and security.

# Load the replr package
library(replr)

cat("=== replr Docker Integration Example ===\n")

options(replr.debug = TRUE)
options(replr.use.docker = TRUE)

# Check if Docker is available
cat("\n1. Checking Docker availability...\n")
docker_available <- is_docker_available()
cat("Docker available:", docker_available, "\n")

stopifnot(docker_available)
cat("Docker image name:", get_worker_docker_image(), "\n")

# Test 1: Create a session with Docker auto-detection (ellmer style)
cat("\n2. Creating session...\n")
result1 <- replr_create_repl_session()
cat("Success:", result1$success, "\n")
cat("Message:", result1$message, "\n")
cat("Session ID:", result1$data$session_id, "\n")
stopifnot(result1$success)
session_id <- result1$data$session_id

# Execute some test code
cat("\n3. Executing test code in", session_id, "...\n")
code_result <- replr_execute_code(session_id, "2 + 2")
cat("  Code execution success:", code_result$success, "\n")
if (code_result$success) {
  cat("  Output:", code_result$data$output, "\n")
}
stopifnot(code_result$success)

# Clean up
replr_stop_session(session_id)

cat("\nDocker integration example completed!\n")
