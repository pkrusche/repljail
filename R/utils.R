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
#' Docker usage is controlled by the 'replr.use.docker' option.
#'
#' @param port integer, port number for the worker to listen on
#' @param timeout numeric, timeout in seconds to wait for worker startup
#' @return list with process object and connection info
#' @export
start_worker <- function(port = NULL, timeout = 10) {
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
  worker_env[["R_LIBS_USER"]] <- paste(
    .libPaths(),
    collapse = .Platform$path.sep
  )

  # Check if Docker should be used (from option)
  use_docker <- getOption("replr.use.docker", default = FALSE)

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
    # Try to get debug logs from worker before failing
    stdout_lines <- proc$read_output_lines()
    stderr_lines <- proc$read_error_lines()

    # Clean up failed process
    if (proc$is_alive()) {
      proc$kill()
    }

    # Special cleanup for Docker containers
    container_name <- attr(proc, "container_name")
    if (use_docker && !is.null(container_name)) {
      debug_log("Cleaning up failed Docker container: ", container_name)
      tryCatch(
        {
          # Force remove the container if it exists
          system2(
            "docker",
            c("rm", "-f", container_name),
            stdout = FALSE,
            stderr = FALSE
          )
        },
        error = function(e) {
          debug_warn("Failed to clean up Docker container: ", e$message)
        }
      )
    }

    # Wait for graceful shutdown
    start_time <- Sys.time()
    # Shorter timeout for Docker
    while (
      proc$is_alive() &&
        difftime(Sys.time(), start_time, units = "secs") < 2
    ) {
      Sys.sleep(0.1)
    }

    # Force kill if still alive
    if (proc$is_alive()) {
      debug_log("Worker did not stop gracefully, killing process")
      proc$kill()
      Sys.sleep(0.1)
    }

    stop(
      "Worker process did not become ready within ",
      timeout,
      " seconds\n",
      if (use_docker) {
        "\nNote: This was a Docker container startup failure\n"
      } else {
        ""
      },
      "\nSTDOUT: ",
      paste(stdout_lines, collapse = "\n"),
      "\nSTDERR: ",
      paste(stderr_lines, collapse = "\n")
    )
  }

  # Create worker info with proper Docker tracking
  worker_info <- list(
    process = proc,
    port = port,
    started_at = Sys.time(),
    is_docker = use_docker
  )

  # If this is a Docker worker, store the container name in worker_info too
  if (use_docker) {
    container_name <- attr(proc, "container_name")
    if (!is.null(container_name)) {
      worker_info$container_name <- container_name
    }
  }

  worker_info
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
        # Try to get debug logs from worker before failing
        worker_logs <- get_worker_debug_logs(worker_info)
        if (length(worker_logs) > 0) {
          debug_log("Worker debug logs:")
          for (log_line in worker_logs) {
            debug_log("  ", log_line)
          }
        }
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

  # Try to send shutdown message first (if socket connection exists)
  tryCatch(
    {
      if (!is.null(worker_info$port)) {
        debug_log(
          "Sending shutdown message to worker on port ",
          worker_info$port
        )

        # Create a temporary socket to send shutdown message
        sock <- create_req_socket(worker_info$port)
        if (!is.null(sock)) {
          send_result <- nanonext::send(sock, "__SHUTDOWN__")
          close(sock)
          debug_log("Shutdown message sent, result: ", send_result)

          # Give worker a moment to process shutdown message
          Sys.sleep(0.2)
        }
      }
    },
    error = function(e) {
      debug_log("Failed to send shutdown message: ", e$message)
    }
  )

  # Try graceful shutdown with SIGINT as fallback
  tryCatch(
    {
      if (proc$is_alive()) {
        debug_log("Sending SIGINT to worker process")
        proc$signal(2) # SIGINT
      }
    },
    error = function(e) {
      debug_log("Failed to send SIGINT: ", e$message)
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
    debug_log("Worker did not stop gracefully, killing process")
    proc$kill()
    Sys.sleep(0.1)
  }

  # Clean up Docker container if this was a Docker worker
  container_name <- attr(proc, "container_name")
  if (is.null(container_name) && !is.null(worker_info$container_name)) {
    # Fallback to container name from worker_info
    container_name <- worker_info$container_name
  }

  if (!is.null(container_name)) {
    debug_log("Cleaning up Docker container: ", container_name)
    tryCatch(
      {
        # Force remove the container
        system2(
          "docker",
          c("rm", "-f", container_name),
          stdout = FALSE,
          stderr = FALSE
        )
      },
      error = function(e) {
        debug_warn("Failed to clean up Docker container: ", e$message)
      }
    )
  }

  !proc$is_alive()
}

