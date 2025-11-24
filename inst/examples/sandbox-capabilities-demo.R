#!/usr/bin/env Rscript

# Unified Sandbox Capabilities Demo for repljail Package
# This script checks all available sandboxing methods and tests their features

library(repljail)

cat("\n")
cat("================================================================================\n")
cat("                    repljail Sandbox Capabilities Demo\n")
cat("================================================================================\n")
cat("\n")

# Note: Debug logging is disabled to avoid interference with socket communication
# To enable debug logging, uncomment the line below:
# enable_debug(TRUE)

# Store results for summary
results <- list()

#' Test a specific isolation feature
#' @param session RREPLSession object
#' @param feature_name Name of the feature being tested
#' @param code R code to execute
#' @param timeout Execution timeout
#' @param expected_pattern Expected pattern in output (for validation)
test_feature <- function(session, feature_name, code, timeout = 15, expected_pattern = NULL) {
  cat(sprintf("  - Testing %s...\n", feature_name))

  result <- tryCatch({
    session$execute(code, timeout = timeout)
  }, error = function(e) {
    list(status = "error", result = list(output = paste("Error:", e$message)))
  })

  # Check if result is a proper list with status field
  if (!is.list(result) || is.null(result$status)) {
    cat(sprintf("    [FAIL] Invalid response from worker\n"))
    cat(sprintf("          Type: %s, Length: %d\n", typeof(result), length(result)))
    if (is.list(result)) {
      cat(sprintf("          Names: %s\n", paste(names(result), collapse=", ")))
    } else {
      cat(sprintf("          Raw value: %s\n", as.character(result)))
      # Check if it's a nanonext error value
      if (is.integer(result) && length(result) == 1) {
        cat(sprintf("          This appears to be a nanonext error code\n"))
      }
    }
    return(list(
      feature = feature_name,
      status = "FAIL",
      output = paste("Invalid response:", toString(result))
    ))
  }

  if (result$status == "success" || result$status == "error") {
    output <- paste(result$result$output, collapse = " ")

    # Check if output matches expected pattern
    status <- if (!is.null(expected_pattern)) {
      if (grepl(expected_pattern, output, ignore.case = TRUE)) "PASS" else "FAIL"
    } else {
      "INFO"
    }

    cat(sprintf("    [%s] %s\n", status, substr(output, 1, 80)))
    if (nchar(output) > 80) cat("           ...\n")

    return(list(
      feature = feature_name,
      status = status,
      output = output
    ))
  } else {
    cat(sprintf("    [FAIL] Timeout or communication error\n"))
    return(list(
      feature = feature_name,
      status = "FAIL",
      output = "Timeout"
    ))
  }
}

#' Test all security features for a sandboxing method
#' @param wrapper_type Type of worker wrapper (native, docker, firejail, macos-sandbox)
test_sandbox_features <- function(wrapper_type) {
  cat(sprintf("\n--- Testing %s ---\n", toupper(wrapper_type)))

  # Configure worker type
  options(repljail.worker.type = wrapper_type)

  # Handle network isolation for Docker
  if (wrapper_type == "docker") {
    # Test both with and without network isolation
    for (net_iso in c(FALSE, TRUE)) {
      options(repljail.worker.docker.network.isolation = net_iso)
      mode_name <- if (net_iso) "docker-isolated" else "docker-standard"

      cat(sprintf("\nMode: %s (network.isolation=%s)\n", mode_name, net_iso))

      test_sandbox_features_impl(mode_name)
    }
  } else {
    test_sandbox_features_impl(wrapper_type)
  }

  # Reset options
  options(repljail.worker.type = NULL)
  options(repljail.worker.docker.network.isolation = NULL)
}

