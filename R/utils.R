#' Check Package Dependencies
#'
#' Verify that all required packages are available and compatible
#'
#' @return logical indicating if all dependencies are satisfied
#' @export
check_dependencies <- function() {
  required_packages <- c(
    "nanonext",
    "mirai",
    "processx",
    "evaluate",
    "R6",
    "uuid"
  )
  suggested_packages <- c("pryr", "testthat")

  missing_required <- character(0)
  missing_suggested <- character(0)

  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing_required <- c(missing_required, pkg)
    }
  }

  for (pkg in suggested_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      missing_suggested <- c(missing_suggested, pkg)
    }
  }

  if (length(missing_required) > 0) {
    stop(
      "Missing required packages: ",
      paste(missing_required, collapse = ", "),
      "\nInstall with: install.packages(c(",
      paste0('"', missing_required, '"', collapse = ", "),
      "))"
    )
  }

  if (length(missing_suggested) > 0) {
    message(
      "Missing suggested packages: ",
      paste(missing_suggested, collapse = ", ")
    )
  }

  TRUE
}

#' Check Process Availability
#'
#' Verify that R and Rscript are available for process spawning
#'
#' @return logical indicating if process requirements are met
check_process_requirements <- function() {
  rscript_path <- Sys.which("Rscript")

  if (rscript_path == "") {
    stop("Rscript not found in PATH. Please ensure R is properly installed.")
  }

  if (!file.access(rscript_path, mode = 1) == 0) {
    stop("Rscript is not executable: ", rscript_path)
  }

  TRUE
}

#' Get Available Port
#'
#' Find an available TCP port for nanonext communication
#'
#' @param start_port integer, starting port number to check
#' @param max_attempts integer, maximum number of ports to try
#' @return integer, available port number
get_available_port <- function(start_port = 5555, max_attempts = 100) {
  for (i in seq_len(max_attempts)) {
    port <- start_port + i - 1

    # Try to bind to the port
    tryCatch(
      {
        sock <- nanonext::socket(
          "rep",
          listen = paste0("tcp://127.0.0.1:", port)
        )
        close(sock)
        return(port)
      },
      error = function(e) {
        # Port is likely in use, try next one
      }
    )
  }

  stop("Could not find available port after ", max_attempts, " attempts")
}

#' Get Worker Script Path
#' @return character, path to worker.R script
get_worker_script_path <- function() {
  possible_paths <- c(
    here::here("inst", "worker.R"),
    file.path(system.file(package = "replr"), "worker.R")
  )

  for (path in possible_paths) {
    if (file.exists(path)) {
      return(normalizePath(path))
    }
  }

  stop("Worker script not found in expected locations.")
}

#' Start Worker Process
#'
#' Spawn a worker R process using processx that runs the worker script.
#' Optionally can run the worker inside a Docker container for enhanced isolation.
#'
#' @param port integer, port number for the worker to listen on
#' @param timeout numeric, timeout in seconds to wait for worker startup
#' @param use_docker logical, whether to run worker in Docker container (default: FALSE)
#' @return list with process object and connection info
#' @export
start_worker <- function(port = NULL, timeout = 10, use_docker = FALSE) {
  # Check prerequisites
  check_dependencies()
  check_process_requirements()

  # Get available port if not specified
  if (is.null(port)) {
    port <- get_available_port()
  }

  worker_script <- get_worker_script_path()

  # Build arguments for worker process
  worker_args <- c(worker_script, as.character(port))

  # Add debug flag if debug logging is enabled in parent process
  if (is_debug_enabled()) {
    debug_log("Starting worker with debug logging enabled")
    worker_args <- c(worker_args, "--debug")
  }

  # Prepare environment for worker process
  worker_env <- Sys.getenv()
  # Pass current library paths to worker
  worker_env[["R_LIBS_USER"]] <- paste(.libPaths(), collapse = .Platform$path.sep)
  
  # Start the worker process (either Docker or native)
  if (use_docker) {
    # Check Docker availability
    if (!is_docker_available()) {
      stop("Docker is not available. Cannot start worker in Docker container.")
    }
    
    proc <- start_docker_worker(port, worker_script, worker_args, timeout)
  } else {
    # Start native worker process
    proc <- processx::process$new(
      command = file.path(R.home("bin"), "Rscript"),
      args = worker_args,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE,
      env = worker_env
    )
  }

  # Wait for worker to start up
  start_time <- Sys.time()
  worker_ready <- FALSE

  while (difftime(Sys.time(), start_time, units = "secs") < timeout) {
    if (!proc$is_alive()) {
      # Process died
      stdout_lines <- proc$read_output_lines()
      stderr_lines <- proc$read_error_lines()
      stop(
        "Worker process failed to start:\nSTDOUT: ",
        paste(stdout_lines, collapse = "\n"),
        "\nSTDERR: ",
        paste(stderr_lines, collapse = "\n")
      )
    }

    # Try to connect to worker
    tryCatch(
      {
        sock <- create_req_socket(port, timeout = 1)
        # Simple ping test
        result <- send_request(sock, "1", id = "ping")
        if (!is.null(result)) {
          close_socket(sock)
          worker_ready <- TRUE
          break
        }
        close_socket(sock)
      },
      error = function(e) {
        # Worker not ready yet, continue waiting
      }
    )

    Sys.sleep(0.5) # Longer delay between attempts
  }

  if (!worker_ready) {
    # Clean up failed process
    if (proc$is_alive()) {
      proc$kill()
    }
    stop("Worker process did not become ready within ", timeout, " seconds")
  }

  list(
    process = proc,
    port = port,
    started_at = Sys.time()
  )
}

