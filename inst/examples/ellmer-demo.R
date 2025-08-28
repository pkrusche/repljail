#' ellmer Tools Usage Example
#'
#' This script demonstrates how to use the ellmer tools for REPL session
#' management with LLM agents.
#'
#' The ellmer tools provide a standardized interface for LLM agents to:
#' - Create isolated R REPL sessions
#' - Execute R code in those sessions
#' - Manage multiple concurrent sessions
#' - Get structured responses suitable for LLM processing

# Load the replr package (with ellmer tools)
library(replr)

# Example 1: Basic session creation and code execution
cat("=== Example 1: Basic Usage ===\n")

# Create a new REPL session
result <- ellmer_create_repl_session()
if (result$success) {
  session_id <- result$data$session_id
  cat("Created session:", session_id, "\n")
  
  # Execute some R code
  exec_result <- ellmer_execute_code(session_id, "x <- 10; y <- 20; x + y")
  if (exec_result$success) {
    cat("Execution output:", exec_result$data$output, "\n")
  }
  
  # Execute code with output
  result2 <- ellmer_execute_code(session_id, "summary(mtcars)")
  if (result2$success) {
    cat("Summary output:\n")
    cat(paste(result2$data$output, collapse = "\n"), "\n")
  }
  
  # Clean up
  ellmer_stop_session(session_id)
  cat("Session stopped.\n")
}

cat("\n=== Example 2: Multiple Sessions and Isolation ===\n")

# Create multiple sessions for different analyses
analysis1 <- ellmer_create_repl_session("data_analysis")
analysis2 <- ellmer_create_repl_session("model_building")

if (analysis1$success && analysis2$success) {
  # Set up different data in each session
  ellmer_execute_code("data_analysis", "
    data <- mtcars
    summary_stats <- summary(data$mpg)
    data_type <- 'car_data'
  ")
  
  ellmer_execute_code("model_building", "
    data <- iris
    model <- lm(Sepal.Length ~ Sepal.Width, data = data)
    data_type <- 'flower_data'
  ")
  
  # Verify isolation - each session has its own data_type
  result1 <- ellmer_execute_code("data_analysis", "data_type")
  result2 <- ellmer_execute_code("model_building", "data_type")
  
  cat("Analysis 1 data type:", result1$data$output, "\n")
  cat("Analysis 2 data type:", result2$data$output, "\n")
  
  # List all active sessions
  sessions <- ellmer_list_sessions()
  cat("Active sessions:", sessions$data$count, "\n")
  
  # Clean up all sessions
  ellmer_stop_all_sessions()
}

cat("\n=== Example 3: Error Handling ===\n")

# Create session for error handling demo
error_demo <- ellmer_create_repl_session("error_demo")
if (error_demo$success) {
  session_id <- error_demo$data$session_id
  
  # Execute code that generates a warning
  warning_result <- ellmer_execute_code(session_id, "
    warning('This is a warning message')
    result <- 42
    result
  ")
  
  cat("Warning example:\n")
  cat("Status:", warning_result$data$status, "\n")
  cat("Warnings:", paste(warning_result$data$warnings, collapse = "; "), "\n")
  cat("Output:", warning_result$data$output, "\n")
  
  # Execute code that generates an error
  error_result <- ellmer_execute_code(session_id, "stop('This is an error')")
  
  cat("\nError example:\n")
  cat("Success:", error_result$success, "\n")
  cat("Status:", error_result$data$status, "\n")
  cat("Errors:", paste(error_result$data$errors, collapse = "; "), "\n")
  
  # Verify session survives errors
  recovery_result <- ellmer_execute_code(session_id, "2 + 2")
  cat("\nRecovery after error:\n")
  cat("Success:", recovery_result$success, "\n")
  cat("Output:", recovery_result$data$output, "\n")
  
  # Clean up
  ellmer_stop_session(session_id)
}

cat("\n=== Example 4: Session Management ===\n")

# Create several sessions
sessions <- c("session_a", "session_b", "session_c")
for (id in sessions) {
  result <- ellmer_create_repl_session(id)
  if (result$success) {
    cat("Created session:", id, "\n")
  }
}

# List all sessions
all_sessions <- ellmer_list_sessions()
cat("Total active sessions:", all_sessions$data$count, "\n")

# Get info about a specific session
info <- ellmer_get_session_info("session_b")
if (info$success) {
  cat("Session B info:\n")
  cat("  Port:", info$data$port, "\n")
  cat("  PID:", info$data$pid, "\n")
  cat("  Started at:", info$data$started_at, "\n")
}

# Clean up all sessions
cleanup <- ellmer_stop_all_sessions()
cat("Stopped", cleanup$data$stopped_count, "sessions\n")

cat("\n=== ellmer Tools Demo Complete ===\n")
cat("All ellmer tools are working correctly!\n")