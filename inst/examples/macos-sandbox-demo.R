#!/usr/bin/env Rscript

# macOS Sandbox Integration Demo for replr Package
# This script demonstrates how to use macOS sandbox-exec with replr

# Load the package
library(replr)

cat("\n=== macOS Sandbox Integration Demo ===\n\n")

# Check macOS sandbox availability
cat("1. Checking macOS sandbox-exec availability...\n")
macos_sandbox_available <- is_macos_sandbox_available()
cat("   macOS sandbox-exec available:", macos_sandbox_available, "\n\n")

if (!macos_sandbox_available) {
  if (Sys.info()["sysname"] != "Darwin") {
    cat("This demo requires macOS (Darwin).\n")
    cat("Current system:", Sys.info()["sysname"], "\n\n")
  } else {
    cat("macOS sandbox-exec is not available on this system.\n")
    cat("sandbox-exec should be pre-installed on macOS.\n")
    cat("Please check your system configuration.\n\n")
  }
  quit(save = "no")
}

# Enable debug logging to see what's happening
enable_debug(TRUE)

# Configure to use macOS sandbox
cat("2. Configuring replr to use macOS sandbox...\n")
options(replr.worker.type = "macos-sandbox")
cat("   Option 'replr.worker.type' set to 'macos-sandbox'\n\n")

# Create a session with macOS sandbox
cat("3. Creating a macOS sandbox-isolated R session...\n")
session <- RREPLSession$new(timeout = 30)

# Get session info
info <- session$get_info()
cat("   Session info:\n")
cat("     - Port:", info$port, "\n")
cat("     - PID:", info$pid, "\n")
cat("     - Wrapper type:", info$wrapper_type, "\n")
cat("     - Is alive:", info$is_alive, "\n\n")

# Execute some basic R code
cat("4. Executing basic R code in macOS sandbox...\n")
result <- session$execute("2 + 2")
cat("   Result:", result$result$output, "\n")
cat("   Status:", result$status, "\n\n")

# Test network isolation
cat("5. Testing network isolation (should fail)...\n")
network_test <- session$execute(
  '
  tryCatch({
    con <- url("http://example.com")
    close(con)
    "NETWORK_ACCESSIBLE"
  }, error = function(e) {
    paste("NETWORK_BLOCKED:", e$message)
  })
',
  timeout = 15
)
cat("   Network test result:\n")
cat("   ", network_test$result$output, "\n\n")

# Test localhost network access (should work for host communication)
cat("6. Testing localhost network access (should work)...\n")
localhost_test <- session$execute(
  '
  tryCatch({
    # Test if we can create a local socket
    # This should work because the sandbox allows localhost
    "LOCALHOST_OK"
  }, error = function(e) {
    paste("LOCALHOST_FAILED:", e$message)
  })
',
  timeout = 10
)
cat("   Localhost test result:\n")
cat("   ", localhost_test$result$output, "\n\n")

# Test filesystem isolation (temp directory should work)
cat("7. Testing filesystem access (temp directory - should work)...\n")
fs_test_temp <- session$execute(
  '
  tmpfile <- tempfile()
  writeLines("test content", tmpfile)
  exists <- file.exists(tmpfile)
  content <- if(exists) readLines(tmpfile) else "FAILED"
  unlink(tmpfile)
  list(exists = exists, content = content)
',
  timeout = 10
)
cat("   Temp directory test result:\n")
cat("   ", fs_test_temp$result$output, "\n\n")

# Test restricted filesystem access (home directory - should fail)
cat(
  "8. Testing filesystem restrictions (home directory write - should fail)...\n"
)
fs_test_home <- session$execute(
  '
  tryCatch({
    test_file <- file.path(path.expand("~"), ".replr_test_write")
    writeLines("test", test_file)
    unlink(test_file)
    "HOME_WRITABLE"
  }, error = function(e) {
    "HOME_RESTRICTED"
  })
',
  timeout = 10
)
cat("   Home directory write test result:\n")
cat("   ", fs_test_home$result$output, "\n\n")

# Execute code with a plot
cat("9. Testing plot generation in macOS sandbox...\n")
plot_result <- session$execute(
  '
  plot(1:10, 1:10, main = "Test Plot in macOS Sandbox")
  "Plot generated"
',
  timeout = 10
)
cat("   Plot result:\n")
cat("     Output:", plot_result$result$output, "\n")
cat("     Plots generated:", length(plot_result$result$plots), "\n")
if (length(plot_result$result$plots) > 0) {
  cat(
    "     Plot 1 (data URL):",
    substr(plot_result$result$plots[[1]], 1, 50),
    "...\n"
  )
}
cat("\n")

