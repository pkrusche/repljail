#' Communication Helpers for nanonext REQ-REP
#'
#' Functions to manage nanonext sockets and handle request/response communication
#' between the main process and worker processes.

#' Create REQ Socket
#'
#' Create a nanonext REQ socket for sending requests to worker
#'
#' @param port integer, port number to connect to (for TCP mode)
#' @param socket_path character, socket file path (for IPC mode)
#' @param timeout numeric, timeout in seconds for socket operations
#' @return nanonext socket object
create_req_socket <- function(port = NULL, socket_path = NULL, timeout = 5) {
  # Determine socket URL based on provided parameters
  if (!is.null(socket_path)) {
    # IPC mode
    socket_url <- paste0("ipc://", socket_path)
  } else if (!is.null(port)) {
    # TCP mode
    socket_url <- paste0("tcp://127.0.0.1:", port)
  } else {
    stop("Either port or socket_path must be provided")
  }

  tryCatch(
    {
      debug_log("Creating REQ socket for {socket_url}")
      # Create socket with async dial (autostart = TRUE)
      # This is essential for Docker gateway scenarios where initial connection may be slow
      # The socket will continue attempting to connect in the background
      sock <- nanonext::socket("req", dial = socket_url, autostart = TRUE)

      # Set timeout for receive operations (timeout in milliseconds)
      nanonext::opt(sock, "recv-timeout") <- as.integer(timeout * 1000)

      # Give the async dial time to establish (critical for gateway forwarding)
      Sys.sleep(1)

      debug_success("REQ socket created successfully")
      sock
    },
    error = function(e) {
      debug_error("Failed to create REQ socket: {e$message}")
      stop("Failed to create REQ socket: ", e$message)
    }
  )
}

#' Send Request to Worker
#'
#' Send a code execution request to a worker process
#'
#' @param socket nanonext socket object
#' @param code character, R code to execute
#' @param id character, optional request ID (auto-generated if NULL)
#' @param options list, optional execution options
#' @param timeout integer, timeout in seconds for the request
#' @return response list from worker, or NULL if timeout/error
send_request <- function(
  socket,
  code,
  id = NULL,
  options = list(),
  timeout = 5
) {
  if (is.null(id)) {
    id <- uuid::UUIDgenerate()
  }

  request <- list(
    id = id,
    code = code,
    options = options
  )

  timeout <- as.integer(timeout * 1000) # Convert to milliseconds

  tryCatch(
    {
      # Send request
      debug_log("Sending request ID: {id}")
      nanonext::send(socket, request)

      # Receive response
      response <- nanonext::recv(socket, block = timeout)

      debug_log("Received response from request ID: {id}")
      response
    },
    error = function(e) {
      debug_error("Communication error for request {id}: {e$message}")
      warning("Communication error: ", e$message)
      NULL
    }
  )
}

#' Close Socket
#'
#' Safely close a nanonext socket
#'
#' @param socket nanonext socket object
close_socket <- function(socket) {
  if (!is.null(socket)) {
    tryCatch(
      {
        debug_log("Closing socket")
        close(socket)
        debug_success("Socket closed successfully")
      },
      error = function(e) {
        debug_error("Error closing socket: {e$message}")
        warning("Error closing socket: ", e$message)
      }
    )
  }
}

#' Test Socket Connection
#'
#' Test if a socket connection is working by sending a simple ping
#'
#' @param socket nanonext socket object
#' @return logical, TRUE if connection is working
test_socket_connection <- function(socket) {
  debug_log("Testing socket connection with ping")
  response <- send_request(socket, "1 + 1", id = "ping")

  is_working <- !is.null(response) && response$status == "success"
  if (is_working) {
    debug_success("Socket connection test successful")
  } else {
    debug_warn("Socket connection test failed")
  }

  is_working
}
