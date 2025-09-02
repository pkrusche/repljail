#' RREPLSession: R6 Class for Isolated R Session Management
#'
#' An R6 class that provides object-oriented interface for managing isolated
#' R worker processes. This class wraps the functional interface (start_worker,
#' send_command, stop_worker) and provides automatic resource management
#' through finalizers. Docker usage is controlled by the 'replr.use.docker' option.
#'
#' @section Constructor:
#' \code{RREPLSession$new(port = NULL, timeout = 10)}
#'
#' @section Public Methods:
#' \itemize{
#'   \item \code{execute(code, timeout = 30)} - Execute R code in the worker
#'   \item \code{is_alive()} - Check if worker process is running
#'   \item \code{stop(timeout = 5)} - Gracefully stop the worker process
#'   \item \code{get_info()} - Get worker process information
#' }
#'
#' @section Active Bindings:
#' \itemize{
#'   \item \code{port} - Port number used by the worker
#'   \item \code{pid} - Process ID of the worker (if alive)
#'   \item \code{started_at} - Timestamp when worker was started
#' }
#'
#' @examples
#' \dontrun{
#' # Create a new session
#' session <- RREPLSession$new()
#'
#' # Execute some R code
#' result <- session$execute("1 + 1")
#' print(result$result$output)
#'
#' # Check if worker is alive
#' session$is_alive()
#'
#' # Stop the session (optional - happens automatically on cleanup)
#' session$stop()
#' }
#'
#' @export
RREPLSession <- R6::R6Class(
  # nolint
  "RREPLSession",
  public = list(
    #' @description
    #' Create a new RREPLSession
    #' @param port integer, port number for worker (auto-selected if NULL)
    #' @param timeout numeric, timeout in seconds for worker startup
    initialize = function(port = NULL, timeout = 10) {
      private$.worker_info <- start_worker(
        port = port,
        timeout = timeout
      )
      private$.stopped <- FALSE

      # Register finalizer for automatic cleanup
      reg.finalizer(
        self,
        function(obj) {
          if (!private$.stopped && !is.null(private$.worker_info)) {
            tryCatch(
              {
                stop_worker(private$.worker_info, timeout = 2)
              },
              error = function(e) {
                # Silent cleanup - worker may already be dead
              }
            )
          }
        },
        onexit = TRUE
      )
    },

    #' @description
    #' Execute R code in the worker process
    #' @param code character, R code to execute
    #' @param timeout numeric, timeout in seconds for execution
    #' @return list with execution results
    execute = function(code, timeout = 30) {
      if (private$.stopped) {
        stop("Session has been stopped")
      }

      if (!self$is_alive()) {
        stop("Worker process is not running")
      }

      send_command(private$.worker_info, code, timeout = timeout)
    },

    #' @description
    #' Check if worker process is alive
    #' @return logical, TRUE if worker is running
    is_alive = function() {
      if (private$.stopped || is.null(private$.worker_info)) {
        return(FALSE)
      }

      proc <- private$.worker_info$process
      !is.null(proc) && proc$is_alive()
    },

    #' @description
    #' Stop the worker process gracefully
    #' @param timeout numeric, timeout in seconds for graceful shutdown
    #' @return logical, TRUE if stopped successfully
    stop = function(timeout = 5) {
      if (private$.stopped || is.null(private$.worker_info)) {
        return(TRUE)
      }

      result <- stop_worker(private$.worker_info, timeout = timeout)
      private$.stopped <- TRUE

      result
    },

    #' @description
    #' Get worker process information
    #' @return list with process details
    get_info = function() {
      if (is.null(private$.worker_info)) {
        return(NULL)
      }

      list(
        port = private$.worker_info$port,
        pid = if (self$is_alive()) {
          private$.worker_info$process$get_pid()
        } else {
          NA
        },
        started_at = private$.worker_info$started_at,
        is_alive = self$is_alive(),
        stopped = private$.stopped,
        is_docker = private$.worker_info$is_docker
      )
    },

    #' @description
    #' Retrieve debug logs from the worker process
    #' @return character vector of debug log messages
    get_debug_logs = function() {
      if (private$.stopped || is.null(private$.worker_info)) {
        return(character(0))
      }

      if (!self$is_alive()) {
        return(character(0))
      }

      return(replr:::get_worker_debug_logs(private$.worker_info)) # nolint
    }
  ),
  active = list(
    #' @field port Port number used by the worker
    port = function() {
      if (is.null(private$.worker_info)) {
        return(NA_integer_)
      }
      private$.worker_info$port
    },

    #' @field pid Process ID of the worker
    pid = function() {
      if (!self$is_alive()) {
        return(NA_integer_)
      }
      private$.worker_info$process$get_pid()
    },

    #' @field started_at Timestamp when worker was started
    started_at = function() {
      if (is.null(private$.worker_info)) {
        return(as.POSIXct(NA))
      }
      private$.worker_info$started_at
    },

    #' @field is_docker Logical, TRUE if worker is running inside Docker
    is_docker = function() {
      if (is.null(private$.worker_info)) {
        return(NA)
      }
      private$.worker_info$is_docker
    }
  ),
  private = list(
    .worker_info = NULL,
    .stopped = FALSE
  )
)
