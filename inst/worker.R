#!/usr/bin/env Rscript

# Worker process script for replr package
# This script runs in an isolated R process and executes code via evaluate package
# Communication with parent process via nanonext REP socket

# Get command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 1) {
  cat("Usage: Rscript worker.R <port>\n", file = stderr())
  quit(status = 1)
}

port <- as.integer(args[1])

if (is.na(port) || port <= 0 || port > 65535) {
  cat("Error: Invalid port number:", args[1], "\n", file = stderr())
  quit(status = 1)
}

# Load required packages
required_packages <- c("nanonext", "evaluate")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Error: Required package not available:", pkg, "\n", file = stderr())
    quit(status = 1)
  }
}

# Helper function for null coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x

# Set up nanonext REP socket
socket_url <- paste0("tcp://127.0.0.1:", port)
cat("Worker starting on", socket_url, "\n", file = stderr())

tryCatch({
  # Create REP socket and bind to port
  sock <- nanonext::socket("rep", listen = socket_url)
  
  cat("Worker ready and listening\n", file = stderr())
  
  # Main message loop
  while (TRUE) {
    # Receive request from parent process
    msg <- nanonext::recv(sock)
    
    if (is.null(msg)) {
      # Connection closed or error
      break
    }
    
    # Process the request
    response <- tryCatch({
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
        eval_result <- evaluate::evaluate(code_to_execute, 
                                        stop_on_error = 2,  # Continue after errors
                                        new_device = FALSE)  # Don't create new plot device
        
        # Calculate execution time
        execution_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
        
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
          } else if (inherits(item, "simpleError") || inherits(item, "error")) {
            # Error message
            error_msgs <- c(error_msgs, item$message)
          } else if (inherits(item, "recordedplot")) {
            # Plot object
            plots <- append(plots, list(item))
          } else if (!is.null(item)) {
            # Other objects (usually the result of the last expression)
            if (length(eval_result) > 0 && identical(item, eval_result[[length(eval_result)]])) {
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
    }, error = function(e) {
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
    })
    
    # Send response back
    nanonext::send(sock, response)
  }
  
}, error = function(e) {
  cat("Worker error:", e$message, "\n", file = stderr())
  quit(status = 1)
}, finally = {
  # Clean up socket
  if (exists("sock")) {
    close(sock)
  }
  cat("Worker shutting down\n", file = stderr())
})

quit(status = 0)