#' Send Command to Worker
#'
#' Send an R command to a running worker process and get the result
#'
#' @param worker_info list, worker info returned by start_worker()
#' @param code character, R code to execute
#' @param timeout numeric, timeout in seconds for command execution
#' @return response list from worker
#' @export
send_command <- function(worker_info, code, timeout = 30) {
  if (is.null(worker_info$process) || !worker_info$process$is_alive()) {
    stop("Worker process is not running")
  }

  # Create socket connection
  sock <- create_req_socket(worker_info$port, timeout = timeout)

  tryCatch(
    {
      # Send request
      response <- send_request(sock, code)

      if (is.null(response)) {
        stop("No response from worker (timeout or communication error)")
      }

      response
    },
    finally = {
      close_socket(sock)
    }
  )
}

#' Stop Worker Process
#'
#' Gracefully stop a worker process
#'
#' @param worker_info list, worker info returned by start_worker()
#' @param timeout numeric, timeout in seconds to wait for graceful shutdown
#' @return logical, TRUE if stopped successfully
#' @export
stop_worker <- function(worker_info, timeout = 5) {
  if (is.null(worker_info$process)) {
    return(TRUE)
  }

  proc <- worker_info$process

  if (!proc$is_alive()) {
    return(TRUE)
  }

  # Try graceful shutdown first
  tryCatch(
    {
      proc$signal(2) # SIGINT
    },
    error = function(e) {
      # Signal failed, proceed to kill
    }
  )

  # Wait for graceful shutdown
  start_time <- Sys.time()
  while (
    proc$is_alive() &&
      difftime(Sys.time(), start_time, units = "secs") < timeout
  ) {
    Sys.sleep(0.1)
  }

  # Force kill if still alive
  if (proc$is_alive()) {
    proc$kill()
    Sys.sleep(0.1)
  }

  !proc$is_alive()
}

#' Check Docker Availability
#'
#' Check if Docker is available and accessible on the system
#'
#' @return logical, TRUE if Docker is available and accessible
#' @export
is_docker_available <- function() {
  # Check if docker command exists
  docker_path <- Sys.which("docker")
  if (docker_path == "") {
    return(FALSE)
  }
  
  # Test if docker is accessible (try docker version)
  tryCatch({
    result <- system2("docker", c("version", "--format", "'{{.Client.Version}}'"), 
                     stdout = TRUE, stderr = TRUE)
    # If no error and got output, Docker is available
    return(length(result) > 0 && !inherits(result, "try-error"))
  }, error = function(e) {
    return(FALSE)
  })
}

#' Get Docker Image Name for Worker
#'
#' Get the Docker image name to use for worker containers
#'
#' @return character, Docker image name
get_worker_docker_image <- function() {
  "replr-worker:latest"
}

