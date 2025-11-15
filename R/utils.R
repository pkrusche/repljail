#' Check Package Dependencies
#'
#' Verify that all required packages are available and compatible
#'
#' @return logical indicating if all dependencies are satisfied
#' @export
check_dependencies <- function() {
  required_packages <- c(
    "nanonext",
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
#' Can use different isolation strategies: native, Docker, or firejail.
#' Isolation method is controlled by options: 'replr.use.firejail' or 'replr.use.docker'.
#'
#' @param port integer, port number for the worker to listen on
#' @param timeout numeric, timeout in seconds to wait for worker startup
#' @return list with process object and connection info
#' @keywords internal
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

  # Create the appropriate worker wrapper based on options
  wrapper <- create_worker_wrapper()
  wrapper_metadata <- wrapper$get_metadata()
  wrapper_type <- wrapper_metadata$type

  debug_log("Using worker wrapper type: ", wrapper_type)

  # Start the worker process using the wrapper
  wrapper_result <- wrapper$start_process(port, worker_script, worker_args, timeout)
  proc <- wrapper_result$process

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
        # Use longer timeout for Docker gateway scenarios
        sock <- create_req_socket(port, timeout = 3)
        # Simple ping test
        result <- send_request(sock, "1", id = "ping", timeout = 3)
        if (!is.null(result)) {
          close_socket(sock)
          worker_ready <- TRUE
          break
        }
        close_socket(sock)
      },
      error = function(e) {
        # Worker not ready yet, continue waiting
        debug_log(paste0("Ping attempt failed: ", e$message))
      }
    )

    Sys.sleep(1) # Wait between attempts
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
    container_name <- wrapper_result$container_name
    gateway_name <- wrapper_result$gateway_name
    network_name <- wrapper_result$network_name
    if (wrapper_type == "docker" && !is.null(container_name)) {
      debug_log("Cleaning up failed Docker container: ", container_name)
      tryCatch(
        {
          # Build list of containers to remove
          containers_to_remove <- container_name
          if (!is.null(gateway_name)) {
            containers_to_remove <- c(containers_to_remove, gateway_name)
          }

          # Force remove the container(s) if they exist
          system2(
            "docker",
            c("rm", "-f", containers_to_remove),
            stdout = FALSE,
            stderr = FALSE
          )
        },
        error = function(e) {
          debug_warn("Failed to clean up Docker container: ", e$message)
        }
      )

      # Clean up network if it was created
      if (!is.null(network_name)) {
        debug_log("Cleaning up failed Docker network: ", network_name)
        remove_docker_network(network_name)
      }
    }

    # Wait for graceful shutdown
    start_time <- Sys.time()
    # Shorter timeout for Docker/firejail
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
      if (wrapper_type %in% c("docker", "firejail")) {
        paste0("\nNote: This was a ", wrapper_type, " worker startup failure\n")
      } else {
        ""
      },
      "\nSTDOUT: ",
      paste(stdout_lines, collapse = "\n"),
      "\nSTDERR: ",
      paste(stderr_lines, collapse = "\n")
    )
  }

  # Create worker info with proper tracking
  worker_info <- list(
    process = proc,
    port = port,
    started_at = Sys.time(),
    wrapper_type = wrapper_type,
    # Legacy field for backward compatibility
    is_docker = (wrapper_type == "docker")
  )

  # If this is a Docker worker, store the container name in worker_info too
  if (wrapper_type == "docker") {
    if (!is.null(wrapper_result$container_name)) {
      worker_info$container_name <- wrapper_result$container_name
    }
    if (!is.null(wrapper_result$network_name)) {
      worker_info$network_name <- wrapper_result$network_name
    }
    if (!is.null(wrapper_result$gateway_name)) {
      worker_info$gateway_name <- wrapper_result$gateway_name
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
#' @keywords internal
send_command <- function(worker_info, code, timeout = 30) {
  if (is.null(worker_info$process) || !worker_info$process$is_alive()) {
    stop("Worker process is not running")
  }

  # Create socket connection
  sock <- create_req_socket(worker_info$port, timeout = timeout)

  tryCatch(
    {
      # Send request
      response <- send_request(sock, code, timeout = timeout)

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
#' @keywords internal
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

  # Clean up Docker containers if this was a Docker worker
  container_name <- attr(proc, "container_name")
  if (is.null(container_name) && !is.null(worker_info$container_name)) {
    # Fallback to container name from worker_info
    container_name <- worker_info$container_name
  }

  # Get gateway name for cleanup
  gateway_name <- attr(proc, "gateway_name")
  if (is.null(gateway_name) && !is.null(worker_info$gateway_name)) {
    # Fallback to gateway name from worker_info
    gateway_name <- worker_info$gateway_name
  }

  # Get network name for cleanup
  network_name <- attr(proc, "network_name")
  if (is.null(network_name) && !is.null(worker_info$network_name)) {
    # Fallback to network name from worker_info
    network_name <- worker_info$network_name
  }

  if (!is.null(container_name)) {
    debug_log("Cleaning up Docker containers: ", container_name)
    tryCatch(
      {
        # Build list of containers to remove
        containers_to_remove <- container_name
        if (!is.null(gateway_name)) {
          containers_to_remove <- c(containers_to_remove, gateway_name)
          debug_log("Also cleaning up gateway: ", gateway_name)
        }

        # Force remove the container(s)
        system2(
          "docker",
          c("rm", "-f", containers_to_remove),
          stdout = FALSE,
          stderr = FALSE
        )
      },
      error = function(e) {
        debug_warn("Failed to clean up Docker containers: ", e$message)
      }
    )

    # Clean up network if it exists
    if (!is.null(network_name)) {
      debug_log("Cleaning up Docker network: ", network_name)
      remove_docker_network(network_name)
    }
  }

  !proc$is_alive()
}

#' Get Debug Logs from Worker
#'
#' Retrieve debug logs from a running worker process
#'
#' @param worker_info list, worker info returned by start_worker()
#' @return character vector of debug log messages
#' @keywords internal
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

  # Check if network isolation is enabled
  use_network_isolation <- getOption(
    "replr.worker.docker.network.isolation",
    default = FALSE
  )
  network_name <- NULL

  # Create isolated network if enabled
  if (use_network_isolation) {
    network_name <- paste0(
      "replr-network-",
      port,
      "-",
      format(Sys.time(), "%Y%m%d-%H%M%S")
    )
    if (!create_docker_network(network_name)) {
      warning(
        "Failed to create isolated network, proceeding without network isolation"
      )
      use_network_isolation <- FALSE
      network_name <- NULL
    }
  }

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

  # Add network configuration
  if (use_network_isolation && !is.null(network_name)) {
    # Use isolated internal network (no internet access)
    # Worker will not expose ports directly; gateway sidecar handles host communication
    docker_args <- c(docker_args, "--network", network_name)
  } else {
    # No network isolation: expose port directly for communication
    docker_args <- c(
      docker_args,
      "-p",
      sprintf("%i:%i", port, port)
    )
  }

  debug_log("Using Docker options: {docker_args}")

  # Add image and command
  docker_args <- c(
    docker_args,
    image_name,
    "Rscript",
    "/app/worker.R",
    as.character(port)
  )

  # Add --listen-all for Docker mode (needed for gateway to reach worker)
  docker_args <- c(docker_args, "--listen-all")

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

  # Store container metadata
  attr(proc, "container_name") <- container_name
  gateway_name <- NULL

  # If network isolation is enabled, start gateway sidecar for host communication
  if (use_network_isolation && !is.null(network_name)) {
    attr(proc, "network_name") <- network_name

    # Start gateway container with socat for port forwarding
    gateway_name <- paste0(
      "replr-gateway-",
      port,
      "-",
      format(Sys.time(), "%Y%m%d-%H%M%S")
    )

    debug_log(paste0("Starting gateway container: ", gateway_name))
    debug_log(paste0("Worker container name: ", container_name))
    debug_log(paste0("Port: ", port))

    # Build gateway command
    socat_command <- sprintf(
      "TCP-LISTEN:8080,fork,reuseaddr TCP:%s:%i",
      container_name,
      port
    )
    debug_log(paste0("Socat command: ", socat_command))

    gateway_args <- c(
      "run",
      "-d", # Detached mode
      "--name",
      gateway_name,
      "--rm", # Auto-remove when stopped
      "-p",
      sprintf("127.0.0.1:%i:8080", port), # Map host port to gateway
      "alpine/socat",
      socat_command
    )

    debug_log(paste0("Gateway args length: ", length(gateway_args)))

    # Gateway forwards host:<port> -> worker:<port>
    gateway_result <- system2(
      "docker",
      gateway_args,
      stdout = TRUE,
      stderr = TRUE
    )

    # Debug gateway result details
    debug_log(paste0("Gateway result length: ", length(gateway_result)))
    if (length(gateway_result) > 0) {
      debug_log(paste0("Gateway result[1]: '", gateway_result[1], "'"))
      debug_log(paste0("Gateway result[1] nchar: ", nchar(gateway_result[1])))
    }

    # Check for errors
    gateway_status <- attr(gateway_result, "status")
    debug_log(paste0(
      "Gateway status: ",
      ifelse(is.null(gateway_status), "NULL", gateway_status)
    ))

    if (!is.null(gateway_status) && gateway_status != 0) {
      # Gateway failed to start, cleanup worker
      debug_error(paste0(
        "Gateway container failed to start. Status: ",
        gateway_status
      ))
      debug_error(paste0(
        "Gateway stdout: ",
        paste(gateway_result, collapse = "\n")
      ))
      system2(
        "docker",
        c("rm", "-f", container_name),
        stdout = FALSE,
        stderr = FALSE
      )
      stop("Failed to start gateway container for network isolation")
    }

    if (
      is.null(gateway_result) ||
        length(gateway_result) == 0 ||
        nchar(gateway_result[1]) < 10
    ) {
      debug_error("Gateway container did not return valid container ID")
      debug_error(paste0(
        "Detailed: length=",
        length(gateway_result),
        " content=",
        if (length(gateway_result) > 0) gateway_result[1] else "EMPTY"
      ))
      system2(
        "docker",
        c("rm", "-f", container_name),
        stdout = FALSE,
        stderr = FALSE
      )
      stop("Failed to get gateway container ID")
    }

    debug_log(paste0(
      "Gateway container ID: ",
      substr(gateway_result[1], 1, 12)
    ))

    # Connect gateway to internal network so it can reach worker
    debug_log(paste0("Connecting gateway to internal network: ", network_name))
    connect_result <- system2(
      "docker",
      c("network", "connect", network_name, gateway_name),
      stdout = FALSE,
      stderr = FALSE
    )

    if (
      !is.null(attr(connect_result, "status")) &&
        attr(connect_result, "status") != 0
    ) {
      # Failed to connect gateway, cleanup both containers
      debug_error("Failed to connect gateway to internal network")
      system2(
        "docker",
        c("rm", "-f", container_name, gateway_name),
        stdout = FALSE,
        stderr = FALSE
      )
      stop("Failed to connect gateway to internal network")
    }

    debug_success(paste0(
      "Gateway container started and connected: ",
      gateway_name
    ))
    attr(proc, "gateway_name") <- gateway_name

    # Verify gateway is still running after network connect
    gateway_check <- system2(
      "docker",
      c("ps", "-q", "--filter", paste0("name=", gateway_name)),
      stdout = TRUE,
      stderr = FALSE
    )

    if (length(gateway_check) == 0 || nchar(gateway_check[1]) == 0) {
      # Gateway died - check logs
      gateway_logs <- system2(
        "docker",
        c("logs", gateway_name),
        stdout = TRUE,
        stderr = TRUE
      )
      debug_error(paste0(
        "Gateway container died after starting. Logs: ",
        paste(gateway_logs, collapse = "\n")
      ))
      system2(
        "docker",
        c("rm", "-f", container_name, gateway_name),
        stdout = FALSE,
        stderr = FALSE
      )
      stop("Gateway container exited unexpectedly")
    }

    debug_log("Gateway is running, waiting for it to initialize...")
    # Give gateway significant time to start listening before returning
    # socat needs time to initialize, and NNG protocol handshake needs to establish
    # We need to wait for: container start + socat init + NNG dial to succeed
    Sys.sleep(3)

    # Check gateway logs for any errors
    gateway_logs <- system2(
      "docker",
      c("logs", gateway_name),
      stdout = TRUE,
      stderr = TRUE
    )
    if (length(gateway_logs) > 0) {
      debug_log(paste0("Gateway logs: ", paste(gateway_logs, collapse = " | ")))
    }

    debug_log("Gateway initialization complete")
  }

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
      worker_containers <- system2(
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

      # Find all replr gateway containers
      gateway_containers <- system2(
        "docker",
        c(
          "ps",
          "-a",
          "--filter",
          "name=replr-gateway-",
          "--format",
          "{{.Names}}"
        ),
        stdout = TRUE,
        stderr = FALSE
      )

      # Combine all containers
      all_containers <- c(worker_containers, gateway_containers)
      all_containers <- all_containers[nchar(all_containers) > 0]

      if (length(all_containers) == 0) {
        debug_log("No orphaned replr containers found")
        return(TRUE)
      }

      debug_log(
        "Found ",
        length(all_containers),
        " orphaned containers: ",
        paste(all_containers, collapse = ", ")
      )

      # Remove all found containers
      result <- system2(
        "docker",
        c("rm", "-f", all_containers),
        stdout = FALSE,
        stderr = FALSE
      )

      if (is.null(attr(result, "status")) || attr(result, "status") == 0) {
        debug_success(
          "Cleaned up ",
          length(all_containers),
          " orphaned containers"
        )
        return(TRUE)
      } else {
        debug_warn("Failed to remove some containers")
        return(FALSE)
      }
    },
    error = function(e) {
      debug_error("Error during Docker container cleanup: ", e$message)
      return(FALSE)
    }
  )
}

#' Create an Isolated Docker Network
#'
#' Creates an isolated Docker network with no external access for a worker container.
#' The network uses the bridge driver and is marked as internal.
#'
#' @param network_name character, name for the Docker network
#' @return logical, TRUE if network creation was successful
#' @keywords internal
create_docker_network <- function(network_name) {
  if (!is_docker_available()) {
    warning("Docker is not available")
    return(FALSE)
  }

  tryCatch(
    {
      debug_log("Creating isolated Docker network: ", network_name)

      # Create internal bridge network for complete isolation
      # The --internal flag blocks all external network access (no internet)
      # A gateway sidecar container bridges host-to-worker communication
      # Note: We do NOT use enable_icc=false because the gateway MUST communicate with the worker
      result <- system2(
        "docker",
        c(
          "network",
          "create",
          "--driver",
          "bridge",
          "--internal", # Block all external access (no internet)
          "--subnet",
          "172.28.0.0/16", # Custom subnet to avoid conflicts
          network_name
        ),
        stdout = TRUE,
        stderr = TRUE
      )

      if (is.null(attr(result, "status")) || attr(result, "status") == 0) {
        debug_success("Created isolated network: ", network_name)
        return(TRUE)
      } else {
        debug_warn(
          "Failed to create Docker network: ",
          paste(result, collapse = "\n")
        )
        return(FALSE)
      }
    },
    error = function(e) {
      debug_error("Error creating Docker network: ", e$message)
      return(FALSE) # nolint
    }
  )
}

#' Remove a Docker Network
#'
#' Removes a Docker network if it exists
#'
#' @param network_name character, name of the Docker network to remove
#' @return logical, TRUE if network removal was successful
#' @keywords internal
remove_docker_network <- function(network_name) {
  if (!is_docker_available()) {
    return(FALSE)
  }

  tryCatch(
    {
      debug_log("Removing Docker network: ", network_name)

      result <- system2(
        "docker",
        c("network", "rm", network_name),
        stdout = FALSE,
        stderr = FALSE
      )

      if (is.null(attr(result, "status")) || attr(result, "status") == 0) {
        debug_log("Removed Docker network: ", network_name)
        return(TRUE)
      } else {
        debug_warn("Failed to remove Docker network: ", network_name)
        return(FALSE)
      }
    },
    error = function(e) {
      debug_log("Error removing Docker network: ", e$message)
      return(FALSE) # nolint
    }
  )
}

#' Cleanup Orphaned Docker Networks
#'
#' Remove orphaned replr Docker networks that may have been left behind
#'
#' @return logical, TRUE if cleanup was successful
#' @export
cleanup_docker_networks <- function() {
  if (!is_docker_available()) {
    warning("Docker is not available")
    return(FALSE)
  }

  tryCatch(
    {
      debug_log("Cleaning up orphaned replr Docker networks")

      # Find all replr worker networks
      networks <- system2(
        "docker",
        c(
          "network",
          "ls",
          "--filter",
          "name=replr-network-",
          "--format",
          "{{.Name}}"
        ),
        stdout = TRUE,
        stderr = FALSE
      )

      if (
        length(networks) > 0 &&
          !is.null(attr(networks, "status")) &&
          attr(networks, "status") == 0
      ) {
        # No networks found or command failed
        debug_log("No orphaned replr networks found")
        return(TRUE)
      }

      if (length(networks) > 0) {
        debug_log(
          "Found ",
          length(networks),
          " orphaned networks: ",
          paste(networks, collapse = ", ")
        )

        # Remove all found networks
        for (network in networks) {
          remove_docker_network(network)
        }

        debug_success(
          "Cleaned up ",
          length(networks),
          " orphaned networks"
        )
        return(TRUE)
      } else {
        debug_log("No orphaned replr networks found")
        return(TRUE)
      }
    },
    error = function(e) {
      debug_error("Error during Docker network cleanup: ", e$message)
      return(FALSE)
    }
  )
}
