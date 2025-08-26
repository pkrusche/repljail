#' Communication Helpers for nanonext REQ-REP
#'
#' Functions to manage nanonext sockets and handle request/response communication
#' between the main process and worker processes.

#' Create REQ Socket
#'
#' Create a nanonext REQ socket for sending requests to worker
#'
#' @param port integer, port number to connect to
#' @param timeout numeric, timeout in seconds for socket operations
#' @return nanonext socket object
create_req_socket <- function(port, timeout = 5) {
  socket_url <- paste0("tcp://127.0.0.1:", port)
  
  tryCatch({
    sock <- nanonext::socket("req", dial = socket_url, autostart = NA)
    
    # Set timeout for receive operations (timeout in milliseconds)
    nanonext::opt(sock, "recv-timeout") <- as.integer(timeout * 1000)
    
    sock
  }, error = function(e) {
    stop("Failed to create REQ socket on port ", port, ": ", e$message)
  })
}

#' Send Request to Worker
#'
#' Send a code execution request to a worker process
#'
#' @param socket nanonext socket object
#' @param code character, R code to execute
#' @param id character, optional request ID (auto-generated if NULL)
#' @param options list, optional execution options
#' @return response list from worker, or NULL if timeout/error
send_request <- function(socket, code, id = NULL, options = list()) {
  if (is.null(id)) {
    id <- uuid::UUIDgenerate()
  }
  
  request <- list(
    id = id,
    code = code,
    options = options
  )
  
  tryCatch({
    # Send request
    nanonext::send(socket, request)
    
    # Receive response
    response <- nanonext::recv(socket)
    
    response
  }, error = function(e) {
    warning("Communication error: ", e$message)
    NULL
  })
}

#' Close Socket
#'
#' Safely close a nanonext socket
#'
#' @param socket nanonext socket object
close_socket <- function(socket) {
  if (!is.null(socket)) {
    tryCatch({
      close(socket)
    }, error = function(e) {
      warning("Error closing socket: ", e$message)
    })
  }
}

#' Test Socket Connection
#'
#' Test if a socket connection is working by sending a simple ping
#'
#' @param socket nanonext socket object
#' @return logical, TRUE if connection is working
test_socket_connection <- function(socket) {
  response <- send_request(socket, "1 + 1", id = "ping")
  
  !is.null(response) && response$status == "success"
}