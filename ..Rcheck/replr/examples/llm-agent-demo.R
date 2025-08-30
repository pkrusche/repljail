#' LLM Agent Example: Using Tools for Data Analysis
#'
#' This example demonstrates how an LLM agent would use ellmer with tools
#' to perform a complete data analysis workflow using isolated REPL sessions.
#' The script will:
#'
#' 1. Create an agent with access to the ellmer::tool() implementations from {replr}
#' 2. Ask the agent to create a histogram of 100 random normal values.
#' 3. Check if the computation ran successfully

library(replr)

library(ellmer)

# Initialize chat with OpenAI (requires API key)
cat("Initializing chat with OpenAI...\n")
tryCatch(
  {
    chat <- ellmer::chat_openai(
      system_prompt = paste(
        "You are a helpful data analysis assistant.",
        "You have access to tools for creating and managing isolated R REPL sessions.",
        "Use these tools to execute R code safely in separate processes.",
        "Always create a session first, then execute code, and clean up when done."
      )
    )
    cat("✓ Chat initialized successfully\n")
  },
  error = function(e) {
    cat("✗ Failed to initialize chat. Make sure OPENAI_API_KEY is set.\n")
    cat("Error:", e$message, "\n")
    stop("Chat initialization failed")
  }
)
# Register replr tools with the chat
cat("Registering replr tools...\n")

# Get all replr tool functions
tools <- list(
  replr_create_repl_session_tool(),
  replr_execute_code_tool(),
  replr_get_session_info_tool(),
  replr_list_sessions_tool(),
  replr_stop_session_tool(),
  replr_cleanup_sessions_tool(),
  replr_stop_all_sessions_tool()
)

# Register each tool with the chat
for (tool in tools) {
  chat$register_tool(tool)
  cat("  ✓ Registered:", tool@name, "\n")
}

cat("All tools registered successfully!\n\n")

# Define the analysis task
task <- paste(
  "Please help me analyze some data:",
  "1. Create a new REPL session",
  "2. Generate 100 random normal values with mean=0 and sd=1",
  "3. Create a histogram of these values",
  "4. Calculate basic summary statistics (mean, median, sd)",
  "5. Show me the results",
  "6. Clean up the session when done"
)

cat("=== Starting Data Analysis Demo ===\n")
cat("Task:", task, "\n\n")

# Send the task to the LLM
cat("Sending task to Agent\n")
response <- chat$chat(task)

# Display the response
cat("\n=== Agent's Response ===\n")
cat(response$content, "\n")

# Show any tool calls that were made
if (length(response$tool_calls) > 0) {
  cat("\n=== Tool Calls Made ===\n")
  for (i in seq_along(response$tool_calls)) {
    tool_call <- response$tool_calls[[i]]
    cat("Tool", i, ":", tool_call@name, "\n")
    if (length(tool_call@arguments) > 0) {
      cat("  Arguments:\n")
      for (arg_name in names(tool_call@arguments)) {
        cat("   ", arg_name, ":", tool_call@arguments[[arg_name]], "\n")
      }
    }
    cat("\n")
  }
}

# Show current sessions (should be empty if cleanup worked)
cat("\n=== Final Session Check ===\n")
final_sessions <- replr_list_sessions()
if (final_sessions$success && final_sessions$data$count == 0) {
  cat("✓ All sessions cleaned up successfully\n")
} else {
  cat("⚠ Sessions remain active:\n")
  print(final_sessions$data$sessions)

  # Clean up any remaining sessions
  cat("Cleaning up remaining sessions...\n")
  cleanup_result <- replr_stop_all_sessions()
  if (cleanup_result$success) {
    cat("✓ All sessions stopped\n")
  } else {
    cat("✗ Some sessions failed to stop:", cleanup_result$error, "\n")
  }
}

cat("\n=== Demo Complete ===\n")
cat("This example showed how an LLM agent can:\n")
cat("- Use replr tools to manage isolated R sessions\n")
cat("- Execute R code safely in separate processes\n")
cat("- Perform data analysis tasks with proper cleanup\n")
cat("- Handle errors and manage resources effectively\n")
