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
#' library(repljail)
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
        "**Started:** ",
        format(private$session_start, "%Y-%m-%d %H:%M:%S"),
        "\n\n"
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

      # Unlock the binding to allow wrapping (R6 objects have locked bindings)
      unlockBinding("chat", chat)

      # Wrap the chat method to log prompts and responses
      chat$chat <- private$create_chat_wrapper()

      # Re-lock the binding to maintain R6 semantics
      lockBinding("chat", chat)

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
    #' @importFrom jsonlite toJSON
    save = function(file = NULL) {
      file_path <- file %||% self$log_file

      if (is.null(file_path)) {
        stop(
          "No file path provided. Specify file parameter or set log_file in constructor."
        )
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
        "**Started:** ",
        format(private$session_start, "%Y-%m-%d %H:%M:%S"),
        "\n\n"
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
              "**Time:** ",
              format(Sys.time(), "%H:%M:%S"),
              "\n\n"
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

      # Handle both S7 objects (use @) and regular lists (use $)
      tool_name <- if (inherits(request, "S7_object")) {
        request@name %||% "unknown"
      } else {
        request$name %||% "unknown"
      }
      private$append_log(paste0("**Tool:** `", tool_name, "`\n\n"))

      # Get arguments - handle both S7 and list
      args <- if (inherits(request, "S7_object")) {
        request@arguments %||% list()
      } else {
        request$arguments %||% list()
      }

      # Special handling for R code execution
      if (tool_name == "repljail_execute_code") {
        if (!is.null(args$code)) {
          private$append_log("**Code:**\n\n")
          private$append_log("```r\n")
          private$append_log(args$code)
          private$append_log("\n```\n\n")
        }
        if (!is.null(args$session_id)) {
          private$append_log(paste0("**Session:** ", args$session_id, "\n\n"))
        }
      } else if (tool_name == "repljail_run_r_code") {
        if (!is.null(args$code)) {
          private$append_log("**Code:**\n\n")
          private$append_log("```r\n")
          private$append_log(args$code)
          private$append_log("\n```\n\n")
        }
      } else {
        # Generic tool arguments
        if (length(args) > 0) {
          private$append_log("**Arguments:**\n\n")
          private$append_log("```json\n")
          private$append_log(toJSON(args, pretty = TRUE, auto_unbox = TRUE))
          private$append_log("\n```\n\n")
        }
      }
    },
    log_tool_result = function(result) {
      # Log tool result
      private$append_log("### Tool Result\n\n")

      # Handle S7 objects - extract properties using @ notation
      is_s7 <- inherits(result, "S7_object")

      # For ellmer ContentToolResult objects, extract the actual value
      # Check class name contains "ContentToolResult" (may have namespace prefix)
      if (is_s7 && any(grepl("ContentToolResult", class(result)))) {
        result <- tryCatch(slot(result, "value"), error = function(e) result)
        is_s7 <- inherits(result, "S7_object")
      }

      # Helper function to safely get property from S7 or list
      get_prop <- function(obj, name) {
        if (is_s7) {
          tryCatch(slot(obj, name), error = function(e) NULL)
        } else {
          obj[[name]]
        }
      }

      # Check if this is a repljail tool result (standard format)
      success_val <- get_prop(result, "success")
      if (!is.null(success_val)) {
        private$append_log(paste0(
          "**Status:** ",
          if (success_val) "\u2713 Success" else "\u2717 Failed",
          "\n\n"
        ))

        message_val <- get_prop(result, "message")
        if (!is.null(message_val)) {
          private$append_log(paste0("**Message:** ", message_val, "\n\n"))
        }

        # Special handling for execution results
        data <- get_prop(result, "data")
        if (!is.null(data)) {
          # Output from code execution
          output_val <- data$output
          if (!is.null(output_val) && length(output_val) > 0) {
            private$append_log("**Output:**\n\n")
            private$append_log("```\n")
            private$append_log(paste(output_val, collapse = "\n"))
            private$append_log("\n```\n\n")
          }

          # Warnings
          warnings_val <- data$warnings
          if (!is.null(warnings_val) && length(warnings_val) > 0) {
            private$append_log("**Warnings:**\n\n")
            private$append_log("```\n")
            private$append_log(paste(warnings_val, collapse = "\n"))
            private$append_log("\n```\n\n")
          }

          # Errors
          errors_val <- data$errors
          if (!is.null(errors_val) && length(errors_val) > 0) {
            private$append_log("**Errors:**\n\n")
            private$append_log("```\n")
            private$append_log(paste(errors_val, collapse = "\n"))
            private$append_log("\n```\n\n")
          }

          # Plots
          plots_val <- data$plots
          if (
            !is.null(plots_val) &&
              !is.null(plots_val$count) &&
              plots_val$count > 0
          ) {
            private$append_log(paste0(
              "**Plots:** ",
              plots_val$count,
              " plot(s) generated\n\n"
            ))

            # Embed plot images using file_paths if available, otherwise fall back to data_urls
            if (
              !is.null(plots_val$file_paths) && length(plots_val$file_paths) > 0
            ) {
              for (i in seq_along(plots_val$file_paths)) {
                temp_file_path <- plots_val$file_paths[[i]]

                # Copy the temp file to the log directory if log_file is set
                final_path <- temp_file_path
                if (!is.null(self$log_file)) {
                  log_dir <- normalizePath(dirname(self$log_file))
                  log_basename <- tools::file_path_sans_ext(basename(
                    self$log_file
                  ))

                  # Create a unique filename for the plot
                  plot_filename <- paste0(
                    log_basename,
                    "_plot_",
                    format(Sys.time(), "%Y%m%d_%H%M%S"),
                    "_",
                    i,
                    ".png"
                  )
                  final_path <- file.path(log_dir, plot_filename)

                  # Copy the temp file to the log directory
                  stopifnot(file.copy(
                    temp_file_path,
                    final_path,
                    overwrite = TRUE
                  ))

                  # Use relative path for markdown (just the filename)
                  final_path <- plot_filename
                }

                private$append_log(paste0("**Plot ", i, ":**\n\n"))
                private$append_log(paste0(
                  "![Plot ",
                  i,
                  "](",
                  basename(final_path),
                  ")\n\n"
                ))
              }
            } else if (
              !is.null(plots_val$data_urls) && length(plots_val$data_urls) > 0
            ) {
              # Fallback to data URLs if file paths not available
              for (i in seq_along(plots_val$data_urls)) {
                private$append_log(paste0("**Plot ", i, ":**\n\n"))
                private$append_log(paste0(
                  "![Plot ",
                  i,
                  "](",
                  plots_val$data_urls[[i]],
                  ")\n\n"
                ))
              }
            }
          }

          # Execution time
          exec_time <- data$execution_time
          if (!is.null(exec_time)) {
            private$append_log(paste0(
              "**Execution time:** ",
              round(exec_time, 3),
              " seconds\n\n"
            ))
          }
        }

        # Log error if present
        error_val <- get_prop(result, "error")
        if (!is.null(error_val)) {
          private$append_log("**Error Details:**\n\n")
          private$append_log("```\n")
          private$append_log(paste(error_val, collapse = "\n"))
          private$append_log("\n```\n\n")
        }
      } else {
        # Generic result - try to convert to something JSON-serializable
        result_for_json <- if (is_s7) {
          # For S7 objects, try to extract a reasonable representation
          tryCatch(
            {
              # Try to get all slot names and values
              list(
                result = paste(capture.output(print(result)), collapse = "\n")
              )
            },
            error = function(e) {
              list(result = "S7 object (cannot serialize)")
            }
          )
        } else {
          result
        }
        private$append_log("```json\n")
        private$append_log(toJSON(
          result_for_json,
          pretty = TRUE,
          auto_unbox = TRUE
        ))
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
