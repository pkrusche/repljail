#!/usr/bin/env Rscript
# Example demonstrating the replr_lint_code MCP tool
# This script shows how to use the lintr functionality without executing code

library(replr)

cat("========================================\n")
cat("replr_lint_code MCP Tool Demo\n")
cat("========================================\n\n")

# Example 1: Clean code (no issues)
cat("Example 1: Linting clean code\n")
cat("------------------------------\n")
clean_code <- "
x <- 1
y <- 2
z <- x + y
print(z)
"

result1 <- replr_lint_code(clean_code)
cat("Code to lint:\n", clean_code, "\n")
cat("Success:", result1$success, "\n")
cat("Message:", result1$message, "\n")
cat("Lint count:", result1$data$lint_count, "\n\n")

# Example 2: Code with style issues
cat("Example 2: Linting code with style issues\n")
cat("------------------------------------------\n")
bad_code <- "
x = 1
y=2
z <- x + y
"

result2 <- replr_lint_code(bad_code)
cat("Code to lint:\n", bad_code, "\n")
cat("Success:", result2$success, "\n")
cat("Message:", result2$message, "\n")
cat("Lint count:", result2$data$lint_count, "\n")

if (result2$data$lint_count > 0) {
  cat("\nLinting issues found:\n")
  for (i in seq_along(result2$data$lints)) {
    lint <- result2$data$lints[[i]]
    cat(sprintf(
      "  [Line %d, Col %d] %s: %s\n",
      lint$line,
      lint$column,
      lint$type,
      lint$message
    ))
  }
}
cat("\n")

# Example 3: Using the tool definition
cat("Example 3: Tool definition structure\n")
cat("-------------------------------------\n")
tool <- replr_lint_code_tool()
cat("Tool name:", tool$name, "\n")
cat("Description:", substr(tool$description, 1, 80), "...\n")
cat("Parameters:", paste(names(tool$parameters), collapse = ", "), "\n\n")

cat("========================================\n")
cat("Demo complete!\n")
cat("========================================\n")
