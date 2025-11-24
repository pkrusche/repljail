#' Worker Wrapper Base Class
#'
#' Base R6 class for worker process wrappers that encapsulate different
#' isolation strategies (native, Docker, firejail, etc.)
#'
#' @keywords internal
WorkerWrapper <- R6::R6Class(
  "WorkerWrapper",
  public = list(
    #' @description
    #' Start the worker process
    #' @param port integer, port number for worker to listen on
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    #' @return list with process object and connection info
    start_process = function(port, worker_script, worker_args, timeout) {
      stop("start_process must be implemented by subclass")
    },

    #' @description
    #' Get the port number for connecting to the worker
    #' @return integer, port number
    get_port = function() {
      private$.port
    },

    #' @description
    #' Get the process object
    #' @return processx process object
    get_process = function() {
      private$.process
    },

    #' @description
    #' Get metadata about this wrapper
    #' @return list with wrapper type and other metadata
    get_metadata = function() {
      list(
        type = private$.type
      )
    }
  ),
  private = list(
    .port = NULL,
    .process = NULL,
    .type = "base"
  )
)

#' Native Worker Wrapper
#'
#' Worker wrapper for native R processes (no sandboxing)
#'
#' @keywords internal
NativeWorkerWrapper <- R6::R6Class(
  "NativeWorkerWrapper",
  inherit = WorkerWrapper,
  public = list(
    #' @description
    #' Start a native worker process using processx
    #' @param port integer, port number for worker to listen on (unused, kept for compatibility)
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    start_process = function(port, worker_script, worker_args, timeout) {
      debug_log("Starting native worker process with IPC")

      # Generate IPC socket path
      socket_path <- get_ipc_socket_path()
      debug_log("Using IPC socket path: ", socket_path)

      # Replace the port argument with socket path for IPC mode
      # worker_args[2] is the port/socket_path argument
      worker_args[2] <- socket_path

      # Prepare environment for worker process
      worker_env <- Sys.getenv()
      # Pass current library paths to worker
      worker_env[["R_LIBS_USER"]] <- paste(
        .libPaths(),
        collapse = .Platform$path.sep
      )

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

      private$.socket_path <- socket_path
      private$.process <- proc

      debug_success("Native worker process started with IPC")

      list(
        process = proc,
        port = port, # Keep for compatibility, but not used
        socket_path = socket_path
      )
    }
  ),
  private = list(
    .type = "native",
    .socket_path = NULL
  )
)