#' Get Debug Logs from Worker
#'
#' Retrieve debug logs from a running worker process
#'
#' @param worker_info list, worker info returned by start_worker()
#' @return character vector of debug log messages
#' @export
get_worker_debug_logs <- function(worker_info) {
  if (is.null(worker_info) || is.null(worker_info$process)) {
    return(character(0))
  }

  if (!worker_info$process$is_alive()) {
    return(character(0))
  }

  tryCatch(
    {
      # Read stdout and stderr from worker process
      stdout_lines <- worker_info$process$read_output_lines()
      stderr_lines <- worker_info$process$read_error_lines()

      # Combine and return all lines
      all_lines <- c(stdout_lines, stderr_lines)
      return(all_lines)
    },
    error = function(e) {
      warning("Failed to retrieve debug logs: ", e$message)
      return(character(0)) # nolint
    }
  )
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
  tryCatch(
    {
      result <- system2(
        "docker",
        c("version", "--format", "'{{.Client.Version}}'"),
        stdout = TRUE,
        stderr = TRUE
      )
      # If no error and got output, Docker is available
      return(length(result) > 0 && !inherits(result, "try-error"))
    },
    error = function(e) {
      return(FALSE) # nolint
    }
  )
}

#' Get Docker Image Name for Worker
#'
#' Get the Docker image name to use for worker containers.
#' Reads from option 'replr.worker.docker.image' if set, otherwise uses default.
#'
#' @return character, Docker image name
get_worker_docker_image <- function() {
  getOption("replr.worker.docker.image", default = "replr-worker:latest")
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

  # Get configurable resource limits
  memory_limit <- getOption("replr.worker.docker.memory", default = "512m")
  cpu_limit <- getOption("replr.worker.docker.cpus", default = "1.0")

  # Generate a unique container name for cleanup tracking
  container_name <- paste0(
    "replr-worker-",
    port,
    "-",
    format(Sys.time(), "%Y%m%d-%H%M%S")
  )

  # Build base Docker arguments with improved networking
  docker_args <- c(
    "run",
    "--name",
    container_name, # Name for cleanup
    "--rm", # Remove container when done
    "--user",
    "replr", # Run as non-root user
    "--memory",
    memory_limit, # Memory limit (configurable)
    "--cpus",
    cpu_limit, # CPU limit (configurable)
    "-p",
    sprintf("%i:%i", port, port), # Expose port (not strictly needed with host network)
    "--read-only", # Read-only filesystem
    "--tmpfs",
    "/tmp:noexec,nosuid,size=100m", # Writable tmp directory with restrictions
    "--security-opt",
    "no-new-privileges", # Prevent privilege escalation
    "--cap-drop",
    "ALL",
    "-v",
    paste0(worker_script, ":/app/worker.R:ro") # Mount worker script
  )

  debug_log("Using Docker options: {docker_args}")

  # Add image and command
  docker_args <- c(
    docker_args,
    image_name,
    "Rscript",
    "/app/worker.R",
    as.character(port),
    "--listen-all" # Listen on all interfaces inside Docker so port forwarding works
  )

  # Add debug flag if present in worker_args
  if ("--debug" %in% worker_args) {
    docker_args <- c(docker_args, "--debug")
  }

  debug_log("Starting Docker container with args: {docker_args}")

  # Start Docker container
  proc <- processx::process$new(
    command = "docker",
    args = docker_args,
    stdout = "|",
    stderr = "|",
    cleanup = TRUE,
    cleanup_tree = TRUE
  )

  # Return process with container name stored separately
  # We can't add fields to the processx object directly due to locked environment
  attr(proc, "container_name") <- container_name

  return(proc) # nolint
}

