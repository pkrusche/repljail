#' replr Tools for REPL Session Management
#'
#' This module provides tools designed specifically for ellmer LLM agents to
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
#' Creates a new isolated R REPL session that can be used by an ellmer LLM agent.
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
  tryCatch({
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
    
    # Create new REPL session
    session <- RREPLSession$new(timeout = timeout)
    
    # Store in registry
    assign(session_id, session, envir = .replr_sessions)
    
    # Get session information
    session_info <- session$get_info()
    
    list(
      success = TRUE,
      message = paste("Successfully created REPL session:", session_id),
      data = list(
        session_id = session_id,
        port = session_info$port,
        pid = session_info$pid,
        started_at = as.character(session_info$started_at),
        is_alive = session$is_alive()
      ),
      error = NULL
    )
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Failed to create REPL session:", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
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
  tryCatch({
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
      plots = length(result$result$plots),  # Just count, not full plot objects
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
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error executing code in session", session_id, ":", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
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
  tryCatch({
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
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error getting session info for", session_id, ":", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
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
  tryCatch({
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
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error stopping session", session_id, ":", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
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
  tryCatch({
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
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error listing sessions:", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
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
  tryCatch({
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
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error during cleanup:", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
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
  tryCatch({
    session_ids <- ls(envir = .replr_sessions)
    stopped_count <- 0
    errors <- character(0)
    
    for (session_id in session_ids) {
      tryCatch({
        session <- get(session_id, envir = .replr_sessions)
        session$stop(timeout = timeout)
        stopped_count <- stopped_count + 1
      }, error = function(e) {
        errors <<- c(errors, paste(session_id, ":", e$message))
      })
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
  }, error = function(e) {
    list(
      success = FALSE,
      message = paste("Error stopping all sessions:", e$message),
      data = NULL,
      error = as.character(e$message)
    )
  })
}