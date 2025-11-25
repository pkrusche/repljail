library(ellmer)
library(tibble)
library(dplyr)
library(repljail)

# Simple task in the format of {vitals}
# Vitals cannot visualize traces with tools yet, so we just evaluate directly.
tasks <- tibble(
  input = c(
    "What's the sum of all prime numbers between 1000000 and 2000000?"
  ),
  target = c("105363426899")
)

judge_chat <- chat_anthropic(
  model = "claude-sonnet-4-20250514",
  system_prompt = paste(
    "You're an expert in R programming and check if the returned result from a chat is a correct answer to the question.",
    "You will be given a question, the target answer, and the response from a chat.",
    "Check if the response contains the correct answer to the question.",
    "If the answer is correct, respond only with 'Correct', otherwise respond 'False'. ",
    "Do not provide any additional explanation, only say 'Correct' or 'False'.",
    "When the result is incorrect, do not use the word 'incorrect' in your response ",
    "since this will interfere with result parsing."
  )
)

vanilla_chat <- chat_anthropic(
  model = "claude-sonnet-4-20250514",
  system_prompt = paste(
    "You are an expert R programmer and data analyst.",
    "When asked coding questions:",
    "1. For coding tasks: Provide well-commented code examples",
    "2. For debugging: Explain the issue and provide the corrected code",
    "Be concise and give a minimal answer that is correct. "
  )
)

repljail_augmented_chat <- chat_anthropic(
  model = "claude-sonnet-4-20250514",
  system_prompt = paste(
    "You are an expert R programmer and data analyst.",
    "You have access to tools for executing R code in an isolated R environment. ",
    "When asked coding questions:",
    "1. For coding tasks: Provide well-commented code examples",
    "2. For debugging: Explain the issue and provide the corrected code",
    "3. For package questions: Use package search and documentation tools",
    " Try the code in an R session using the tools you have available. ",
    "Be concise and give a minimal answer that is correct. "
  )
)
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
  repljail_augmented_chat$register_tool(tool)
  cat("  ✓ Registered:", tool@name, "\n")
}

cat("All tools registered successfully!\n\n")

# Evaluate tasks with both chat systems
cat("Evaluating tasks...\n\n")

results <- list()
for (i in seq_len(nrow(tasks))) {
  cat("Task", i, ":\n")
  cat("Input:", tasks$input[i], "\n")
  cat("Target:", tasks$target[i], "\n\n")

  # Evaluate with vanilla chat
  cat("Getting vanilla response...\n")
  vanilla_response <- vanilla_chat$clone()$chat(tasks$input[i], echo = FALSE)

  # Evaluate with repljail-augmented chat
  cat("Getting repljail-augmented response...\n")
  repljail_response <- repljail_augmented_chat$clone()$chat(
    tasks$input[i],
    echo = FALSE
  )

  # Judge vanilla response
  judge_vanilla <- judge_chat$clone()$chat(
    paste(
      "Question:",
      tasks$input[i],
      "Target Answer:",
      tasks$target[i],
      "Response:",
      vanilla_response
    ),
    echo = FALSE
  )

  # Judge repljail response
  judge_repljail <- judge_chat$clone()$chat(
    paste(
      "Question:",
      tasks$input[i],
      "Target Answer:",
      tasks$target[i],
      "Response:",
      repljail_response
    ),
    echo = FALSE
  )

  # Store results
  results <- list(
    results,
    tibble(
      task_id = i,
      input = tasks$input[i],
      target = tasks$target[i],
      vanilla_response = vanilla_response,
      repljail_response = repljail_response,
      vanilla_correct = grepl("Correct", judge_vanilla, ignore.case = TRUE),
      repljail_correct = grepl("Correct", judge_repljail, ignore.case = TRUE)
    )
  )

  cat(
    "Vanilla response (",
    judge_vanilla,
    "):",
    substr(vanilla_response, 1, 100),
    "...\n"
  )
  cat(
    "repljail response (",
    judge_repljail,
    "):",
    substr(repljail_response, 1, 100),
    "...\n"
  )
  cat("---\n\n")
}

cat("Evaluation complete!\n")
print(results)
