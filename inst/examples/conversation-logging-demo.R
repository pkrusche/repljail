#' Conversation Logging Demo
#'
#' This example demonstrates how to use the ConversationLogger to log
#' ellmer chat sessions with repljail tools in markdown format.
#'
#' The logger captures:
#' - User prompts
#' - Assistant responses
#' - Tool calls (especially R code executions)
#' - Tool results with output, warnings, and errors
#'
#' All logs are formatted in readable markdown with code blocks for R code.

library(repljail)
library(ellmer)

# Create a log file path
log_file <- file.path("conversation_log.md")
cat("Log will be saved to:", log_file, "\n\n")

# Initialize chat with OpenAI (requires API key)
cat("Initializing chat with OpenAI...\n")
tryCatch(
  {
    chat <- ellmer::chat_openai(
      system_prompt = paste(
        "You are a helpful data analysis assistant. ",
        "You have access to tools for creating and managing isolated R REPL sessions. ",
        "Use these tools to execute R code safely in separate processes. ",
        "Always create a session first, then execute code, and clean up when done."
      ),
      model = "gpt-4o"
    )
    cat("✓ Chat initialized successfully\n")
  },
  error = function(e) {
    cat("✗ Failed to initialize chat. Make sure OPENAI_API_KEY is set.\n")
    cat("Error:", e$message, "\n")
    stop("Chat initialization failed")
  }
)

# Create and attach the conversation logger
cat("Creating conversation logger...\n")
logger <- create_conversation_logger(
  log_file = log_file,
  auto_save = TRUE # Automatically save after each turn
)

cat("Attaching logger to chat...\n")
logger$attach(chat)
cat("✓ Logger attached\n\n")

# Register repljail tools with the chat
cat("Registering repljail tools...\n")

# Run in Docker for isolation
options(repljail.use.docker = TRUE)

# Get all repljail tool functions
tools <- list(
  repljail_create_repl_session_tool(),
  repljail_execute_code_tool(),
  repljail_get_session_info_tool(),
  repljail_list_sessions_tool(),
  repljail_stop_session_tool(),
  repljail_cleanup_sessions_tool(),
  repljail_stop_all_sessions_tool()
)

# Register each tool with the chat
for (tool in tools) {
  chat$register_tool(tool)
  cat("  ✓ Registered:", tool@name, "\n")
}

cat("All tools registered successfully!\n\n")

# Start the conversation
cat("=== Starting Conversation ===\n\n")

# First request: Simple calculation
cat("User: Please create a session and calculate the mean of 1, 2, 3, 4, 5\n")
response1 <- chat$chat(
  "Please create a new REPL session and calculate the mean of the numbers 1, 2, 3, 4, 5"
)
cat("Assistant:", substr(response1, 1, 100), "...\n\n")

# Second request: Create a plot
cat("User: Create a histogram of random data\n")
response2 <- chat$chat(
  "In the same session, generate 100 random normal values and create a histogram"
)
cat("Assistant:", substr(response2, 1, 100), "...\n\n")

# Third request: Clean up
cat("User: Clean up the session\n")
response3 <- chat$chat(
  "Please clean up and stop the session"
)
cat("Assistant:", substr(response3, 1, 100), "...\n\n")

cat("=== Conversation Complete ===\n\n")

# Display the log
cat("=== Conversation Log Preview ===\n")
log_content <- logger$get_log()
cat(substr(log_content, 1, 500), "...\n\n")

# The log is already saved (auto_save = TRUE)
cat("Full log saved to:", log_file, "\n")

# Show file size
file_size <- file.info(log_file)$size
cat("Log file size:", file_size, "bytes\n\n")

# Clean up any remaining sessions
cat("=== Final Cleanup ===\n")
final_sessions <- repljail_list_sessions()
if (final_sessions$success && final_sessions$data$count == 0) {
  cat("✓ All sessions cleaned up successfully\n")
} else {
  cat("Cleaning up remaining sessions...\n")
  cleanup_result <- repljail_stop_all_sessions()
  if (cleanup_result$success) {
    cat("✓ All sessions stopped\n")
  }
}

cat("\n=== Demo Complete ===\n")
cat("View the full log at:", log_file, "\n")
