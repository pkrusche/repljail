#!/usr/bin/env Rscript

# Firejail Integration Demo for replr Package
# This script demonstrates how to use firejail sandboxing with replr

# Load the package
library(replr)

cat("\n=== Firejail Integration Demo ===\n\n")

# Check firejail availability
cat("1. Checking firejail availability...\n")
firejail_available <- is_firejail_available()
cat("   Firejail available:", firejail_available, "\n\n")

if (!firejail_available) {
  cat("Firejail is not available on this system.\n")
  cat("To install firejail:\n")
  cat("  - Ubuntu/Debian: sudo apt install firejail\n")
  cat("  - Fedora: sudo dnf install firejail\n")
  cat("  - Arch: sudo pacman -S firejail\n\n")
  quit(save = "no")
}

# Enable debug logging to see what's happening
enable_debug(TRUE)

# Configure to use firejail
cat("2. Configuring replr to use firejail...\n")
options(replr.use.firejail = TRUE)
cat("   Option 'replr.use.firejail' set to TRUE\n\n")

# Create a session with firejail
cat("3. Creating a firejail-isolated R session...\n")
session <- RREPLSession$new(timeout = 30)

# Get session info
info <- session$get_info()
cat("   Session info:\n")
cat("     - Port:", info$port, "\n")
cat("     - PID:", info$pid, "\n")
cat("     - Wrapper type:", info$wrapper_type, "\n")
cat("     - Is alive:", info$is_alive, "\n\n")

# Execute some basic R code
cat("4. Executing basic R code in firejail sandbox...\n")
result <- session$execute("2 + 2")
cat("   Result:", result$result$output, "\n")
cat("   Status:", result$status, "\n\n")

# Test network isolation
cat("5. Testing network isolation (should fail)...\n")
network_test <- session$execute('
  tryCatch({
    con <- url("http://example.com")
    close(con)
    "NETWORK_ACCESSIBLE"
  }, error = function(e) {
    paste("NETWORK_BLOCKED:", e$message)
  })
', timeout = 15)
cat("   Network test result:\n")
cat("   ", network_test$result$output, "\n\n")

# Test filesystem isolation (temp directory should work)
cat("6. Testing filesystem access (temp directory)...\n")
fs_test <- session$execute('
  tmpfile <- tempfile()
  writeLines("test content", tmpfile)
  exists <- file.exists(tmpfile)
  content <- if(exists) readLines(tmpfile) else "FAILED"
  unlink(tmpfile)
  list(exists = exists, content = content)
', timeout = 10)
cat("   Filesystem test result:\n")
cat("   ", fs_test$result$output, "\n\n")

# Test capability restrictions by trying privileged operations
cat("7. Testing capability restrictions...\n")
cap_test <- session$execute('
  tryCatch({
    # Try to change system time (requires CAP_SYS_TIME)
    system("date -s \\"2020-01-01 00:00:00\\"", intern = TRUE)
    "PRIVILEGED_OP_SUCCEEDED"
  }, error = function(e) {
    "PRIVILEGED_OP_BLOCKED"
  })
', timeout = 10)
cat("   Capability test result:\n")
cat("   ", cap_test$result$output, "\n\n")

# Execute code with a plot
cat("8. Testing plot generation in firejail...\n")
plot_result <- session$execute('
  plot(1:10, 1:10, main = "Test Plot in Firejail")
  "Plot generated"
', timeout = 10)
cat("   Plot result:\n")
cat("     Output:", plot_result$result$output, "\n")
cat("     Plots generated:", length(plot_result$result$plots), "\n")
if (length(plot_result$result$plots) > 0) {
  cat("     Plot 1 (data URL):", substr(plot_result$result$plots[[1]], 1, 50), "...\n")
}
cat("\n")

# Demonstrate custom firejail profile
cat("9. Testing custom firejail profile...\n")

# Create a temporary custom profile
profile_path <- tempfile(fileext = ".profile")
writeLines(c(
  "# Custom firejail profile for replr demo",
  "net none",
  "private-tmp",
  "caps.drop all",
  "seccomp"
), profile_path)

cat("   Created custom profile at:", profile_path, "\n")

# Stop current session
session$stop()
cat("   Stopped previous session\n")

# Configure to use custom profile
options(replr.worker.firejail.profile = profile_path)
cat("   Set custom profile option\n")

# Create new session with custom profile
session2 <- RREPLSession$new(timeout = 30)
cat("   Created new session with custom profile\n")

# Test the new session
custom_result <- session2$execute("cat('Custom profile works!')")
cat("   Custom profile test result:", custom_result$result$output, "\n\n")

# Clean up
cat("10. Cleaning up...\n")
session2$stop()
cat("    Second session stopped\n")

unlink(profile_path)
cat("    Custom profile deleted\n")

# Reset options
options(replr.use.firejail = NULL)
options(replr.worker.firejail.profile = NULL)
cat("    Options reset\n\n")

cat("=== Demo Complete ===\n\n")

cat("Summary:\n")
cat("  - Firejail provides lightweight sandboxing for R workers\n")
cat("  - Network isolation prevents external connections\n")
cat("  - Filesystem is restricted (only temp directory writable)\n")
cat("  - Linux capabilities are dropped for security\n")
cat("  - Custom profiles allow fine-grained control\n")
cat("  - Plot generation and code execution work normally within sandbox\n\n")

cat("For more information, see:\n")
cat("  - ?is_firejail_available\n")
cat("  - ?RREPLSession\n")
cat("  - README.md (Firejail section)\n\n")
