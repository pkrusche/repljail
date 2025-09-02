# Docker Integration Example for replr
# 
# This example demonstrates how to use replr with Docker containers
# for enhanced isolation and security.

# Load the replr package
library(replr)

cat("=== replr Docker Integration Example ===\n")

# Check if Docker is available
cat("\n1. Checking Docker availability...\n")
docker_available <- is_docker_available()
cat("Docker available:", docker_available, "\n")

if (docker_available) {
  cat("Docker image name:", get_worker_docker_image(), "\n")
  
  # Test 1: Create a session with Docker auto-detection (ellmer style)
  cat("\n2. Creating session with auto-detection...\n")
  result1 <- replr_create_repl_session("docker_auto_session")
  cat("Auto-detection result:")
  cat("  Success:", result1$success, "\n")
  cat("  Message:", result1$message, "\n")
  if (result1$success) {
    cat("  Using Docker:", result1$data$using_docker, "\n")
    
    # Execute some test code
    cat("\n3. Executing test code in auto-detected session...\n")
    code_result <- replr_execute_code("docker_auto_session", "2 + 2")
    cat("  Code execution success:", code_result$success, "\n")
    if (code_result$success) {
      cat("  Output:", code_result$data$output, "\n")
    }
    
    # Clean up
    replr_stop_session("docker_auto_session")
  }
  
  # Test 2: Explicitly request Docker
  cat("\n4. Creating session with explicit Docker request...\n")
  result2 <- replr_create_repl_session_docker("explicit_docker_session", use_docker = TRUE)
  cat("Explicit Docker result:")
  cat("  Success:", result2$success, "\n")
  cat("  Message:", result2$message, "\n")
  if (result2$success) {
    cat("  Using Docker:", result2$data$using_docker, "\n")
    
    # Execute more complex code
    cat("\n5. Executing complex code in Docker session...\n")
    complex_code <- "
    x <- c(1, 2, 3, 4, 5)
    mean_x <- mean(x)
    sd_x <- sd(x)
    paste('Mean:', mean_x, 'SD:', sd_x)
    "
    code_result2 <- replr_execute_code("explicit_docker_session", complex_code)
    cat("  Complex code success:", code_result2$success, "\n")
    if (code_result2$success) {
      cat("  Output:", paste(code_result2$data$output, collapse = "\n"), "\n")
    }
    
    # Clean up
    replr_stop_session("explicit_docker_session")
  }
  
  # Test 3: Object-oriented API with Docker
  cat("\n6. Using object-oriented API with Docker...\n")
  tryCatch({
    docker_session <- RREPLSession$new(use_docker = TRUE)
    cat("  OOP Docker session created successfully\n")
    cat("  Session port:", docker_session$port, "\n")
    cat("  Session PID:", docker_session$pid, "\n")
    
    # Execute code using OOP API
    oop_result <- docker_session$execute("sqrt(16)")
    cat("  OOP execution success:", !is.null(oop_result), "\n")
    if (!is.null(oop_result) && oop_result$status == "success") {
      cat("  OOP Output:", oop_result$result$output, "\n")
    }
    
    # Clean up
    docker_session$stop()
    cat("  OOP session stopped\n")
  }, error = function(e) {
    cat("  OOP Docker session error:", e$message, "\n")
  })
  
} else {
  cat("\nDocker is not available on this system.\n")
  cat("The replr package will use native process isolation instead.\n")
  
  # Demonstrate fallback to native execution
  cat("\n2. Creating session with native fallback...\n")
  result_native <- replr_create_repl_session("native_session")
  cat("Native result:")
  cat("  Success:", result_native$success, "\n")
  cat("  Message:", result_native$message, "\n")
  if (result_native$success) {
    cat("  Using Docker:", result_native$data$using_docker, "\n")
    
    # Test native execution
    code_result_native <- replr_execute_code("native_session", "3 * 7")
    cat("  Code execution success:", code_result_native$success, "\n")
    if (code_result_native$success) {
      cat("  Output:", code_result_native$data$output, "\n")
    }
    
    # Clean up
    replr_stop_session("native_session")
  }
}

# Test the Docker availability tool
cat("\n7. Testing Docker availability tool...\n")
docker_check_result <- replr_check_docker_availability()
cat("Docker check result:")
cat("  Success:", docker_check_result$success, "\n")
cat("  Message:", docker_check_result$message, "\n")
cat("  Available:", docker_check_result$data$available, "\n")

# Summary
cat("\n=== Summary ===\n")
cat("✓ Docker availability detection implemented\n")
cat("✓ Minimal hardened Dockerfile created\n")
cat("✓ Secure container execution with isolation\n")
cat("✓ RREPLSession class supports use_docker parameter\n")
cat("✓ ellmer tools auto-detect Docker availability\n")
cat("✓ Explicit Docker control available\n")
cat("✓ Graceful fallback to native execution\n")

cat("\nDocker integration example completed!\n")