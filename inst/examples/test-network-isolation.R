#!/usr/bin/env Rscript

# Test network isolation implementation

library(devtools)
load_all()

# Enable Docker mode with network isolation
options(replr.use.docker = TRUE)
options(replr.worker.docker.network.isolation = TRUE)

cat("Starting worker with network isolation...\n")
worker <- start_worker(timeout = 20)

cat("✓ Worker started successfully!\n\n")

# Test 1: Basic computation
cat("Test 1: Basic computation\n")
result1 <- send_command(worker, "2 + 2")
if (!is.null(result1) && !is.null(result1$result)) {
  cat("  Result:", result1$result$output, "\n")
} else {
  cat("  ERROR: Failed to get result\n")
  print(result1)
}

# Test 2: Internet access (should be blocked)
cat("\nTest 2: Internet access (should be blocked)\n")
result2 <- send_command(
  worker,
  '
  tryCatch({
    readLines("http://example.com", n = 1)
    "FAIL: Internet is accessible"
  }, error = function(e) {
    paste("SUCCESS: Blocked -", e$message)
  })
'
)
if (!is.null(result2) && !is.null(result2$result)) {
  cat("  ", result2$result$output, "\n")
} else {
  cat("  ERROR: Failed to get result\n")
  print(result2)
}

# Cleanup
cat("\nCleaning up...\n")
stop_worker(worker)

cat("\n✓ All tests completed!\n")