#' Start Docker Worker Process
#'
#' Start a worker process inside a Docker container with security hardening
#'
#' @param port integer, port number for the worker
#' @param worker_script character, path to worker script
#' @param worker_args character vector, arguments for worker
#' @param timeout numeric, startup timeout
#' @return processx process object
start_docker_worker <- function(port, worker_script, worker_args, timeout) {
  image_name <- get_worker_docker_image()
  
  # Build Docker image if it doesn't exist
  if (!docker_image_exists(image_name)) {
    build_worker_docker_image(image_name)
  }
  
  # Prepare Docker arguments with security hardening
  docker_args <- c(
    "run",
    "--rm",                    # Remove container when done
    "--user", "replr",         # Run as non-root user
    "--memory", "512m",        # Memory limit
    "--cpus", "1.0",          # CPU limit
    "-p", paste0("127.0.0.1:", port, ":", port), # Port mapping
    "-v", paste0(worker_script, ":/app/worker.R:ro"), # Mount worker script
    image_name,
    "Rscript", "/app/worker.R", as.character(port)
  )
  
  # Add additional security options if they work in this environment
  tryCatch({
    # Test if advanced security options work
    test_result <- system2("docker", c("run", "--rm", "--network", "none", 
                                      "--read-only", "--tmpfs", "/tmp",
                                      "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                                      image_name, "echo", "test"), 
                          stdout = FALSE, stderr = FALSE)
    
    if (test_result == 0) {
      # Advanced security works, use it
      docker_args <- c(
        "run",
        "--rm",                    # Remove container when done
        "--network", "none",       # No network access for security
        "--user", "replr",         # Run as non-root user
        "--read-only",             # Read-only filesystem
        "--tmpfs", "/tmp",         # Writable tmp directory
        "--cap-drop", "ALL",       # Drop all capabilities
        "--security-opt", "no-new-privileges",  # Prevent privilege escalation
        "--memory", "512m",        # Memory limit
        "--cpus", "1.0",          # CPU limit
        "-p", paste0("127.0.0.1:", port, ":", port), # Port mapping
        "-v", paste0(worker_script, ":/app/worker.R:ro"), # Mount worker script
        image_name,
        "Rscript", "/app/worker.R", as.character(port)
      )
      debug_log("Using advanced Docker security options")
    } else {
      debug_log("Using basic Docker security options (advanced options not supported)")
    }
  }, error = function(e) {
    debug_log("Using basic Docker security options due to error:", e$message)
  })
  
  # Add debug flag if present in worker_args
  if ("--debug" %in% worker_args) {
    docker_args <- c(docker_args, "--debug")
  }
  
  # Start Docker container
  proc <- processx::process$new(
    command = "docker",
    args = docker_args,
    stdout = "|",
    stderr = "|",
    cleanup = TRUE,
    cleanup_tree = TRUE
  )
  
  return(proc)
}

#' Check if Docker Image Exists
#'
#' @param image_name character, Docker image name
#' @return logical, TRUE if image exists
docker_image_exists <- function(image_name) {
  tryCatch({
    result <- system2("docker", c("image", "inspect", image_name), 
                     stdout = FALSE, stderr = FALSE)
    return(result == 0)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Build Worker Docker Image
#'
#' Build the Docker image for worker containers
#'
#' @param image_name character, Docker image name to build
build_worker_docker_image <- function(image_name) {
  dockerfile_path <- file.path(system.file(package = "replr"), "Dockerfile")
  
  # If running from source, use inst/Dockerfile
  if (!file.exists(dockerfile_path)) {
    dockerfile_path <- file.path(find.package("replr", lib.loc = .libPaths()), "..", "..", "inst", "Dockerfile")
  }
  
  # As last resort, check current directory structure
  if (!file.exists(dockerfile_path)) {
    possible_paths <- c(
      here::here("inst", "Dockerfile"),
      file.path(getwd(), "inst", "Dockerfile")
    )
    for (path in possible_paths) {
      if (file.exists(path)) {
        dockerfile_path <- path
        break
      }
    }
  }
  
  if (!file.exists(dockerfile_path)) {
    stop("Dockerfile not found. Cannot build Docker image.")
  }
  
  # Build the image
  build_args <- c(
    "build",
    "-t", image_name,
    "-f", dockerfile_path,
    dirname(dockerfile_path)
  )
  
  debug_log("Building Docker image:", image_name)
  result <- system2("docker", build_args, stdout = TRUE, stderr = TRUE)
  
  if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
    stop("Failed to build Docker image. Docker output:\n", paste(result, collapse = "\n"))
  }
  
  debug_success("Docker image built successfully:", image_name)
}