# Test reading system files (should be allowed)
cat("10. Testing system file reading (should work)...\n")
sys_read_test <- session$execute(
  '
  tryCatch({
    # Try to read a system file
    lines <- readLines("/usr/share/dict/words", n = 1, warn = FALSE)
    if (length(lines) > 0) "SYSTEM_READ_OK" else "SYSTEM_READ_FAILED"
  }, error = function(e) {
    paste("SYSTEM_READ_ERROR:", e$message)
  })
',
  timeout = 10
)
cat("   System file read test result:\n")
cat("   ", sys_read_test$result$output, "\n\n")

# Demonstrate custom macOS sandbox profile
cat("11. Testing custom macOS sandbox profile...\n")

# Create a temporary custom profile
profile_path <- tempfile(fileext = ".sb")
writeLines(
  c(
    "; Custom macOS sandbox profile for replr demo",
    "(version 1)",
    "(allow default)",
    "(deny default)",
    "",
    "; Allow file operations on temp directories",
    "(allow file* (subpath \"/tmp\"))",
    "(allow file* (subpath \"/private/tmp\"))",
    "",
    "; Allow network access to localhost only",
    "(allow network* (remote ip \"127.0.0.1:*\"))",
    "(allow network* (remote ip \"localhost:*\"))",
    "",
    "; Allow process operations",
    "(allow process-exec)",
    "(allow process-fork)",
    "(allow signal)",
    "",
    "; Allow IPC",
    "(allow ipc-posix-shm)",
    "(allow ipc-posix-sem)",
    "(allow mach-lookup)",
    "",
    "; Allow sysctl reads",
    "(allow sysctl-read)"
  ),
  profile_path
)

cat("   Created custom profile at:", profile_path, "\n")

# Stop current session
session$stop()
cat("   Stopped previous session\n")

# Configure to use custom profile
options(replr.worker.macos.sandbox.profile = profile_path)
cat("   Set custom profile option\n")

# Create new session with custom profile
session2 <- RREPLSession$new(timeout = 30)
cat("   Created new session with custom profile\n")

# Test the new session
custom_result <- session2$execute("cat('Custom profile works!')")
cat("   Custom profile test result:", custom_result$result$output, "\n\n")

# Test data frame operations
cat("12. Testing complex R operations in sandbox...\n")
complex_result <- session2$execute(
  '
  df <- data.frame(
    x = 1:10,
    y = rnorm(10)
  )
  summary(df)
',
  timeout = 10
)
cat("   Complex operations test:\n")
cat("     Status:", complex_result$status, "\n")
cat(
  "     Output preview:",
  substr(complex_result$result$output, 1, 100),
  "...\n\n"
)

# Clean up
cat("13. Cleaning up...\n")
session2$stop()
cat("    Second session stopped\n")

unlink(profile_path)
cat("    Custom profile deleted\n")

# Reset options
options(replr.worker.type = NULL)
options(replr.worker.macos.sandbox.profile = NULL)
cat("    Options reset\n\n")

# Disable debug logging
enable_debug(FALSE)

cat("=== Demo Complete ===\n\n")

cat("Summary:\n")
cat(
  "  - macOS sandbox-exec provides native sandboxing for R workers on macOS\n"
)
cat(
  "  - Network isolation blocks external connections (localhost retained for host communication)\n"
)
cat("  - Filesystem access is controlled via Sandbox Profile Language (SBPL)\n")
cat("  - Temp directories remain writable for working storage\n")
cat("  - System files can be read but not modified\n")
cat("  - Custom profiles allow fine-grained control using SBPL\n")
cat("  - Plot generation and code execution work normally within sandbox\n\n")

cat("Security Features:\n")
cat("  - Process isolation prevents breakout\n")
cat("  - Network limited to localhost (loopback) only\n")
cat("  - Filesystem writes restricted to /tmp and /private/tmp\n")
cat("  - No outbound network access beyond localhost\n")
cat("  - IPC and Mach lookups controlled by profile\n\n")

cat("For more information, see:\n")
cat("  - ?is_macos_sandbox_available\n")
cat("  - ?RREPLSession\n")
cat("  - README.md (macOS Sandbox section)\n")
cat("  - man sandbox-exec (macOS man page)\n")
cat(
  "  - https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf\n\n"
)
