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
#'
#' @param session_id character, optional custom session ID. If NULL, a UUID will be generated.
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
#'
#' # Create a session with custom ID
#' result <- replr_create_repl_session("my_analysis_session")
#' }
replr_create_repl_session <- function(session_id = NULL, timeout = 10) {
  tryCatch(
    {
      # Generate session ID if not provided
      if (is.null(session_id)) {
        session_id <- uuid::UUIDgenerate()
      }

      # Check if session ID already exists
      if (exists(session_id, envir = .replr_sessions)) {
        return(list(
          success = FALSE,
          message = paste("Session ID already exists:", session_id),
          data = NULL,
          error = "DUPLICATE_SESSION_ID"
        ))
      }

      # Auto-detect Docker availability for LLM tools
      use_docker <- is_docker_available()
      
      # Create new REPL session with Docker if available
      session <- RREPLSession$new(timeout = timeout, use_docker = use_docker)

      # Store in registry
      assign(session_id, session, envir = .replr_sessions)

      # Get session information
      session_info <- session$get_info()

      list(
        success = TRUE,
        message = paste("Successfully created REPL session:", session_id, 
                       if (use_docker) "(using Docker)" else "(native)"),
        data = list(
          session_id = session_id,
          port = session_info$port,
          pid = session_info$pid,
          started_at = as.character(session_info$started_at),
          is_alive = session$is_alive(),
          using_docker = use_docker
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

#' Create a New REPL Session with Docker Control
#'
#' Creates a new isolated R REPL session with explicit Docker container control.
#' This function allows users to explicitly choose whether to use Docker containers.
#'
#' @param session_id character, optional custom session ID. If NULL, a UUID will be generated.
#' @param timeout numeric, timeout in seconds for session startup (default: 10)
#' @param use_docker logical, whether to use Docker containers (default: auto-detect)
#' @return list with success status, session information, and any errors
#' @export
#' @examples
#' \dontrun{
#' # Create a session with Docker explicitly enabled
#' result <- replr_create_repl_session_docker("analysis", use_docker = TRUE)
#' if (result$success) {
#'   session_id <- result$data$session_id
#'   cat("Created session with Docker:", session_id)
#' }
#' }
replr_create_repl_session_docker <- function(session_id = NULL, timeout = 10, use_docker = NULL) {
  tryCatch(
    {
      # Generate session ID if not provided
      if (is.null(session_id)) {
        session_id <- uuid::UUIDgenerate()
      }

      # Check if session ID already exists
      if (exists(session_id, envir = .replr_sessions)) {
        return(list(
          success = FALSE,
          message = paste("Session ID already exists:", session_id),
          data = NULL,
          error = "DUPLICATE_SESSION_ID"
        ))
      }

      # Determine Docker usage
      if (is.null(use_docker)) {
        # Auto-detect if not specified
        use_docker <- is_docker_available()
      } else if (use_docker && !is_docker_available()) {
        # Docker requested but not available
        return(list(
          success = FALSE,
          message = "Docker requested but not available on this system",
          data = NULL,
          error = "DOCKER_NOT_AVAILABLE"
        ))
      }
      
      # Create new REPL session
      session <- RREPLSession$new(timeout = timeout, use_docker = use_docker)

      # Store in registry
      assign(session_id, session, envir = .replr_sessions)

      # Get session information
      session_info <- session$get_info()

      list(
        success = TRUE,
        message = paste("Successfully created REPL session:", session_id, 
                       if (use_docker) "(using Docker)" else "(native)"),
        data = list(
          session_id = session_id,
          port = session_info$port,
          pid = session_info$pid,
          started_at = as.character(session_info$started_at),
          is_alive = session$is_alive(),
          using_docker = use_docker
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

      # Extract and structure the results
      execution_data <- list(
        session_id = session_id,
        status = result$status,
        output = result$result$output,
        warnings = result$result$warnings,
        errors = result$result$errors,
        visible = result$result$visible,
        plots = length(result$result$plots), # Just count, not full plot objects
        execution_time = result$execution_time,
        request_id = result$id
      )

      # Determine overall success
      is_success <- result$status == "success"

      list(
        success = is_success,
        message = if (is_success) {
          "Code executed successfully"
        } else {
          paste("Code execution failed:", paste(result$result$errors, collapse = "; "))
        },
        data = execution_data,
        error = if (!is_success) result$result$errors else NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error executing code in session", session_id, ":", e$message),
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
        message = paste("Error getting session info for", session_id, ":", e$message),
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
        message = paste("Successfully stopped and removed session:", session_id),
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
        session_id = ellmer::type_string("Optional custom session ID. If not provided, a UUID will be generated.", required = FALSE),
        timeout = ellmer::type_number("Timeout in seconds for session startup", required = FALSE)
      )
    )
  } else {
    # Fallback structure if ellmer is not available
    list(
      name = "replr_create_repl_session",
      description = "Create a new isolated R REPL session for executing R code",
      parameters = list(
        session_id = list(type = "string", description = "Optional custom session ID"),
        timeout = list(type = "number", description = "Timeout in seconds", default = 10)
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
      description = "Execute R code in an isolated REPL session and return structured results",
      arguments = list(
        session_id = ellmer::type_string("ID of the session to execute code in", required = TRUE),
        code = ellmer::type_string("R code to execute in the session", required = TRUE),
        timeout = ellmer::type_number("Timeout in seconds for code execution", required = FALSE)
      )
    )
  } else {
    list(
      name = "replr_execute_code",
      description = "Execute R code in an isolated REPL session and return structured results",
      parameters = list(
        session_id = list(type = "string", description = "Session ID", required = TRUE),
        code = list(type = "string", description = "R code to execute", required = TRUE),
        timeout = list(type = "number", description = "Timeout in seconds", default = 30)
      ),
      fn = replr_execute_code
    )
  }
}

#' Create REPL Session with Docker Tool Definition
#'
#' Returns an ellmer tool definition for creating new REPL sessions with
#' explicit Docker container control. This function provides the tool metadata
#' that LLM agents need to understand how to create isolated R sessions
#' with or without Docker containers.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' docker_tool <- replr_create_repl_session_docker_tool()
#' print(docker_tool$name)
#' print(docker_tool$description)
#' }
replr_create_repl_session_docker_tool <- function() {
  # Try to use ellmer::tool if available, otherwise return a basic structure
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_create_repl_session_docker,
      name = "replr_create_repl_session_docker",
      description = "Create a new isolated R REPL session with explicit Docker container control for enhanced security",
      arguments = list(
        session_id = ellmer::type_string("Optional custom session ID. If not provided, a UUID will be generated.", required = FALSE),
        timeout = ellmer::type_number("Timeout in seconds for session startup", required = FALSE),
        use_docker = ellmer::type_boolean("Whether to use Docker containers (true/false). If not specified, Docker will be auto-detected.", required = FALSE)
      )
    )
  } else {
    # Fallback structure if ellmer is not available
    list(
      name = "replr_create_repl_session_docker",
      description = "Create a new isolated R REPL session with explicit Docker container control for enhanced security",
      parameters = list(
        session_id = list(type = "string", description = "Optional custom session ID"),
        timeout = list(type = "number", description = "Timeout in seconds", default = 10),
        use_docker = list(type = "boolean", description = "Use Docker containers", required = FALSE)
      ),
      fn = replr_create_repl_session_docker
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
        session_id = ellmer::type_string("ID of the session to query", required = TRUE)
      )
    )
  } else {
    list(
      name = "replr_get_session_info",
      description = "Get detailed information about a REPL session including status and process info",
      parameters = list(
        session_id = list(type = "string", description = "Session ID", required = TRUE)
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
        session_id = ellmer::type_string("ID of the session to stop", required = TRUE),
        timeout = ellmer::type_number("Timeout in seconds for graceful shutdown", required = FALSE)
      )
    )
  } else {
    list(
      name = "replr_stop_session",
      description = "Stop a specific REPL session and remove it from the registry",
      parameters = list(
        session_id = list(type = "string", description = "Session ID", required = TRUE),
        timeout = list(type = "number", description = "Timeout in seconds", default = 5)
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
        timeout = ellmer::type_number("Timeout in seconds for each session shutdown", required = FALSE)
      )
    )
  } else {
    list(
      name = "replr_stop_all_sessions",
      description = "Stop all active REPL sessions and clear the session registry",
      parameters = list(
        timeout = list(type = "number", description = "Timeout in seconds", default = 5)
      ),
      fn = replr_stop_all_sessions
    )
  }
}

#' Check Docker Availability Tool
#'
#' A utility function for LLM agents to check if Docker is available
#' on the system. This helps agents decide whether to use Docker containers.
#'
#' @return list with Docker availability status
#' @export
#' @examples
#' \dontrun{
#' # Check if Docker is available
#' result <- replr_check_docker_availability()
#' if (result$data$available) {
#'   cat("Docker is available for enhanced isolation")
#' }
#' }
replr_check_docker_availability <- function() {
  tryCatch(
    {
      docker_available <- is_docker_available()
      
      list(
        success = TRUE,
        message = if (docker_available) "Docker is available" else "Docker is not available",
        data = list(
          available = docker_available,
          image_name = if (docker_available) get_worker_docker_image() else NULL
        ),
        error = NULL
      )
    },
    error = function(e) {
      list(
        success = FALSE,
        message = paste("Error checking Docker availability:", e$message),
        data = list(available = FALSE),
        error = as.character(e$message)
      )
    }
  )
}

#' Check Docker Availability Tool Definition
#'
#' Returns an ellmer tool definition for checking Docker availability.
#' This function provides the tool metadata that LLM agents need to
#' understand how to check if Docker containers can be used.
#'
#' @return An ellmer tool object (when ellmer is available) or a compatible
#'   structure containing the tool name, description, parameters, and function.
#' @export
#' @examples
#' \dontrun{
#' # Get the tool definition
#' docker_check_tool <- replr_check_docker_availability_tool()
#' print(docker_check_tool$name)
#' }
replr_check_docker_availability_tool <- function() {
  if (requireNamespace("ellmer", quietly = TRUE)) {
    ellmer::tool(
      replr_check_docker_availability,
      name = "replr_check_docker_availability",
      description = "Check if Docker is available on the system for enhanced container isolation",
      arguments = list()
    )
  } else {
    list(
      name = "replr_check_docker_availability",
      description = "Check if Docker is available on the system for enhanced container isolation",
      parameters = list(),
      fn = replr_check_docker_availability
    )
  }
}
