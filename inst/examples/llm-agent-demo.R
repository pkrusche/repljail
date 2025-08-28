#' LLM Agent Example: Using ellmer Tools for Data Analysis
#'
#' This example demonstrates how an LLM agent would use the ellmer tools
#' to perform a complete data analysis workflow using isolated REPL sessions.

# Simulate LLM Agent Functions
cat("=== LLM Agent Data Analysis Workflow ===\n")

# Agent function to safely execute R code and handle responses
llm_execute_r <- function(session_id, code, description = "") {
  cat("LLM Agent executing:", description, "\n")
  cat("Code:", substr(code, 1, 50), "...\n")
  
  result <- ellmer_execute_code(session_id, code)
  
  if (result$success) {
    cat("✓ Success - Output:", substr(paste(result$data$output, collapse = " "), 1, 100), "\n")
    if (length(result$data$warnings) > 0) {
      cat("⚠ Warnings:", paste(result$data$warnings, collapse = "; "), "\n")
    }
  } else {
    cat("✗ Failed:", result$message, "\n")
    cat("Errors:", paste(result$data$errors, collapse = "; "), "\n")
  }
  
  return(result)
}

# LLM Agent starts analysis
cat("\n1. Agent creates dedicated analysis session\n")
session_result <- ellmer_create_repl_session("llm_analysis_session")
if (!session_result$success) {
  stop("Could not create session: ", session_result$message)
}
session_id <- session_result$data$session_id
cat("Session created:", session_id, "\n")

# LLM Agent performs step-by-step analysis
cat("\n2. Load and explore dataset\n")
llm_execute_r(session_id, "
  # Load the mtcars dataset
  data(mtcars)
  cat('Dataset loaded with', nrow(mtcars), 'rows and', ncol(mtcars), 'columns\n')
  head(mtcars, 3)
", "Loading mtcars dataset")

cat("\n3. Basic data exploration\n")
llm_execute_r(session_id, "
  # Basic statistics
  summary(mtcars[c('mpg', 'hp', 'wt')])
", "Computing summary statistics")

cat("\n4. Data visualization setup\n")
llm_execute_r(session_id, "
  # Create correlation matrix
  cor_matrix <- cor(mtcars[c('mpg', 'hp', 'wt', 'qsec')])
  cat('Correlation between mpg and hp:', cor_matrix['mpg', 'hp'], '\n')
  cor_matrix
", "Computing correlations")

cat("\n5. Statistical modeling\n")
model_result <- llm_execute_r(session_id, "
  # Build regression model
  model <- lm(mpg ~ hp + wt + qsec, data = mtcars)
  model_summary <- summary(model)
  
  cat('Model R-squared:', model_summary$r.squared, '\n')
  cat('Model p-value:', pf(model_summary$fstatistic[1], 
                          model_summary$fstatistic[2], 
                          model_summary$fstatistic[3], 
                          lower.tail = FALSE), '\n')
  
  # Return key metrics
  list(
    r_squared = model_summary$r.squared,
    adj_r_squared = model_summary$adj.r.squared,
    coefficients = coef(model)
  )
", "Building regression model")

cat("\n6. Model validation\n")
llm_execute_r(session_id, "
  # Generate predictions and residuals
  predictions <- predict(model)
  residuals <- residuals(model)
  
  # Calculate RMSE
  rmse <- sqrt(mean(residuals^2))
  cat('Root Mean Square Error:', rmse, '\n')
  
  # Check assumptions
  shapiro_test <- shapiro.test(residuals)
  cat('Residuals normality test p-value:', shapiro_test$p.value, '\n')
  
  rmse
", "Validating model assumptions")

cat("\n7. Generate insights\n")
llm_execute_r(session_id, "
  # Extract key insights
  coef_summary <- summary(model)$coefficients
  
  cat('=== Model Insights ===\n')
  cat('Most significant predictors (p < 0.05):\n')
  
  significant <- coef_summary[coef_summary[,4] < 0.05, ]
  for(i in 1:nrow(significant)) {
    var_name <- rownames(significant)[i]
    coef_val <- significant[i, 1]
    p_val <- significant[i, 4]
    cat(sprintf('%s: coefficient = %.3f, p-value = %.4f\n', 
                var_name, coef_val, p_val))
  }
  
  'Analysis complete'
", "Extracting insights")

# LLM Agent checks session status
cat("\n8. Session management\n")
session_info <- ellmer_get_session_info(session_id)
if (session_info$success) {
  cat("Session", session_id, "status:\n")
  cat("  Alive:", session_info$data$is_alive, "\n")
  cat("  Port:", session_info$data$port, "\n")
  cat("  Started:", session_info$data$started_at, "\n")
}

# List all sessions (agent might have multiple analyses running)
sessions <- ellmer_list_sessions()
cat("Total active sessions:", sessions$data$count, "\n")

# LLM Agent cleans up when done
cat("\n9. Cleanup\n")
cleanup_result <- ellmer_stop_session(session_id)
if (cleanup_result$success) {
  cat("✓ Session", session_id, "stopped successfully\n")
} else {
  cat("✗ Failed to stop session:", cleanup_result$message, "\n")
}

# Verify cleanup
final_sessions <- ellmer_list_sessions()
cat("Remaining sessions after cleanup:", final_sessions$data$count, "\n")

cat("\n=== LLM Agent Analysis Complete ===\n")
cat("The LLM agent successfully:\n")
cat("- Created an isolated analysis environment\n") 
cat("- Performed step-by-step data analysis\n")
cat("- Built and validated a statistical model\n")
cat("- Generated insights from the results\n")
cat("- Cleaned up resources properly\n")
cat("\nAll operations used structured responses suitable for LLM processing!\n")