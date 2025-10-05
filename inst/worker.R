#!/usr/bin/env Rscript

# Worker process script for replr package
# This script runs in an isolated R process and executes code via evaluate package
# Communication with parent process via nanonext REP socket

# Get command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1 || length(args) > 3) {
  cat(
    "Usage: Rscript worker.R <port> [--debug] [--listen-all]\n",
    file = stderr()
  )
  cat("  port:   Port number to listen on\n", file = stderr())
  cat("  --debug: Enable debug logging (optional)\n", file = stderr())
  cat(
    "  --listen-all: Listen on all IPs (optional, e.g. when running inside Docker)\n",
    file = stderr()
  )
  quit(status = 1)
}

port <- as.integer(args[1])

if (is.na(port) || port <= 0 || port > 65535) {
  cat("Error: Invalid port number:", args[1], "\n", file = stderr())
  quit(status = 1)
}

# Check for debug and listen flag
debug_enabled <- length(args) >= 2 && any(args[2:length(args)] == "--debug")
listen_enabled <- length(args) >= 2 &&
  any(args[2:length(args)] == "--listen-all")
if (debug_enabled) {
  cat("Debug mode enabled for worker process\n", file = stderr())
}

# Load required packages
required_packages <- c("nanonext", "evaluate", "cli")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Error: Required package not available:", pkg, "\n", file = stderr())
    quit(status = 1)
  }
}

# Check if debug logging is enabled (uses command line flag)
is_debug_enabled <- function() {
  debug_enabled
}

# Worker debug logging functions (inline since we're in separate process)
worker_debug_log <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_dim(cli::col_blue("\u2139")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

worker_debug_success <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_bold(cli::col_green("\u2714")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

worker_debug_warn <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_bold(cli::col_yellow("\u26a0")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

worker_debug_error <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_bold(cli::col_red("\u2716")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

# Helper function for null coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x

# Global flag for graceful shutdown
shutdown_requested <- FALSE

# Set up nanonext REP socket
if (listen_enabled) {
  socket_url <- paste0("tcp://*:", port)
} else {
  socket_url <- paste0("tcp://127.0.0.1:", port)
}
worker_debug_log("Worker starting on ", socket_url)
# Always show startup message
cat("Worker starting on", socket_url, "\n", file = stderr())

tryCatch(
  {
    # Create REP socket and bind to port
    sock <- nanonext::socket("rep", listen = socket_url)

    worker_debug_success("Worker ready and listening")
    # Always show ready message
    cat("Worker ready and listening\n", file = stderr())

    # Main message loop with graceful shutdown support
    while (!shutdown_requested) {
      # Use non-blocking receive with timeout to allow signal checking
      msg <- nanonext::recv(sock, block = FALSE)

      if (is.null(msg) || inherits(msg, "errorValue")) {
        # No message received, check for shutdown and continue
        if (shutdown_requested) {
          worker_debug_log("Shutdown requested, breaking message loop")
          break
        }

        # Brief sleep to prevent busy waiting
        Sys.sleep(0.1)
        next
      }

      worker_debug_log(
        "Received request: ",
        paste0(deparse(msg), collapse = ";")
      )

      # Check if this is a shutdown message
      if (is.character(msg) && msg == "__SHUTDOWN__") {
        worker_debug_log("Received shutdown command from parent")
        break
      }

      # Process the request
      response <- tryCatch(
        {
          # Extract request data - handle both list and direct message formats
          if (is.list(msg) && "code" %in% names(msg)) {
            code_to_execute <- msg$code
            request_id <- msg$id %||% "unknown"
          } else if (is.character(msg)) {
            # Direct code string
            code_to_execute <- msg
            request_id <- "direct"
          } else {
            # Invalid format
            list(
              id = "unknown",
              status = "error",
              result = list(
                output = character(0),
                warnings = character(0),
                errors = "Invalid request format: expected list with 'code' field or character string",
                visible = FALSE,
                plots = list()
              ),
              execution_time = 0
            )
          }

          # Only proceed if we have valid code
          if (exists("code_to_execute")) {
            # Record start time
            start_time <- Sys.time()

            # Execute code using evaluate package
            eval_result <- evaluate::evaluate(
              code_to_execute,
              stop_on_error = 2, # Continue after errors
              new_device = TRUE
            ) # Create new plot device for each run

            # Calculate execution time
            execution_time <- as.numeric(difftime(
              Sys.time(),
              start_time,
              units = "secs"
            ))

            # Process evaluation results
            output_lines <- character(0)
            warning_msgs <- character(0)
            error_msgs <- character(0)
            plots <- list()
            visible <- FALSE

            for (item in eval_result) {
              if (is.character(item)) {
                # Console output
                output_lines <- c(output_lines, item)
              } else if (inherits(item, "source")) {
                # Source code - usually skip in output
                next
              } else if (inherits(item, "warning")) {
                # Warning message
                warning_msgs <- c(warning_msgs, item$message)
              } else if (
                inherits(item, "simpleError") || inherits(item, "error")
              ) {
                # Error message
                error_msgs <- c(error_msgs, item$message)
              } else if (inherits(item, "recordedplot")) {
                # Plot object
                # to append plot directly: - but this seems to not
                # transfer nicely through the socket. plots <- append(plots, list(item))
                img_file <- tempfile(fileext = ".png")
                png(img_file)
                print(item)
                dev.off()
                img_data <- base64enc::base64encode(img_file)
                unlink(img_file)
                plots <- append(
                  plots,
                  list(paste0("data:image/png;base64,", img_data))
                )
              } else if (!is.null(item)) {
                # Other objects (usually the result of the last expression)
                if (
                  length(eval_result) > 0 &&
                    identical(item, eval_result[[length(eval_result)]])
                ) {
                  visible <- TRUE
                  if (!is.null(item)) {
                    # Capture printed representation
                    output_lines <- c(output_lines, capture.output(print(item)))
                  }
                }
              }
            }

            # Determine overall status
            status <- if (length(error_msgs) > 0) "error" else "success"

            # Create response
            list(
              id = request_id,
              status = status,
              result = list(
                output = output_lines,
                warnings = warning_msgs,
                errors = error_msgs,
                visible = visible,
                plots = plots
              ),
              execution_time = execution_time
            )
          }
        },
        error = function(e) {
          # Handle unexpected errors in processing
          list(
            id = "unknown",
            status = "error",
            result = list(
              output = character(0),
              warnings = character(0),
              errors = paste("Worker error:", e$message),
              visible = FALSE,
              plots = list()
            ),
            execution_time = 0
          )
        }
      )
      worker_debug_log(
        "Sending response: ",
        paste0(deparse(response), collapse = ";")
      )
      # Send response back
      nanonext::send(sock, response)
    }
  },
  error = function(e) {
    worker_debug_error("Worker error: ", e$message)
    # Always show critical errors
    cat("Worker error:", e$message, "\n", file = stderr())
    quit(status = 1)
  },
  finally = {
    # Clean up socket
    if (exists("sock")) {
      worker_debug_log("Closing socket connection")
      tryCatch(
        {
          close(sock)
        },
        error = function(e) {
          worker_debug_warn("Error closing socket: ", e$message)
        }
      )
    }

    # Final shutdown message
    if (shutdown_requested) {
      worker_debug_success("Worker shutdown completed gracefully")
      cat("Worker shutdown completed gracefully\n", file = stderr())
    } else {
      worker_debug_log("Worker shutting down")
      cat("Worker shutting down\n", file = stderr())
    }
  }
)

quit(status = 0)
