#' LLM Agent Example: Using Tools for Data Analysis
#'
#' This example demonstrates how an LLM agent would use ellmer with tools
#' to perform a complete data analysis workflow using isolated REPL sessions.
#' The script will:
#'
#' 1. Create an agent with access to the ellmer::tool() implementations from {repljail}
#' 2. Ask the agent to create a histogram of 100 random normal values.
#' 3. Check if the computation ran successfully

library(repljail)
library(ellmer)

# Initialize chat with OpenAI (requires API key)
cat("Initializing chat with OpenAI...\n")
tryCatch(
  {
    chat <- ellmer::chat_openai(
      system_prompt = paste(
        "You are a helpful data analysis assistant. ",
        "You have access to tools for creating and managing isolated R REPL sessions. ",
        "Use these tools to execute R code safely in separate processes. ",
        "Always create a session first, then execute code, and clean up when done. ",
        "When creating plots, do not save them to a temporary file. ",
        "Instead, just use plot() or ggplot() commands, will then return a temporary file path. ",
        "When a plot image is returned in this manner, return the <path> to the image by adding ",
        "__IMAGE_RETURNED__:<path> to your response."
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

plain_chat <- chat$clone()

# Register repljail tools with the chat
cat("Registering repljail tools...\n")

# Run in Docker for isolation
options(repljail.worker.type = "docker")

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

# Define the analysis task
task <- paste(
  "Please help me analyze some data:",
  "1. Create a new REPL session",
  "2. Generate 100 random normal values with mean=0 and sd=1",
  "3. Create a histogram of these values",
  "4. Calculate basic summary statistics (mean, median, sd)",
  "5. Show me the results (including the plots)",
  "6. Clean up the session when done"
)

cat("=== Starting Data Analysis Demo ===\n")
cat("Task:", task, "\n\n")

# Send the task to the LLM
cat("Sending task to Agent\n")
response <- chat$chat(task)

# Display the response
cat("\n=== Agent's Response ===\n")
cat(response, "\n")

cat("\n=== Analyze the Plot ===\n")
if (grepl("__IMAGE_RETURNED__:", response)) {
  image_path <- sub(".*__IMAGE_RETURNED__: *", "", response)
  cat("Image path extracted:", image_path, "\n")
  response <- plain_chat$chat(
    c(
      "Analyze the following image carefully and describe what you see in detail:"
    ),
    content_image_file(image_path),
  )
} else {
  cat("No image path found in the response.\n")
}

# Show current sessions (should be empty if cleanup worked)
cat("\n=== Final Session Check ===\n")
final_sessions <- repljail_list_sessions()
if (final_sessions$success && final_sessions$data$count == 0) {
  cat("✓ All sessions cleaned up successfully\n")
} else {
  cat("⚠ Sessions remain active:\n")
  print(final_sessions$data$sessions)

  # Clean up any remaining sessions
  cat("Cleaning up remaining sessions...\n")
  cleanup_result <- repljail_stop_all_sessions()
  if (cleanup_result$success) {
    cat("✓ All sessions stopped\n")
  } else {
    cat("✗ Some sessions failed to stop:", cleanup_result$error, "\n")
  }
}

cat("\n=== Demo Complete ===\n")
