#' Conversation Logger for ellmer Chat Sessions
#'
#' This module provides functionality to log conversations with ellmer chat sessions
#' in markdown format. It captures user prompts, assistant responses, tool calls
#' (especially R code executions), and tool results.
#'
#' @section Usage:
#' Create a logger and attach it to an ellmer Chat object:
#' \preformatted{
#' library(ellmer)
#' library(replr)
#'
#' # Create a chat
#' chat <- chat_openai()
#'
#' # Create and attach logger
#' logger <- ConversationLogger$new(log_file = "conversation.md")
#' logger$attach(chat)
#'
#' # Use chat normally - logging happens automatically
#' chat$chat("What is 2+2?")
#'
#' # Save or retrieve the log
#' logger$save()
#' log_content <- logger$get_log()
#' }

#' Conversation Logger R6 Class
#'
#' @description
#' An R6 class that logs ellmer chat conversations in markdown format.
#' Captures prompts, responses, tool calls, and results.
#'
#' @export
ConversationLogger <- R6::R6Class(
  "ConversationLogger",
  public = list(
    #' @field log_file character, path to the log file (optional)
    log_file = NULL,

    #' @field auto_save logical, whether to automatically save after each turn
    auto_save = FALSE,

    #' @description
    #' Create a new ConversationLogger
    #'
    #' @param log_file character, path where the log should be saved (optional)
    #' @param auto_save logical, if TRUE, saves after each conversation turn
    #' @return A new ConversationLogger object
    initialize = function(log_file = NULL, auto_save = FALSE) {
      self$log_file <- log_file
      self$auto_save <- auto_save
      private$log_buffer <- character(0)
      private$session_start <- Sys.time()
      private$turn_count <- 0

      # Add header
      private$append_log(paste0("# Conversation Log\n\n"))
      private$append_log(paste0(
        "**Started:** ", format(private$session_start, "%Y-%m-%d %H:%M:%S"), "\n\n"
      ))
      private$append_log("---\n\n")
    },

    #' @description
    #' Attach the logger to an ellmer Chat object
    #'
    #' @param chat An ellmer Chat object
    #' @return self (invisibly)
    attach = function(chat) {
      if (!inherits(chat, "Chat")) {
        stop("Must provide an ellmer Chat object")
      }

      private$chat <- chat

      # Store the original chat method
      private$original_chat_method <- chat$chat

      # Wrap the chat method to log prompts and responses
      chat$chat <- private$create_chat_wrapper()

      # Register tool callbacks
      if ("on_tool_request" %in% names(chat)) {
        chat$on_tool_request(private$log_tool_request)
      }

      if ("on_tool_result" %in% names(chat)) {
        chat$on_tool_result(private$log_tool_result)
      }

      invisible(self)
    },

    #' @description
    #' Get the current log content
    #'
    #' @return character, the log content in markdown format
    get_log = function() {
      paste(private$log_buffer, collapse = "")
    },

    #' @description
    #' Save the log to a file
    #'
    #' @param file character, path to save the log (uses log_file if not provided)
    #' @return self (invisibly)
    save = function(file = NULL) {
      file_path <- file %||% self$log_file

      if (is.null(file_path)) {
        stop("No file path provided. Specify file parameter or set log_file in constructor.")
      }

      # Ensure directory exists
      dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)

      # Write log
      writeLines(self$get_log(), file_path)
      message("Log saved to: ", file_path)

      invisible(self)
    },

    #' @description
    #' Clear the log buffer
    #'
    #' @return self (invisibly)
    clear = function() {
      private$log_buffer <- character(0)
      private$turn_count <- 0
      private$session_start <- Sys.time()

      # Re-add header
      private$append_log(paste0("# Conversation Log\n\n"))
      private$append_log(paste0(
        "**Started:** ", format(private$session_start, "%Y-%m-%d %H:%M:%S"), "\n\n"
      ))
      private$append_log("---\n\n")

      invisible(self)
    }
  ),

  private = list(
    log_buffer = NULL,
    session_start = NULL,
    turn_count = NULL,
    chat = NULL,
    original_chat_method = NULL,
    current_tool_request = NULL,

    append_log = function(text) {
      private$log_buffer <- c(private$log_buffer, text)
    },

    create_chat_wrapper = function() {
      # Return a function that wraps the original chat method
      function(...) {
        private$turn_count <- private$turn_count + 1

        # Log the user prompt
        args <- list(...)
        if (length(args) > 0) {
          prompt <- args[[1]]
          if (is.character(prompt)) {
            private$append_log(paste0("## Turn ", private$turn_count, "\n\n"))
            private$append_log(paste0(
              "**Time:** ", format(Sys.time(), "%H:%M:%S"), "\n\n"
            ))
            private$append_log("### User\n\n")
            private$append_log(paste0(prompt, "\n\n"))
          }
        }

        # Call original method
        result <- private$original_chat_method(...)

        # Log the assistant response
        if (is.character(result)) {
          private$append_log("### Assistant\n\n")
          private$append_log(paste0(result, "\n\n"))
        }

        # Auto-save if enabled
        if (self$auto_save && !is.null(self$log_file)) {
          self$save()
        }

        result
      }
    },

    log_tool_request = function(request) {
      # Store for matching with result
      private$current_tool_request <- request

      # Log tool call
      private$append_log("### Tool Call\n\n")

      tool_name <- request$name %||% "unknown"
      private$append_log(paste0("**Tool:** `", tool_name, "`\n\n"))

      # Special handling for R code execution
      if (tool_name == "replr_execute_code") {
        args <- request$arguments %||% list()
        if (!is.null(args$code)) {
          private$append_log("**Code:**\n\n")
          private$append_log("```r\n")
          private$append_log(args$code)
          private$append_log("\n```\n\n")
        }
        if (!is.null(args$session_id)) {
          private$append_log(paste0("**Session:** ", args$session_id, "\n\n"))
        }
      } else if (tool_name == "replr_run_r_code") {
        args <- request$arguments %||% list()
        if (!is.null(args$code)) {
          private$append_log("**Code:**\n\n")
          private$append_log("```r\n")
          private$append_log(args$code)
          private$append_log("\n```\n\n")
        }
      } else {
        # Generic tool arguments
        args <- request$arguments %||% list()
        if (length(args) > 0) {
          private$append_log("**Arguments:**\n\n")
          private$append_log("```json\n")
          private$append_log(jsonlite::toJSON(args, pretty = TRUE, auto_unbox = TRUE))
          private$append_log("\n```\n\n")
        }
      }
    },

    log_tool_result = function(result) {
      # Log tool result
      private$append_log("### Tool Result\n\n")

      # Check if this is a replr tool result (standard format)
      if (is.list(result) && !is.null(result$success)) {
        private$append_log(paste0(
          "**Status:** ",
          if (result$success) "✓ Success" else "✗ Failed",
          "\n\n"
        ))

        if (!is.null(result$message)) {
          private$append_log(paste0("**Message:** ", result$message, "\n\n"))
        }

        # Special handling for execution results
        if (!is.null(result$data)) {
          data <- result$data

          # Output from code execution
          if (!is.null(data$output) && length(data$output) > 0) {
            private$append_log("**Output:**\n\n")
            private$append_log("```\n")
            private$append_log(paste(data$output, collapse = "\n"))
            private$append_log("\n```\n\n")
          }

          # Warnings
          if (!is.null(data$warnings) && length(data$warnings) > 0) {
            private$append_log("**Warnings:**\n\n")
            private$append_log("```\n")
            private$append_log(paste(data$warnings, collapse = "\n"))
            private$append_log("\n```\n\n")
          }

          # Errors
          if (!is.null(data$errors) && length(data$errors) > 0) {
            private$append_log("**Errors:**\n\n")
            private$append_log("```\n")
            private$append_log(paste(data$errors, collapse = "\n"))
            private$append_log("\n```\n\n")
          }

          # Plots
          if (!is.null(data$plots) && !is.null(data$plots$count) && data$plots$count > 0) {
            private$append_log(paste0(
              "**Plots:** ",
              data$plots$count,
              " plot(s) generated\n\n"
            ))
          }

          # Execution time
          if (!is.null(data$execution_time)) {
            private$append_log(paste0(
              "**Execution time:** ",
              round(data$execution_time, 3),
              " seconds\n\n"
            ))
          }
        }

        # Log error if present
        if (!is.null(result$error)) {
          private$append_log("**Error Details:**\n\n")
          private$append_log("```\n")
          private$append_log(paste(result$error, collapse = "\n"))
          private$append_log("\n```\n\n")
        }
      } else {
        # Generic result
        private$append_log("```json\n")
        private$append_log(jsonlite::toJSON(result, pretty = TRUE, auto_unbox = TRUE))
        private$append_log("\n```\n\n")
      }

      private$append_log("---\n\n")

      # Clear current request
      private$current_tool_request <- NULL
    }
  )
)

# Helper for NULL coalescing
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

#' Create a Conversation Logger
#'
#' Convenience function to create a new ConversationLogger instance
#'
#' @param log_file character, path where the log should be saved (optional)
#' @param auto_save logical, if TRUE, saves after each conversation turn
#' @return A new ConversationLogger object
#' @export
#' @examples
#' \dontrun{
#' # Create a logger
#' logger <- create_conversation_logger("chat_log.md", auto_save = TRUE)
#'
#' # Attach to a chat
#' chat <- ellmer::chat_openai()
#' logger$attach(chat)
#'
#' # Use chat - logging happens automatically
#' chat$chat("Hello!")
#' }
create_conversation_logger <- function(log_file = NULL, auto_save = FALSE) {
  ConversationLogger$new(log_file = log_file, auto_save = auto_save)
}