#' Docker Worker Wrapper
#'
#' Worker wrapper for Docker container isolation
#'
#' @keywords internal
DockerWorkerWrapper <- R6::R6Class(
  "DockerWorkerWrapper",
  inherit = WorkerWrapper,
  public = list(
    #' @description
    #' Start a worker process inside a Docker container
    #' @param port integer, port number for worker to listen on
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    start_process = function(port, worker_script, worker_args, timeout) {
      debug_log("Starting Docker worker process on port ", port)

      image_name <- get_worker_docker_image()

      # Build Docker image if it doesn't exist
      if (!docker_image_exists(image_name)) {
        build_worker_docker_image(image_name)
      }

      # Get configurable resource limits
      memory_limit <- getOption("repljail.worker.docker.memory", default = "512m")
      cpu_limit <- getOption("repljail.worker.docker.cpus", default = "1.0")

      # Generate a unique container name for cleanup tracking
      container_name <- paste0(
        "repljail-worker-",
        port,
        "-",
        format(Sys.time(), "%Y%m%d-%H%M%S")
      )

      # Check if network isolation is enabled
      use_network_isolation <- getOption(
        "repljail.worker.docker.network.isolation",
        default = FALSE
      )
      network_name <- NULL

      # Create isolated network if enabled
      if (use_network_isolation) {
        network_name <- paste0(
          "repljail-network-",
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

      # Build base Docker arguments
      docker_args <- c(
        "run",
        "--name",
        container_name,
        "--rm",
        "--user",
        "repljail",
        "--memory",
        memory_limit,
        "--cpus",
        cpu_limit,
        "--read-only",
        "--tmpfs",
        "/tmp:noexec,nosuid,size=100m",
        "--security-opt",
        "no-new-privileges",
        "--cap-drop",
        "ALL",
        "-v",
        paste0(worker_script, ":/app/worker.R:ro")
      )

      # Add network configuration
      if (use_network_isolation && !is.null(network_name)) {
        docker_args <- c(docker_args, "--network", network_name)
      } else {
        docker_args <- c(
          docker_args,
          "-p",
          sprintf("%i:%i", port, port)
        )
      }

      # Add image and command
      docker_args <- c(
        docker_args,
        image_name,
        "Rscript",
        "/app/worker.R",
        as.character(port),
        "--listen-all"
      )

      # Add debug flag if present
      if ("--debug" %in% worker_args) {
        docker_args <- c(docker_args, "--debug")
      }

      debug_log(
        "Starting Docker container with args: ",
        paste(docker_args, collapse = " ")
      )

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
      private$.container_name <- container_name
      private$.network_name <- network_name

      # If network isolation is enabled, start gateway sidecar
      if (use_network_isolation && !is.null(network_name)) {
        attr(proc, "network_name") <- network_name

        gateway_name <- paste0(
          "repljail-gateway-",
          port,
          "-",
          format(Sys.time(), "%Y%m%d-%H%M%S")
        )

        debug_log("Starting gateway container: ", gateway_name)

        # Build gateway command
        socat_command <- sprintf(
          "TCP-LISTEN:8080,fork,reuseaddr TCP:%s:%i",
          container_name,
          port
        )

        gateway_args <- c(
          "run",
          "-d",
          "--name",
          gateway_name,
          "--rm",
          "-p",
          sprintf("127.0.0.1:%i:8080", port),
          "alpine/socat",
          socat_command
        )

        gateway_result <- system2(
          "docker",
          gateway_args,
          stdout = TRUE,
          stderr = TRUE
        )

        # Check for errors
        gateway_status <- attr(gateway_result, "status")
        if (!is.null(gateway_status) && gateway_status != 0) {
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
          system2(
            "docker",
            c("rm", "-f", container_name),
            stdout = FALSE,
            stderr = FALSE
          )
          stop("Failed to get gateway container ID")
        }

        # Connect gateway to internal network
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
          system2(
            "docker",
            c("rm", "-f", container_name, gateway_name),
            stdout = FALSE,
            stderr = FALSE
          )
          stop("Failed to connect gateway to internal network")
        }

        attr(proc, "gateway_name") <- gateway_name
        private$.gateway_name <- gateway_name

        debug_success("Gateway container started: ", gateway_name)
        Sys.sleep(3) # Allow gateway to initialize
      }

      private$.port <- port
      private$.process <- proc

      debug_success("Docker worker process started")

      list(
        process = proc,
        port = port,
        container_name = container_name,
        network_name = network_name,
        gateway_name = private$.gateway_name
      )
    },

    #' @description
    #' Get additional metadata for Docker wrapper
    get_metadata = function() {
      metadata <- super$get_metadata()
      metadata$container_name <- private$.container_name
      metadata$network_name <- private$.network_name
      metadata$gateway_name <- private$.gateway_name
      metadata
    }
  ),
  private = list(
    .type = "docker",
    .container_name = NULL,
    .network_name = NULL,
    .gateway_name = NULL
  )
)

#' Firejail Worker Wrapper
#'
#' Worker wrapper for firejail sandbox isolation
#'
#' @keywords internal
FirejailWorkerWrapper <- R6::R6Class(
  "FirejailWorkerWrapper",
  inherit = WorkerWrapper,
  public = list(
    #' @description
    #' Start a worker process inside a firejail sandbox
    #' @param port integer, port number for worker to listen on (unused, kept for compatibility)
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    start_process = function(port, worker_script, worker_args, timeout) {
      debug_log("Starting firejail worker process with IPC")

      # Check firejail availability
      if (!is_firejail_available()) {
        stop(
          "Firejail is not available. Cannot start worker in firejail sandbox."
        )
      }

      # Generate IPC socket path
      socket_path <- get_ipc_socket_path()
      debug_log("Using IPC socket path: ", socket_path)

      # Replace the port argument with socket path for IPC mode
      # worker_args[2] is the port/socket_path argument
      worker_args[2] <- socket_path

      # Get custom profile if specified
      custom_profile <- getOption(
        "repljail.worker.firejail.profile",
        default = NULL
      )

      # Build firejail arguments
      firejail_args <- c("--quiet")

      if (!is.null(custom_profile) && file.exists(custom_profile)) {
        # Use custom profile
        debug_log("Using custom firejail profile: ", custom_profile)
        firejail_args <- c(firejail_args, paste0("--profile=", custom_profile))
      } else {
        # Use default security settings
        # Network isolation - completely disable network access
        # Since we use IPC sockets (not TCP), the worker doesn't need any network access
        # --net=none works even with restricted_networking yes in firejail.config
        firejail_args <- c(firejail_args, "--net=none")
        debug_log("Using firejail with complete network isolation (--net=none)")

        # Filesystem restrictions
        # Whitelist the socket directory for IPC communication
        # Note: We cannot use --private-tmp with IPC sockets because --private-tmp
        # creates a completely isolated /tmp that cannot be shared with the host.
        # Instead, we use --whitelist to allow access to the socket's parent directory.
        # This allows the worker to create the socket file and the parent to access it.
        socket_dir <- dirname(socket_path)
        firejail_args <- c(firejail_args, paste0("--whitelist=", socket_dir))
        debug_log("Whitelisting socket directory for IPC: ", socket_dir)

        # Additional security options
        firejail_args <- c(
          firejail_args,
          "--caps.drop=all", # Drop all capabilities
          "--seccomp", # Enable seccomp filtering
          "--nonewprivs", # Prevent privilege escalation
          "--noroot", # Run as regular user
          "--nosound", # Disable sound
          "--novideo", # Disable video
          "--no3d", # Disable 3D acceleration
          "--nodvd", # Disable DVD
          "--notv" # Disable TV
        )
      }

      # Add the command to execute
      firejail_args <- c(
        firejail_args,
        file.path(R.home("bin"), "Rscript"),
        worker_args
      )

      debug_log("Firejail args: ", paste(firejail_args, collapse = " "))

      # Prepare environment for worker process
      worker_env <- Sys.getenv()
      worker_env[["R_LIBS_USER"]] <- paste(
        .libPaths(),
        collapse = .Platform$path.sep
      )

      # Start firejail process
      proc <- processx::process$new(
        command = "firejail",
        args = firejail_args,
        stdout = "|",
        stderr = "|",
        cleanup = TRUE,
        cleanup_tree = TRUE,
        env = worker_env
      )

      private$.socket_path <- socket_path
      private$.process <- proc

      debug_success("Firejail worker process started with IPC")

      list(
        process = proc,
        port = port, # Keep for compatibility, but not used
        socket_path = socket_path
      )
    }
  ),
  private = list(
    .type = "firejail",
    .socket_path = NULL
  )
)

#' macOS Sandbox Worker Wrapper
#'
#' Worker wrapper for macOS sandbox-exec isolation
#'
#' @keywords internal
MacOSSandboxWorkerWrapper <- R6::R6Class(
  "MacOSSandboxWorkerWrapper",
  inherit = WorkerWrapper,
  public = list(
    #' @description
    #' Start a worker process inside a macOS sandbox
    #' @param port integer, port number for worker to listen on
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    start_process = function(port, worker_script, worker_args, timeout) {
      debug_log("Starting macOS sandbox worker process on port ", port)

      # Check macOS sandbox availability
      if (!is_macos_sandbox_available()) {
        stop(
          "macOS sandbox-exec is not available. Cannot start worker in macOS sandbox."
        )
      }

      # Get custom profile if specified
      custom_profile <- getOption(
        "repljail.worker.macos.sandbox.profile",
        default = NULL
      )

      # Create temporary profile file
      profile_file <- NULL
      if (!is.null(custom_profile) && file.exists(custom_profile)) {
        # Use custom profile
        debug_log("Using custom macOS sandbox profile: ", custom_profile)
        profile_file <- custom_profile
      } else {
        # Create default security profile
        profile_file <- tempfile(fileext = ".sb")
        private$.temp_profile <- profile_file

        # Default macOS sandbox profile using Sandbox Profile Language (SBPL)
        # Provides network isolation and filesystem write restrictions
        profile_content <- c(
          "; macOS Sandbox Profile for repljail worker",
          "; Provides network isolation and home directory write protection",
          "(version 1)",
          "",
          "; Allow most operations by default (R needs many system calls)",
          "(allow default)",
          "",
          "; === Network Restrictions ===",
          "; Block external network access (but allow localhost for IPC)",
          "(deny network-outbound (remote ip))",
          "(allow network* (remote ip \"localhost:*\"))",
          "(allow network* (local ip \"localhost:*\"))",
          "",
          "; === Filesystem Write Restrictions ===",
          "; Deny writes to home directory (users' files)",
          sprintf("(deny file-write* (subpath \"%s\"))", path.expand("~")),
          "; But allow writes to temp directories even if in home",
          "(allow file-write* (subpath \"/tmp\"))",
          "(allow file-write* (subpath \"/private/tmp\"))",
          "(allow file-write* (subpath \"/var/tmp\"))",
          sprintf("(allow file-write* (regex #\"^%s/\\\\.Rtmp.*\"))", path.expand("~"))
        )
        profile_content <- paste(profile_content, collapse = "\n")

        writeLines(profile_content, profile_file)
        debug_log("Created temporary macOS sandbox profile: ", profile_file)
      }

      # Build sandbox-exec arguments
      sandbox_args <- c(
        "-f",
        profile_file,
        file.path(R.home("bin"), "Rscript"),
        worker_args
      )

      debug_log("Sandbox-exec args: ", paste(sandbox_args, collapse = " "))

      # Prepare environment for worker process
      worker_env <- Sys.getenv()
      worker_env[["R_LIBS_USER"]] <- paste(
        .libPaths(),
        collapse = .Platform$path.sep
      )

      # Start sandbox-exec process
      proc <- processx::process$new(
        command = "sandbox-exec",
        args = sandbox_args,
        stdout = "|",
        stderr = "|",
        cleanup = TRUE,
        cleanup_tree = TRUE,
        env = worker_env
      )

      private$.port <- port
      private$.process <- proc

      debug_success("macOS sandbox worker process started")

      list(
        process = proc,
        port = port,
        profile_file = profile_file
      )
    }
  ),
  private = list(
    .type = "macos_sandbox",
    .temp_profile = NULL,

    # Cleanup method to remove temporary profile
    finalize = function() {
      if (
        !is.null(private$.temp_profile) && file.exists(private$.temp_profile)
      ) {
        unlink(private$.temp_profile)
      }
    }
  )
)

#' Check macOS Sandbox Availability
#'
#' Check if macOS sandbox-exec is available and accessible on the system
#'
#' @return logical, TRUE if macOS sandbox-exec is available and on macOS
#' @export
is_macos_sandbox_available <- function() {
  # Check if running on macOS
  if (Sys.info()["sysname"] != "Darwin") {
    return(FALSE)
  }

  # Check if sandbox-exec command exists
  sandbox_path <- Sys.which("sandbox-exec")
  if (sandbox_path == "") {
    return(FALSE)
  }

  # Test if sandbox-exec is accessible (try with a simple test)
  tryCatch(
    {
      # Create a minimal test profile
      test_profile <- tempfile(fileext = ".sb")
      on.exit(unlink(test_profile), add = TRUE)

      writeLines(
        c(
          "(version 1)",
          "(allow default)"
        ),
        test_profile
      )

      result <- system2(
        "sandbox-exec",
        c("-f", test_profile, "echo", "test"),
        stdout = TRUE,
        stderr = TRUE
      )
      # If no error and got output "test", sandbox-exec is available
      return(length(result) > 0 && any(grepl("test", result, fixed = TRUE)))
    },
    error = function(e) {
      return(FALSE) # nolint
    }
  )
}

#' Check Firejail Availability
#'
#' Check if firejail is available and accessible on the system
#'
#' @return logical, TRUE if firejail is available and accessible
#' @export
is_firejail_available <- function() {
  # Check if firejail command exists
  firejail_path <- Sys.which("firejail")
  if (firejail_path == "") {
    return(FALSE)
  }

  # Test if firejail is accessible (try --version)
  tryCatch(
    {
      result <- system2(
        "firejail",
        c("--version"),
        stdout = TRUE,
        stderr = TRUE
      )
      # If no error and got output, firejail is available
      return(length(result) > 0 && !inherits(result, "try-error"))
    },
    error = function(e) {
      return(FALSE) # nolint
    }
  )
}

#' Create Worker Wrapper
#'
#' Factory function to create the appropriate worker wrapper based on options
#'
#' @return WorkerWrapper object (NativeWorkerWrapper, DockerWorkerWrapper, FirejailWorkerWrapper, or MacOSSandboxWorkerWrapper)
#' @keywords internal
create_worker_wrapper <- function() {
  # Get the worker type from the new unified option
  worker_type <- getOption("repljail.worker.type", default = "native")

  # For backward compatibility, check old boolean options if new option not set
  if (worker_type == "native" && is.null(getOption("repljail.worker.type"))) {
    # Check legacy options in priority order: macos_sandbox > firejail > docker > native
    if (isTRUE(getOption("repljail.use.macos.sandbox"))) {
      worker_type <- "macos-sandbox"
      warning(
        "Option 'repljail.use.macos.sandbox' is deprecated. ",
        "Please use options(repljail.worker.type = \"macos-sandbox\") instead.",
        call. = FALSE
      )
    } else if (isTRUE(getOption("repljail.use.firejail"))) {
      worker_type <- "firejail"
      warning(
        "Option 'repljail.use.firejail' is deprecated. ",
        "Please use options(repljail.worker.type = \"firejail\") instead.",
        call. = FALSE
      )
    } else if (isTRUE(getOption("repljail.use.docker"))) {
      worker_type <- "docker"
      warning(
        "Option 'repljail.use.docker' is deprecated. ",
        "Please use options(repljail.worker.type = \"docker\") instead.",
        call. = FALSE
      )
    }
  }

  # Validate and create the appropriate wrapper
  wrapper <- switch(
    worker_type,
    "native" = {
      debug_log("Creating native worker wrapper")
      NativeWorkerWrapper$new()
    },
    "docker" = {
      debug_log("Creating Docker worker wrapper")
      DockerWorkerWrapper$new()
    },
    "firejail" = {
      debug_log("Creating firejail worker wrapper")
      FirejailWorkerWrapper$new()
    },
    "macos-sandbox" = {
      debug_log("Creating macOS sandbox worker wrapper")
      MacOSSandboxWorkerWrapper$new()
    },
    {
      # Invalid worker type
      stop(
        "Invalid worker type: '",
        worker_type,
        "'. ",
        "Valid options are: 'native', 'docker', 'firejail', 'macos-sandbox'",
        call. = FALSE
      )
    }
  )

  wrapper
}