#' Check if Docker Image Exists
#'
#' @param image_name character, Docker image name
#' @return logical, TRUE if image exists
docker_image_exists <- function(image_name) {
  tryCatch(
    {
      result <- system2(
        "docker",
        c("image", "inspect", image_name),
        stdout = FALSE,
        stderr = FALSE
      )
      return(result == 0)
    },
    error = function(e) {
      return(FALSE) # nolint
    }
  )
}

#' Build or Pull Worker Docker Image
#'
#' Build the Docker image for worker containers from local Dockerfile,
#' or pull it from a registry if it appears to be a remote image
#'
#' @param image_name character, Docker image name to build or pull
build_worker_docker_image <- function(image_name) {
  # Check if this looks like a remote image (contains "/" indicating registry/username)
  is_remote_image <- grepl("/", image_name)

  if (is_remote_image) {
    # Try to pull the remote image
    debug_log("Pulling Docker image:", image_name)

    pull_result <- tryCatch(
      {
        result <- system2(
          "docker",
          c("pull", image_name),
          stdout = TRUE,
          stderr = TRUE
        )

        # Check if pull was successful
        if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
          list(success = FALSE, output = result)
        } else {
          list(success = TRUE, output = result)
        }
      },
      error = function(e) {
        list(success = FALSE, output = e$message)
      }
    )

    if (pull_result$success) {
      debug_success("Docker image pulled successfully:", image_name)
      return(invisible())
    } else {
      debug_log("Failed to pull image, will try to build locally")
      debug_log("Pull error:", paste(pull_result$output, collapse = "\n"))
    }
  }

  # Fall back to building from local Dockerfile
  dockerfile_path <- file.path(system.file(package = "replr"), "Dockerfile")

  # during development, also check inst/Dockerfile and working dir
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
    if (is_remote_image) {
      stop(
        "Failed to pull remote image '",
        image_name,
        "' and no local Dockerfile found. Cannot obtain Docker image."
      )
    } else {
      stop("Dockerfile not found. Cannot build Docker image.")
    }
  }

  # Build the image
  build_args <- c(
    "build",
    "-t",
    image_name,
    "-f",
    dockerfile_path,
    dirname(dockerfile_path)
  )

  debug_log("Building Docker image:", image_name)
  result <- system2("docker", build_args, stdout = TRUE, stderr = TRUE)

  if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
    stop(
      "Failed to build Docker image. Docker output:\n",
      paste(result, collapse = "\n")
    )
  }

  debug_success("Docker image built successfully:", image_name)
}

#' Clean up orphaned replr Docker containers
#'
#' Remove any leftover replr worker containers that may be running
#'
#' @return logical, TRUE if cleanup was successful
#' @export
cleanup_docker_containers <- function() {
  if (!is_docker_available()) {
    warning("Docker is not available")
    return(FALSE)
  }

  tryCatch(
    {
      debug_log("Cleaning up orphaned replr Docker containers")

      # Find all replr worker containers
      containers <- system2(
        "docker",
        c(
          "ps",
          "-a",
          "--filter",
          "name=replr-worker-",
          "--format",
          "{{.Names}}"
        ),
        stdout = TRUE,
        stderr = FALSE
      )

      if (
        length(containers) > 0 &&
          !is.null(attr(containers, "status")) &&
          attr(containers, "status") == 0
      ) {
        # No containers found or command failed
        debug_log("No orphaned replr containers found")
        return(TRUE)
      }

      if (length(containers) > 0) {
        debug_log(
          "Found ",
          length(containers),
          " orphaned containers: ",
          paste(containers, collapse = ", ")
        )

        # Remove all found containers
        result <- system2(
          "docker",
          c("rm", "-f", containers),
          stdout = FALSE,
          stderr = FALSE
        )

        if (is.null(attr(result, "status")) || attr(result, "status") == 0) {
          debug_success(
            "Cleaned up ",
            length(containers),
            " orphaned containers"
          )
          return(TRUE)
        } else {
          debug_warn("Failed to remove some containers")
          return(FALSE)
        }
      } else {
        debug_log("No orphaned replr containers found")
        return(TRUE)
      }
    },
    error = function(e) {
      debug_error("Error during Docker container cleanup: ", e$message)
      return(FALSE)
    }
  )
}
