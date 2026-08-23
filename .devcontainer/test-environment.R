#!/usr/bin/env Rscript

# Test script to validate the custom Copilot environment setup
# This script should be run inside the devcontainer to verify everything works

cat("=== Testing Custom GitHub Copilot Environment for repljail ===\n\n")

# Test 1: Check R version
cat("1. R Version:\n")
cat(paste("   R version:", R.version.string), "\n\n")

# Test 2: Check required packages
cat("2. Required Packages:\n")
required_packages <- c("nanonext", "processx", "evaluate", "R6", "uuid", "ellmer")
for (pkg in required_packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("   ✓ %s: %s\n", pkg, packageVersion(pkg)))
  } else {
    cat(sprintf("   ✗ %s: NOT FOUND\n", pkg))
  }
}

# Test 3: Check suggested packages
cat("\n3. Suggested Packages:\n")
suggested_packages <- c("testthat")
for (pkg in suggested_packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("   ✓ %s: %s\n", pkg, packageVersion(pkg)))
  } else {
    cat(sprintf("   ✗ %s: NOT FOUND\n", pkg))
  }
}

# Test 4: Check development tools
cat("\n4. Development Tools:\n")
dev_packages <- c("devtools", "roxygen2", "lintr")
for (pkg in dev_packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("   ✓ %s: %s\n", pkg, packageVersion(pkg)))
  } else {
    cat(sprintf("   ✗ %s: NOT FOUND\n", pkg))
  }
}

# Test 5: Test package dependency check function
cat("\n5. Testing repljail dependency check:\n")
tryCatch(
  {
    if (file.exists("R/utils.R")) {
      source("R/utils.R")
      result <- check_dependencies()
      cat("   ✓ repljail::check_dependencies() passed\n")
    } else {
      cat("   ⚠ R/utils.R not found (run from package root)\n")
    }
  },
  error = function(e) {
    cat(sprintf("   ✗ repljail::check_dependencies() failed: %s\n", e$message))
  }
)

# Test 6: Test basic nanonext functionality
cat("\n6. Testing nanonext (key dependency):\n")
tryCatch(
  {
    if (requireNamespace("nanonext", quietly = TRUE)) {
      # Simple socket test
      sock <- nanonext::socket("pair")
      close(sock)
      cat("   ✓ nanonext socket creation works\n")
    }
  },
  error = function(e) {
    cat(sprintf("   ✗ nanonext test failed: %s\n", e$message))
  }
)

cat("\n=== Environment Test Complete ===\n")
cat("If all tests show ✓, the environment is ready for GitHub Copilot!\n")