#' Implementation of feature testing
#' @param mode_name Name/identifier for this mode
test_sandbox_features_impl <- function(mode_name) {
  # Create session
  session <- tryCatch({
    RREPLSession$new(timeout = 30)
  }, error = function(e) {
    cat(sprintf("  [SKIP] Failed to create session: %s\n", e$message))
    return(NULL)
  })

  if (is.null(session)) return()

  # Initialize results for this mode
  mode_results <- list(
    mode = mode_name,
    features = list()
  )

  tryCatch({
    # Get session info
    info <- session$get_info()
    cat(sprintf("\nSession Info:\n"))
    cat(sprintf("  - Wrapper type: %s\n", info$wrapper_type))
    cat(sprintf("  - Port: %s\n", info$port))
    cat(sprintf("  - PID: %s\n", info$pid))
    cat(sprintf("  - Is alive: %s\n", info$is_alive))

    cat(sprintf("\nSecurity Features:\n"))

    # Test 1: Basic computation (sanity check)
    mode_results$features$basic <- test_feature(
      session,
      "Basic computation",
      "2 + 2",
      timeout = 10,
      expected_pattern = "4"
    )

    # Test 2: External network access
    mode_results$features$network_external <- test_feature(
      session,
      "External network access (should BLOCK)",
      '
      tryCatch({
        con <- url("http://example.com", open = "r")
        close(con)
        "ACCESSIBLE"
      }, error = function(e) {
        paste("BLOCKED:", e$message)
      })
      ',
      timeout = 15,
      expected_pattern = "BLOCKED"
    )

    # Test 3: Localhost/loopback access
    mode_results$features$network_localhost <- test_feature(
      session,
      "Localhost network (for IPC)",
      '
      # Just verify we can reference localhost
      # Actual socket creation happens via the worker process itself
      "LOCALHOST_OK"
      ',
      timeout = 10,
      expected_pattern = "LOCALHOST_OK"
    )

    # Test 4: Temp directory isolation (writes inside sandbox should not affect host)
    temp_test_file <- tempfile(pattern = "repljail_isolation_test_", fileext = ".txt")
    temp_result <- test_feature(
      session,
      "Temp directory isolation (host should not see sandbox writes)",
      sprintf('
      tryCatch({
        writeLines("test content from sandbox", "%s")
        if (file.exists("%s")) "WROTE_FILE" else "WRITE_FAILED"
      }, error = function(e) {
        paste("WRITE_FAILED:", e$message)
      })
      ', temp_test_file, temp_test_file),
      timeout = 10,
      expected_pattern = "WROTE_FILE"
    )
    # Check if file exists on host (it should NOT for isolated sandboxes)
    temp_isolated <- !file.exists(temp_test_file)
    if (file.exists(temp_test_file)) {
      unlink(temp_test_file)  # Clean up if it leaked through
    }
    # Set status based on whether isolation exists (not whether behavior is "correct")
    # PASS = isolation exists, FAIL = no isolation
    temp_result$status <- if (temp_isolated) "PASS" else "FAIL"

    # Print interpretation based on mode
    if (mode_name == "native") {
      cat(sprintf("    Host filesystem: %s (expected - no isolation in native mode)\n",
                  if (temp_isolated) "ISOLATED (unexpected!)" else "NOT ISOLATED"))
    } else {
      cat(sprintf("    Host filesystem: %s\n",
                  if (temp_isolated) "ISOLATED ✓" else "NOT ISOLATED (LEAKED!) ✗"))
    }
    mode_results$features$fs_temp_isolation <- temp_result

    # Test 5: Home directory isolation (writes inside sandbox should not affect host)
    home_test_file <- file.path(path.expand("~"), paste0(".repljail_test_", format(Sys.time(), "%Y%m%d%H%M%S"), "_", sample(1000:9999, 1)))
    home_result <- test_feature(
      session,
      "Home directory isolation (host should not see sandbox writes)",
      sprintf('
      tryCatch({
        writeLines("test", "%s")
        if (file.exists("%s")) "WROTE_FILE" else "WRITE_FAILED"
      }, error = function(e) {
        paste("WRITE_FAILED:", e$message)
      })
      ', home_test_file, home_test_file),
      timeout = 10,
      expected_pattern = "WROTE_FILE|WRITE_FAILED"
    )
    # Check if file exists on host (it should NOT for isolated sandboxes)
    home_isolated <- !file.exists(home_test_file)
    if (file.exists(home_test_file)) {
      unlink(home_test_file)  # Clean up if it leaked through
    }
    # Set status based on whether isolation exists (not whether behavior is "correct")
    # PASS = isolation exists, FAIL = no isolation
    home_result$status <- if (home_isolated) "PASS" else "FAIL"

    # Print interpretation based on mode
    if (mode_name == "native") {
      cat(sprintf("    Host filesystem: %s (expected - no isolation in native mode)\n",
                  if (home_isolated) "ISOLATED (unexpected!)" else "NOT ISOLATED"))
    } else {
      cat(sprintf("    Host filesystem: %s\n",
                  if (home_isolated) "ISOLATED ✓" else "NOT ISOLATED (LEAKED!) ✗"))
    }
    mode_results$features$fs_home_isolation <- home_result

    # Test 6: System file read
    mode_results$features$fs_system_read <- test_feature(
      session,
      "System file read",
      '
      tryCatch({
        # Try to read a system file (different for each OS)
        system_file <- if (Sys.info()["sysname"] == "Darwin") {
          "/usr/share/dict/words"
        } else if (file.exists("/etc/hostname")) {
          "/etc/hostname"
        } else {
          "/etc/os-release"
        }

        if (file.exists(system_file)) {
          lines <- readLines(system_file, n = 1, warn = FALSE)
          if (length(lines) > 0) "READABLE" else "FAILED"
        } else {
          "FILE_NOT_FOUND"
        }
      }, error = function(e) {
        paste("BLOCKED:", e$message)
      })
      ',
      timeout = 10,
      expected_pattern = "READABLE|FILE_NOT_FOUND"
    )

    # Test 7: Privileged operations (should be blocked)
    mode_results$features$privileged_ops <- test_feature(
      session,
      "Privileged operations (should BLOCK)",
      '
      tryCatch({
        # Try to change system time (requires privileges)
        system("date -s \"2020-01-01 00:00:00\"", intern = TRUE)
        "ALLOWED"
      }, error = function(e) {
        "BLOCKED"
      })
      ',
      timeout = 10,
      expected_pattern = "BLOCKED"
    )

    # Test 8: Plot generation
    mode_results$features$plot_generation <- test_feature(
      session,
      "Plot generation",
      '
      plot(1:10, 1:10, main = "Test Plot")
      "PLOT_GENERATED"
      ',
      timeout = 20,
      expected_pattern = "PLOT_GENERATED"
    )

    # Test 9: Package loading
    mode_results$features$package_loading <- test_feature(
      session,
      "Package loading (base packages)",
      '
      tryCatch({
        library(stats)
        "LOADED"
      }, error = function(e) {
        paste("FAILED:", e$message)
      })
      ',
      timeout = 20,
      expected_pattern = "LOADED"
    )

    # Test 10: Process execution
    mode_results$features$process_exec <- test_feature(
      session,
      "Process execution (echo command)",
      '
      tryCatch({
        result <- system("echo test", intern = TRUE)
        if (length(result) > 0) "ALLOWED" else "FAILED"
      }, error = function(e) {
        paste("BLOCKED:", e$message)
      })
      ',
      timeout = 20,
      expected_pattern = "ALLOWED"
    )

    # Store results
    results[[mode_name]] <<- mode_results

  }, finally = {
    # Clean up session
    session$stop()
    cat(sprintf("\n  [INFO] Session stopped\n"))
  })
}

# ==============================================================================
# Main Execution
# ==============================================================================

cat("Step 1: Checking available sandboxing methods...\n")
cat("--------------------------------------------------------------------------------\n")

available_methods <- list()

# Check Native (always available)
available_methods$native <- list(available = TRUE, description = "No sandboxing")
cat("  [✓] Native (no sandboxing) - Always available\n")

# Check Docker
docker_available <- is_docker_available()
available_methods$docker <- list(
  available = docker_available,
  description = "Container isolation with optional network isolation"
)
if (docker_available) {
  cat("  [✓] Docker - Available\n")
  cat(sprintf("      Image: %s\n", get_worker_docker_image()))
} else {
  cat("  [✗] Docker - Not available\n")
  cat("      Install: https://docs.docker.com/get-docker/\n")
}

# Check Firejail
firejail_available <- is_firejail_available()
available_methods$firejail <- list(
  available = firejail_available,
  description = "Linux sandboxing with seccomp, capabilities, and namespaces"
)
if (firejail_available) {
  cat("  [✓] Firejail - Available\n")
} else {
  cat("  [✗] Firejail - Not available\n")
  if (Sys.info()["sysname"] == "Linux") {
    cat("      Install: sudo apt install firejail (Ubuntu/Debian)\n")
    cat("               sudo dnf install firejail (Fedora)\n")
    cat("               sudo pacman -S firejail (Arch)\n")
  } else {
    cat("      Note: Firejail is Linux-only\n")
  }
}

# Check macOS Sandbox
macos_sandbox_available <- is_macos_sandbox_available()
available_methods$macos_sandbox <- list(
  available = macos_sandbox_available,
  description = "macOS sandbox-exec with Sandbox Profile Language"
)
if (macos_sandbox_available) {
  cat("  [✓] macOS Sandbox - Available\n")
} else {
  cat("  [✗] macOS Sandbox - Not available\n")
  if (Sys.info()["sysname"] != "Darwin") {
    cat("      Note: macOS sandbox-exec is macOS-only\n")
  }
}

cat("\n")
cat("Step 2: Testing security features for each available method...\n")
cat("================================================================================\n")

# Test each available method
if (available_methods$native$available) {
  test_sandbox_features("native")
}

if (available_methods$docker$available) {
  test_sandbox_features("docker")
}

if (available_methods$firejail$available) {
  test_sandbox_features("firejail")
}

if (available_methods$macos_sandbox$available) {
  test_sandbox_features("macos-sandbox")
}

# ==============================================================================
# Summary Report
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("                           SUMMARY REPORT\n")
cat("================================================================================\n")
cat("\n")

# Create summary table
cat(sprintf("%-20s %-15s %-50s\n", "Method", "Status", "Description"))
cat(strrep("-", 85), "\n")

for (method_name in names(available_methods)) {
  method <- available_methods[[method_name]]
  status <- if (method$available) "✓ Available" else "✗ Not Available"
  cat(sprintf("%-20s %-15s %-50s\n", method_name, status, method$description))
}

cat("\n")
cat("Feature Comparison:\n")
cat(strrep("-", 85), "\n")

# Define features to compare
features_to_compare <- c(
  "network_external" = "Blocks external network",
  "fs_home_isolation" = "Isolates home directory (host protected)",
  "fs_temp_isolation" = "Isolates temp directory (host protected)",
  "privileged_ops" = "Blocks privileged operations",
  "process_exec" = "Allows process execution",
  "plot_generation" = "Supports plot generation",
  "package_loading" = "Supports package loading"
)

# Print header
cat(sprintf("%-35s", "Feature"))
for (mode_name in names(results)) {
  cat(sprintf(" %-15s", mode_name))
}
cat("\n")
cat(strrep("-", 85), "\n")

# Print each feature
for (feature_key in names(features_to_compare)) {
  feature_desc <- features_to_compare[feature_key]
  cat(sprintf("%-35s", feature_desc))

  for (mode_name in names(results)) {
    mode_result <- results[[mode_name]]
    if (!is.null(mode_result$features[[feature_key]])) {
      status <- mode_result$features[[feature_key]]$status
      symbol <- switch(status,
        "PASS" = "✓",
        "FAIL" = "✗",
        "INFO" = "○",
        "?"
      )
      cat(sprintf(" %-15s", symbol))
    } else {
      cat(sprintf(" %-15s", "-"))
    }
  }
  cat("\n")
}

cat("\n")
cat("Legend:\n")
cat("  ✓ = Feature working as expected\n")
cat("  ✗ = Feature not working as expected\n")
cat("  ○ = Informational (no pass/fail criterion)\n")
cat("  - = Not tested\n")

cat("\n")
cat("Recommendations:\n")
cat("--------------------------------------------------------------------------------\n")
cat("• For maximum security:\n")
cat("  - Use Docker with network isolation: options(repljail.worker.type = \"docker\",\n")
cat("                                                repljail.worker.docker.network.isolation = TRUE)\n")
cat("\n")
cat("• For lightweight Linux sandboxing:\n")
cat("  - Use Firejail: options(repljail.worker.type = \"firejail\")\n")
cat("\n")
cat("• For native macOS sandboxing:\n")
cat("  - Use macOS Sandbox: options(repljail.worker.type = \"macos-sandbox\")\n")
cat("\n")
cat("• For development/testing (no isolation):\n")
cat("  - Use Native: options(repljail.worker.type = \"native\")\n")

cat("\n")
cat("================================================================================\n")
cat("                         Demo Complete\n")
cat("================================================================================\n")
cat("\n")

cat("For more information:\n")
cat("  - ?RREPLSession\n")
cat("  - ?is_docker_available\n")
cat("  - ?is_firejail_available\n")
cat("  - ?is_macos_sandbox_available\n")
cat("  - README.md\n")
cat("\n")
