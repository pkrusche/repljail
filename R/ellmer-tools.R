#' replr Tools for REPL Session Management
#'
#' This module provides tools designed specifically for LLM agents (e.g. in ellmer) to
#' create, manage, and use isolated R REPL sessions. These functions provide
#' a standardized interface with session tracking and structured responses
#' optimized for LLM consumption.
#'
#' @section Session Management:
#' The replr tools maintain a global registry of active REPL sessions,
#' allowing LLM agents to create multiple concurrent sessions and manage
#' them independently.
#'
#' @section Response Format:
#' All replr tools return standardized responses with the following structure:
#' \itemize{
#'   \item \code{success} - logical, whether the operation succeeded
#'   \item \code{message} - character, human-readable status message
#'   \item \code{data} - list, operation-specific data (when applicable)
#'   \item \code{error} - character, error message (when applicable)
#' }

# Global session registry for replr tools
.replr_sessions <- new.env(parent = emptyenv())

#' Create a New REPL Session for replr
#'
#' Creates a new isolated R REPL session that can be used by an LLM agent.
#' Each session runs in a separate R process and maintains its own environment.
#' Session names are automatically generated with a friendly format.
#'
#' @param timeout numeric, timeout in seconds for session startup (default: 10)
#' @return list with success status, session information, and any errors
#' @export
#' @examples
#' \dontrun{
#' # Create a new session with auto-generated ID
#' result <- replr_create_repl_session()
#' if (result$success) {
#'   session_id <- result$data$session_id
#'   cat("Created session:", session_id)
#' }
#' }
replr_create_repl_session <- function(timeout = 10) {
  tryCatch(
    {
      # Auto-generate session ID
      session_id <- NULL
      counter <- 1
      while (
        is.null(session_id) ||
          (exists(session_id, envir = .replr_sessions) && counter < 10)
      ) {
        session_id <- paste0(
          sample(
            c(
              "red",
              "blue",
              "green",
              "purple",
              "orange",
              "yellow",
              "pink",
              "cyan"
            ),
            1
          ),
          "-",
          sample(
            c(
              "eagle",
              "tiger",
              "dolphin",
              "falcon",
              "wolf",
              "bear",
              "fox",
              "owl"
            ),
            1
          ),
          "-",
          sample(100:999, 1)
        )
        counter <- counter + 1
      }

      # Create new REPL session with Docker if available
      session <- replr::RREPLSession$new(timeout = timeout)

      # Store in registry
      assign(session_id, session, envir = .replr_sessions)

      # Get session information
      session_info <- session$get_info()

      list(
        success = TRUE,
        message = paste(
          "Successfully created REPL session:",
          session_id,
          if (session_info$is_docker) "(using Docker)" else "(native)"
        ),
        data = list(
          session_id = session_id,
          port = session_info$port,
          pid = session_info$pid,
          started_at = as.character(session_info$started_at),
          is_alive = session$is_alive(),
          using_docker = session_info$is_docker
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Failed to create REPL session:", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Execute R Code in a REPL Session
#'
#' Executes R code in a specified replr REPL session and returns the results
#' in a structured format suitable for LLM processing.
#'
#' @param session_id character, ID of the session to execute code in
#' @param code character, R code to execute
#' @param timeout numeric, timeout in seconds for code execution (default: 30)
#' @return list with execution results, output, warnings, errors, and success status
#' @export
#' @examples
#' \dontrun{
#' # Create a session and execute code
#' session_result <- replr_create_repl_session()
#' session_id <- session_result$data$session_id
#'
#' # Execute simple arithmetic
#' result <- replr_execute_code(session_id, "2 + 2")
#' if (result$success) {
#'   cat("Output:", result$data$output)
#' }
#'
#' # Execute more complex code
#' result <- replr_execute_code(session_id, "
#'   data <- data.frame(x = 1:5, y = letters[1:5])
#'   summary(data)
#' ")
#' }
replr_execute_code <- function(session_id, code, timeout = 30) {
  tryCatch(
    {
      # Check if session exists
      if (!exists(session_id, envir = .replr_sessions)) {
        return(list(
          success = FALSE,
          message = paste("Session not found:", session_id),
          data = NULL,
          error = "SESSION_NOT_FOUND"
        ))
      }

      # Get session
      session <- get(session_id, envir = .replr_sessions)

      # Check if session is still alive
      if (!session$is_alive()) {
        return(list(
          success = FALSE,
          message = paste("Session is not alive:", session_id),
          data = NULL,
          error = "SESSION_DEAD"
        ))
      }

      # Execute code
      result <- session$execute(code, timeout = timeout)

      # write plots to temp file locations
      plot_files <- list()
      for (plot_base64 in result$result$plots) {
        plot_data <- sub("^data:image/png;base64,", "", plot_base64)
        plot_raw <- base64enc::base64decode(plot_data)

        temp_filename <- tempfile(fileext = ".png")
        temp_file <- file(temp_filename, "wb")
        writeBin(plot_raw, temp_file)
        close(temp_file)
        # This doesn't work because ellmer does not serialize these to JSON
        # plot_files <- append(plot_files, list(ellmer::content_image_file(temp_filename)))  # nolint
        plot_files <- append(plot_files, list(temp_filename))
        # rm on session exit
        # TODO: better way would be to keep a list of temp files per session and clean up when session is stopped
        on.exit(unlink(temp_filename), add = TRUE)
      }

      # Extract and structure the results
      execution_data <- list(
        session_id = session_id,
        status = result$status,
        output = result$result$output,
        warnings = result$result$warnings,
        errors = result$result$errors,
        visible = result$result$visible,
        plots = list(
          count = length(result$result$plots),
          data_urls = result$result$plots,
          file_paths = plot_files
        ),
        execution_time = result$execution_time,
        request_id = result$id
      )
      debug_log("{execution_data}")

      # Determine overall success
      is_success <- result$status == "success"

      list(
        success = is_success,
        message = if (is_success) {
          "Code executed successfully"
        } else {
          paste(
            "Code execution failed:",
            paste(result$result$errors, collapse = "; ")
          )
        },
        data = execution_data,
        error = if (!is_success) result$result$errors else NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste(
          "Error executing code in session",
          session_id,
          ":",
          e$message
        ),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Get Information About a REPL Session
#'
#' Retrieves detailed information about a specific replr REPL session,
#' including its status, process information, and activity.
#'
#' @param session_id character, ID of the session to query
#' @return list with session information and status
#' @export
#' @examples
#' \dontrun{
#' # Get information about a session
#' result <- replr_get_session_info("my_session_id")
#' if (result$success) {
#'   print(result$data)
#' }
#' }
replr_get_session_info <- function(session_id) {
  tryCatch(
    {
      # Check if session exists
      if (!exists(session_id, envir = .replr_sessions)) {
        return(list(
          success = FALSE,
          message = paste("Session not found:", session_id),
          data = NULL,
          error = "SESSION_NOT_FOUND"
        ))
      }

      # Get session
      session <- get(session_id, envir = .replr_sessions)

      # Get session information
      session_info <- session$get_info()

      list(
        success = TRUE,
        message = paste("Retrieved information for session:", session_id),
        data = list(
          session_id = session_id,
          port = session_info$port,
          pid = session_info$pid,
          started_at = as.character(session_info$started_at),
          is_alive = session_info$is_alive,
          stopped = session_info$stopped
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste(
          "Error getting session info for",
          session_id,
          ":",
          e$message
        ),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Stop a REPL Session
#'
#' Gracefully stops a specified replr REPL session and removes it from
#' the session registry.
#'
#' @param session_id character, ID of the session to stop
#' @param timeout numeric, timeout in seconds for graceful shutdown (default: 5)
#' @return list with stop operation status
#' @export
#' @examples
#' \dontrun{
#' # Stop a specific session
#' result <- replr_stop_session("my_session_id")
#' if (result$success) {
#'   cat("Session stopped successfully")
#' }
#' }
replr_stop_session <- function(session_id, timeout = 5) {
  tryCatch(
    {
      # Check if session exists
      if (!exists(session_id, envir = .replr_sessions)) {
        return(list(
          success = FALSE,
          message = paste("Session not found:", session_id),
          data = NULL,
          error = "SESSION_NOT_FOUND"
        ))
      }

      # Get session
      session <- get(session_id, envir = .replr_sessions)

      # Stop the session
      stop_result <- session$stop(timeout = timeout)

      # Remove from registry
      rm(list = session_id, envir = .replr_sessions)

      list(
        success = TRUE,
        message = paste(
          "Successfully stopped and removed session:",
          session_id
        ),
        data = list(
          session_id = session_id,
          stopped_successfully = stop_result
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error stopping session", session_id, ":", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' List All Active REPL Sessions
#'
#' Returns a list of all currently active replr REPL sessions with their
#' basic information.
#'
#' @return list with information about all active sessions
#' @export
#' @examples
#' \dontrun{
#' # List all active sessions
#' result <- replr_list_sessions()
#' if (result$success) {
#'   for (session in result$data$sessions) {
#'     cat("Session:", session$session_id, "- Alive:", session$is_alive, "\n")
#'   }
#' }
#' }
replr_list_sessions <- function() {
  tryCatch(
    {
      session_ids <- ls(envir = .replr_sessions)

      if (length(session_ids) == 0) {
        return(list(
          success = TRUE,
          message = "No active sessions found",
          data = list(
            count = 0,
            sessions = list()
          ),
          error = NULL
        ))
      }

      # Collect information about all sessions
      sessions_info <- list()
      for (session_id in session_ids) {
        session <- get(session_id, envir = .replr_sessions)
        session_info <- session$get_info()

        sessions_info[[length(sessions_info) + 1]] <- list(
          session_id = session_id,
          port = session_info$port,
          pid = session_info$pid,
          started_at = as.character(session_info$started_at),
          is_alive = session_info$is_alive,
          stopped = session_info$stopped
        )
      }

      list(
        success = TRUE,
        message = paste("Found", length(session_ids), "active sessions"),
        data = list(
          count = length(session_ids),
          sessions = sessions_info
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error listing sessions:", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Clean Up Dead REPL Sessions
#'
#' Removes dead sessions from the replr session registry. This is useful
#' for cleanup when sessions may have died unexpectedly.
#'
#' @return list with cleanup results
#' @export
#' @examples
#' \dontrun{
#' # Clean up any dead sessions
#' result <- replr_cleanup_sessions()
#' cat("Cleaned up", result$data$cleaned_count, "dead sessions")
#' }
replr_cleanup_sessions <- function() {
  tryCatch(
    {
      session_ids <- ls(envir = .replr_sessions)
      cleaned_count <- 0
      dead_sessions <- character(0)

      for (session_id in session_ids) {
        session <- get(session_id, envir = .replr_sessions)

        if (!session$is_alive()) {
          # Try to stop it gracefully first
          tryCatch(session$stop(timeout = 1), error = function(e) {})

          # Remove from registry
          rm(list = session_id, envir = .replr_sessions)
          cleaned_count <- cleaned_count + 1
          dead_sessions <- c(dead_sessions, session_id)
        }
      }

      list(
        success = TRUE,
        message = paste("Cleaned up", cleaned_count, "dead sessions"),
        data = list(
          cleaned_count = cleaned_count,
          dead_sessions = dead_sessions,
          remaining_sessions = length(ls(envir = .replr_sessions))
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error during cleanup:", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Stop All REPL Sessions
#'
#' Stops all active replr REPL sessions and clears the session registry.
#' Useful for cleanup at the end of an LLM agent session.
#'
#' @param timeout numeric, timeout in seconds for each session shutdown (default: 5)
#' @return list with shutdown results
#' @export
#' @examples
#' \dontrun{
#' # Stop all sessions at the end of analysis
#' result <- replr_stop_all_sessions()
#' cat("Stopped", result$data$stopped_count, "sessions")
#' }
replr_stop_all_sessions <- function(timeout = 5) {
  tryCatch(
    {
      session_ids <- ls(envir = .replr_sessions)
      stopped_count <- 0
      errors <- character(0)

      for (session_id in session_ids) {
        tryCatch(
          {
            session <- get(session_id, envir = .replr_sessions)
            session$stop(timeout = timeout)
            stopped_count <- stopped_count + 1
          },
          error = function(e) {
            errors <<- c(errors, paste(session_id, ":", e$message))
          }
        )
      }

      # Clear the entire registry
      rm(list = ls(envir = .replr_sessions), envir = .replr_sessions)

      list(
        success = length(errors) == 0,
        message = paste("Stopped", stopped_count, "sessions"),
        data = list(
          stopped_count = stopped_count,
          total_sessions = length(session_ids),
          errors = errors
        ),
        error = if (length(errors) > 0) errors else NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error stopping all sessions:", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Run R Code (Simple Interface)
#'
#' Executes R code in a temporary isolated REPL session. This is a simplified
#' interface that creates a session, executes the code, and stops the session
#' automatically. Ideal for one-off code execution without manual session management.
#'
#' @param code character, R code to execute
#' @param timeout numeric, timeout in seconds for code execution (default: 30)
#' @return list with execution results, output, warnings, errors, and success status
#' @export
#' @examples
#' \dontrun{
#' # Execute simple arithmetic
#' result <- replr_run_r_code("2 + 2")
#' if (result$success) {
#'   cat("Output:", result$data$output)
#' }
#'
#' # Execute more complex code
#' result <- replr_run_r_code("
#'   data <- data.frame(x = 1:5, y = letters[1:5])
#'   summary(data)
#' ")
#' }
replr_run_r_code <- function(code, timeout = 30) {
  session_result <- NULL
  session_id <- NULL

  # Use timeout for session creation and cleanup as well
  # Session creation gets a reasonable fraction of total timeout
  session_timeout <- min(timeout, 10)
  # Cleanup gets a short timeout since it's just sending a shutdown signal
  cleanup_timeout <- min(timeout / 6, 5)

  tryCatch(
    {
      # Create a temporary session
      session_result <- replr_create_repl_session(timeout = session_timeout)

      if (!session_result$success) {
        return(list(
          success = FALSE,
          message = paste("Failed to create session:", session_result$message),
          data = NULL,
          error = session_result$error
        ))
      }

      session_id <- session_result$data$session_id

      # Execute the code
      exec_result <- replr_execute_code(session_id, code, timeout = timeout)

      # Return the execution result
      exec_result
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error running R code:", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    },
    finally = {
      # Always clean up the session
      if (!is.null(session_id)) {
        tryCatch(
          {
            replr_stop_session(session_id, timeout = cleanup_timeout)
          },
          error = function(e) {
            # Silent cleanup - session may already be dead
          }
        )
      }
    }
  )
}

# ellmer Tool Definitions
# These tools wrap the replr functions to provide a standardized interface for LLM agents

#' Create REPL Session Tool Definition
#'
#' Returns an ellmer tool definition for creating new REPL sessions.
#' This function provides the tool metadata that LLM agents need to
#' understand how to create isolated R sessions.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' create_tool <- replr_create_repl_session_tool()
#' print(create_tool$name)
#' print(create_tool$description)
#' }
replr_create_repl_session_tool <- function() {
  # Try to use ellmer::tool if available, otherwise return a basic structure
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_create_repl_session,
      name = "replr_create_repl_session",
      description = "Create a new isolated R REPL session for executing R code",
      arguments = list(
        timeout = ellmer::type_number(
          "Timeout in seconds for session startup",
          required = FALSE
        )
      )
    )
  } else {
    # Fallback structure if ellmer is not available
    list(
      name = "replr_create_repl_session",
      description = "Create a new isolated R REPL session for executing R code",
      parameters = list(
        timeout = list(
          type = "number",
          description = "Timeout in seconds",
          default = 10
        )
      ),
      fn = replr_create_repl_session
    )
  }
}

#' Execute Code Tool Definition
#'
#' Returns an ellmer tool definition for executing R code in REPL sessions.
#' This function provides the tool metadata that LLM agents need to
#' understand how to execute code in isolated R environments.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' execute_tool <- replr_execute_code_tool()
#' print(execute_tool$name)
#' }
replr_execute_code_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_execute_code,
      name = "replr_execute_code",
      description = paste0(
        "Execute R code in an isolated REPL session and return structured results.",
        " When creating plots in the code, they will be converted to data URLs in ",
        "the structured output for compatibility with vision models."
      ),
      arguments = list(
        session_id = ellmer::type_string(
          "ID of the session to execute code in",
          required = TRUE
        ),
        code = ellmer::type_string(
          "R code to execute in the session",
          required = TRUE
        ),
        timeout = ellmer::type_number(
          "Timeout in seconds for code execution",
          required = FALSE
        )
      )
    )
  } else {
    list(
      name = "replr_execute_code",
      description = paste0(
        "Execute R code in an isolated REPL session and return structured results.",
        " When creating plots in the code, they will be converted to data URLs in ",
        "the structured output for compatibility with vision models."
      ),
      parameters = list(
        session_id = list(
          type = "string",
          description = "Session ID",
          required = TRUE
        ),
        code = list(
          type = "string",
          description = "R code to execute",
          required = TRUE
        ),
        timeout = list(
          type = "number",
          description = "Timeout in seconds",
          default = 30
        )
      ),
      fn = replr_execute_code
    )
  }
}

#' Get Session Info Tool Definition
#'
#' Returns an ellmer tool definition for retrieving REPL session information.
#' This function provides the tool metadata that LLM agents need to
#' understand how to query session status and details.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' info_tool <- replr_get_session_info_tool()
#' print(info_tool$description)
#' }
replr_get_session_info_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_get_session_info,
      name = "replr_get_session_info",
      description = "Get detailed information about a REPL session including status and process info",
      arguments = list(
        session_id = ellmer::type_string(
          "ID of the session to query",
          required = TRUE
        )
      )
    )
  } else {
    list(
      name = "replr_get_session_info",
      description = "Get detailed information about a REPL session including status and process info",
      parameters = list(
        session_id = list(
          type = "string",
          description = "Session ID",
          required = TRUE
        )
      ),
      fn = replr_get_session_info
    )
  }
}

#' List Sessions Tool Definition
#'
#' Returns an ellmer tool definition for listing all active REPL sessions.
#' This function provides the tool metadata that LLM agents need to
#' understand how to enumerate active sessions.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' list_tool <- replr_list_sessions_tool()
#' print(list_tool$name)
#' }
replr_list_sessions_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_list_sessions,
      name = "replr_list_sessions",
      description = "List all active REPL sessions with their status and information",
      arguments = list()
    )
  } else {
    list(
      name = "replr_list_sessions",
      description = "List all active REPL sessions with their status and information",
      parameters = list(),
      fn = replr_list_sessions
    )
  }
}

#' Stop Session Tool Definition
#'
#' Returns an ellmer tool definition for stopping specific REPL sessions.
#' This function provides the tool metadata that LLM agents need to
#' understand how to gracefully stop and clean up sessions.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' stop_tool <- replr_stop_session_tool()
#' print(stop_tool$description)
#' }
replr_stop_session_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_stop_session,
      name = "replr_stop_session",
      description = "Stop a specific REPL session and remove it from the registry",
      arguments = list(
        session_id = ellmer::type_string(
          "ID of the session to stop",
          required = TRUE
        ),
        timeout = ellmer::type_number(
          "Timeout in seconds for graceful shutdown",
          required = FALSE
        )
      )
    )
  } else {
    list(
      name = "replr_stop_session",
      description = "Stop a specific REPL session and remove it from the registry",
      parameters = list(
        session_id = list(
          type = "string",
          description = "Session ID",
          required = TRUE
        ),
        timeout = list(
          type = "number",
          description = "Timeout in seconds",
          default = 5
        )
      ),
      fn = replr_stop_session
    )
  }
}

#' Cleanup Sessions Tool Definition
#'
#' Returns an ellmer tool definition for cleaning up dead REPL sessions.
#' This function provides the tool metadata that LLM agents need to
#' understand how to remove dead sessions from the registry.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' cleanup_tool <- replr_cleanup_sessions_tool()
#' print(cleanup_tool$name)
#' }
replr_cleanup_sessions_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_cleanup_sessions,
      name = "replr_cleanup_sessions",
      description = "Remove dead sessions from the registry to clean up resources",
      arguments = list()
    )
  } else {
    list(
      name = "replr_cleanup_sessions",
      description = "Remove dead sessions from the registry to clean up resources",
      parameters = list(),
      fn = replr_cleanup_sessions
    )
  }
}

#' Stop All Sessions Tool Definition
#'
#' Returns an ellmer tool definition for stopping all active REPL sessions.
#' This function provides the tool metadata that LLM agents need to
#' understand how to perform complete session cleanup.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' stop_all_tool <- replr_stop_all_sessions_tool()
#' print(stop_all_tool$description)
#' }
replr_stop_all_sessions_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_stop_all_sessions,
      name = "replr_stop_all_sessions",
      description = "Stop all active REPL sessions and clear the session registry",
      arguments = list(
        timeout = ellmer::type_number(
          "Timeout in seconds for each session shutdown",
          required = FALSE
        )
      )
    )
  } else {
    list(
      name = "replr_stop_all_sessions",
      description = "Stop all active REPL sessions and clear the session registry",
      parameters = list(
        timeout = list(
          type = "number",
          description = "Timeout in seconds",
          default = 5
        )
      ),
      fn = replr_stop_all_sessions
    )
  }
}

#' Run R Code Tool Definition
#'
#' Returns an ellmer tool definition for executing R code in a temporary session.
#' This function provides the tool metadata that LLM agents need to
#' understand how to execute R code without manual session management.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' run_tool <- replr_run_r_code_tool()
#' print(run_tool$name)
#' print(run_tool$description)
#' }
replr_run_r_code_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_run_r_code,
      name = "replr_run_r_code",
      description = paste0(
        "Execute R code in a temporary isolated REPL session. ",
        "The session is automatically created and cleaned up after execution. ",
        "This is a simple interface for one-off R code execution without manual session management. ",
        "When creating plots in the code, they will be converted to data URLs in ",
        "the structured output for compatibility with vision models."
      ),
      arguments = list(
        code = ellmer::type_string(
          "R code to execute in the temporary session",
          required = TRUE
        ),
        timeout = ellmer::type_number(
          "Timeout in seconds for code execution",
          required = FALSE
        )
      )
    )
  } else {
    list(
      name = "replr_run_r_code",
      description = paste0(
        "Execute R code in a temporary isolated REPL session. ",
        "The session is automatically created and cleaned up after execution. ",
        "This is a simple interface for one-off R code execution without manual session management. ",
        "When creating plots in the code, they will be converted to data URLs in ",
        "the structured output for compatibility with vision models."
      ),
      parameters = list(
        code = list(
          type = "string",
          description = "R code to execute",
          required = TRUE
        ),
        timeout = list(
          type = "number",
          description = "Timeout in seconds",
          default = 30
        )
      ),
      fn = replr_run_r_code
    )
  }
}

#' Check R Code Syntax
#'
#' Validates the syntax of R code without executing it. This function
#' parses the code to check for syntax errors but does not run it,
#' making it safe for checking potentially problematic code.
#'
#' @param code character, R code to check for syntax errors
#' @return list with syntax validation results and any error messages
#' @export
#' @examples
#' \dontrun{
#' # Check valid code
#' result <- replr_check_syntax("x <- 1 + 2\nprint(x)")
#' if (result$success) {
#'   cat("Valid syntax with", result$data$expression_count, "expressions\n")
#' }
#'
#' # Check invalid code
#' result <- replr_check_syntax("x <- mean(c(1, 2, 3)")
#' if (!result$success) {
#'   cat("Syntax error:", result$error, "\n")
#' }
#' }
replr_check_syntax <- function(code) {
  tryCatch(
    {
      # Parse the code without executing it
      parsed <- parse(text = code, keep.source = TRUE)

      list(
        success = TRUE,
        message = "Code syntax is valid",
        data = list(
          valid = TRUE,
          expression_count = length(parsed),
          code = code
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Syntax error:", e$message),
        data = list(
          valid = FALSE,
          code = code,
          error_details = as.character(e$message)
        ),
        error = as.character(e$message)
      )
    }
  )
}

#' Check R Code Syntax Tool Definition
#'
#' Returns an ellmer tool definition for checking R code syntax without execution.
#' This function provides the tool metadata that LLM agents need to
#' understand how to validate R code syntax safely.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' syntax_tool <- replr_check_syntax_tool()
#' print(syntax_tool$name)
#' print(syntax_tool$description)
#' }
replr_check_syntax_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_check_syntax,
      name = "replr_check_syntax",
      description = paste0(
        "Check R code for syntax errors without executing it. ",
        "This is useful for validating code before execution, ",
        "catching syntax problems early, or checking code from untrusted sources. ",
        "The code is parsed but never run, making this operation completely safe."
      ),
      arguments = list(
        code = ellmer::type_string(
          "R code to check for syntax errors",
          required = TRUE
        )
      )
    )
  } else {
    list(
      name = "replr_check_syntax",
      description = paste0(
        "Check R code for syntax errors without executing it. ",
        "This is useful for validating code before execution, ",
        "catching syntax problems early, or checking code from untrusted sources. ",
        "The code is parsed but never run, making this operation completely safe."
      ),
      parameters = list(
        code = list(
          type = "string",
          description = "R code to check for syntax errors",
          required = TRUE
        )
      ),
      fn = replr_check_syntax
    )
  }
}

#' Lint R Code Without Executing It
#'
#' Analyzes R code for style issues and potential problems using the lintr package
#' without executing the code. This is useful for checking code quality and
#' identifying potential issues before execution.
#'
#' @param code character, R code to lint
#' @param linters character vector, optional linters to use. If NULL, uses default linters.
#'   Common linters include: "trailing_whitespace_linter", "line_length_linter",
#'   "object_name_linter", "assignment_linter", etc.
#' @return list with lint results and success status
#' @export
#' @examples
#' \dontrun{
#' # Lint simple code
#' result <- replr_lint_code("x = 1")
#' if (result$success) {
#'   print(result$data$lints)
#' }
#'
#' # Lint code with specific linters
#' result <- replr_lint_code(
#'   "my_var <- 1",
#'   linters = c("object_name_linter", "line_length_linter")
#' )
#' }
replr_lint_code <- function(code, linters = NULL) {
  tryCatch(
    {
      # Check if lintr is available
      if (!requireNamespace("lintr", quietly = TRUE)) {
        return(list(
          success = FALSE,
          message = "lintr package is not installed. Install it with: install.packages('lintr')",
          data = NULL,
          error = "LINTR_NOT_AVAILABLE"
        ))
      }

      # Write code to a temporary file for linting
      temp_file <- tempfile(fileext = ".R")
      on.exit(unlink(temp_file), add = TRUE)
      writeLines(code, temp_file)

      # Prepare linters
      if (is.null(linters)) {
        # Use default linters
        lint_results <- lintr::lint(temp_file)
      } else {
        # Build linter list from names
        linter_list <- list()
        for (linter_name in linters) {
          # Try to get the linter function
          linter_func <- tryCatch(
            get(linter_name, envir = asNamespace("lintr"), mode = "function"),
            error = function(e) NULL
          )
          if (!is.null(linter_func)) {
            linter_list[[linter_name]] <- linter_func()
          }
        }
        lint_results <- lintr::lint(temp_file, linters = linter_list)
      }

      # Convert lint results to a structured format
      lints <- list()
      if (length(lint_results) > 0) {
        for (i in seq_along(lint_results)) {
          lint <- lint_results[[i]]
          lints[[i]] <- list(
            line = lint$line_number,
            column = lint$column_number,
            type = lint$type,
            message = lint$message,
            linter = lint$linter,
            line_content = lint$line
          )
        }
      }

      list(
        success = TRUE,
        message = if (length(lints) == 0) {
          "No linting issues found"
        } else {
          paste("Found", length(lints), "linting issue(s)")
        },
        data = list(
          code = code,
          lint_count = length(lints),
          lints = lints
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error linting code:", e$message),
        data = NULL,
        error = as.character(e$message)
      )
    }
  )
}

#' Lint Code Tool Definition
#'
#' Returns an ellmer tool definition for linting R code without execution.
#' This function provides the tool metadata that LLM agents need to
#' understand how to check code quality using lintr.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' lint_tool <- replr_lint_code_tool()
#' print(lint_tool$name)
#' print(lint_tool$description)
#' }
replr_lint_code_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_lint_code,
      name = "replr_lint_code",
      description = paste0(
        "Analyze R code for style issues and potential problems using lintr without executing it. ",
        "This is useful for checking code quality, identifying potential issues, ",
        "and ensuring code follows best practices before execution. ",
        "Returns a structured list of linting issues including line numbers, messages, and types."
      ),
      arguments = list(
        code = ellmer::type_string(
          "R code to lint and analyze for style issues",
          required = TRUE
        ),
        linters = ellmer::type_array(
          "Optional list of specific linter names to use (e.g., ['line_length_linter', 'object_name_linter']). If not provided, uses default linters.",
          required = FALSE
        )
      )
    )
  } else {
    list(
      name = "replr_lint_code",
      description = paste0(
        "Analyze R code for style issues and potential problems using lintr without executing it. ",
        "This is useful for checking code quality, identifying potential issues, ",
        "and ensuring code follows best practices before execution. ",
        "Returns a structured list of linting issues including line numbers, messages, and types."
      ),
      parameters = list(
        code = list(
          type = "string",
          description = "R code to lint",
          required = TRUE
        ),
        linters = list(
          type = "array",
          description = "Optional list of linter names",
          required = FALSE
        )
      ),
      fn = replr_lint_code
    )
  }
}
