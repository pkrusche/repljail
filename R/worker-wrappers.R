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
    #' @param port integer, port number for worker to listen on
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    start_process = function(port, worker_script, worker_args, timeout) {
      debug_log("Starting native worker process on port ", port)

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

      private$.port <- port
      private$.process <- proc

      debug_success("Native worker process started")

      list(
        process = proc,
        port = port
      )
    }
  ),
  private = list(
    .type = "native"
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

      # Build base Docker arguments
      docker_args <- c(
        "run",
        "--name",
        container_name,
        "--rm",
        "--user",
        "replr",
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

      debug_log("Starting Docker container with args: ", paste(docker_args, collapse = " "))

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
          "replr-gateway-",
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
    #' @param port integer, port number for worker to listen on
    #' @param worker_script character, path to worker.R script
    #' @param worker_args character vector, arguments for worker
    #' @param timeout numeric, startup timeout in seconds
    start_process = function(port, worker_script, worker_args, timeout) {
      debug_log("Starting firejail worker process on port ", port)

      # Check firejail availability
      if (!is_firejail_available()) {
        stop("Firejail is not available. Cannot start worker in firejail sandbox.")
      }

      # Get custom profile if specified
      custom_profile <- getOption("replr.worker.firejail.profile", default = NULL)

      # Build firejail arguments
      firejail_args <- c("--quiet")

      if (!is.null(custom_profile) && file.exists(custom_profile)) {
        # Use custom profile
        debug_log("Using custom firejail profile: ", custom_profile)
        firejail_args <- c(firejail_args, paste0("--profile=", custom_profile))
      } else {
        # Use default security settings
        # Check if networking features are available
        networking_available <- is_firejail_networking_available()

        if (networking_available) {
          # Network isolation - keep loopback for host communication but block external access
          firejail_args <- c(firejail_args, "--net=lo")
          debug_log("Using firejail with network isolation (--net=lo)")
        } else {
          # Network isolation not available - log warning
          warning(
            "Firejail networking features are disabled in system configuration. ",
            "Running without network isolation. ",
            "To enable network isolation, set 'network yes' in /etc/firejail/firejail.config",
            call. = FALSE,
            immediate. = TRUE
          )
          debug_log("Firejail networking disabled - running without network isolation")
        }

        # Filesystem restrictions - only allow writing to /tmp
        firejail_args <- c(firejail_args, "--private-tmp")

        # Additional security options
        firejail_args <- c(
          firejail_args,
          "--caps.drop=all",       # Drop all capabilities
          "--seccomp",              # Enable seccomp filtering
          "--nonewprivs",           # Prevent privilege escalation
          "--noroot",               # Run as regular user
          "--nosound",              # Disable sound
          "--novideo",              # Disable video
          "--no3d",                 # Disable 3D acceleration
          "--nodvd",                # Disable DVD
          "--notv"                  # Disable TV
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

      private$.port <- port
      private$.process <- proc

      debug_success("Firejail worker process started")

      list(
        process = proc,
        port = port
      )
    }
  ),
  private = list(
    .type = "firejail"
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
        stop("macOS sandbox-exec is not available. Cannot start worker in macOS sandbox.")
      }

      # Get custom profile if specified
      custom_profile <- getOption("replr.worker.macos.sandbox.profile", default = NULL)

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
        # Note: macOS sandbox-exec has complex, undocumented restrictions
        # We use a permissive profile that blocks external network only
        profile_content <- paste(
          "; macOS Sandbox Profile for replr worker",
          "; Allows most operations but blocks external network access",
          "(version 1)",
          "",
          "; Start with default allow for most operations",
          "(allow default)",
          "",
          "; Block network access except to localhost",
          "; This provides network isolation while keeping R functional",
          "(deny network-outbound (remote ip))",
          "(allow network* (remote tcp \"localhost:*\"))",
          "(allow network* (local ip \"localhost:*\"))",
          sep = "\n"
        )

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
      if (!is.null(private$.temp_profile) && file.exists(private$.temp_profile)) {
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

#' Check if Firejail Networking is Available
#'
#' Check if firejail networking features are enabled in the system configuration
#'
#' @return logical, TRUE if networking features are available
#' @keywords internal
is_firejail_networking_available <- function() {
  if (!is_firejail_available()) {
    return(FALSE)
  }

  # Try to run a simple command with --net=lo
  tryCatch(
    {
      result <- suppressWarnings(
        system2(
          "firejail",
          c("--net=lo", "--", "echo", "test"),
          stdout = TRUE,
          stderr = TRUE
        )
      )

      # Check if we got an error about networking being disabled
      if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
        # Check for the specific networking disabled error
        if (any(grepl("networking feature is disabled", result, fixed = TRUE))) {
          return(FALSE)
        }
      }

      # If we got here, networking is available
      return(TRUE)
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
  worker_type <- getOption("replr.worker.type", default = "native")

  # For backward compatibility, check old boolean options if new option not set
  if (worker_type == "native" && is.null(getOption("replr.worker.type"))) {
    # Check legacy options in priority order: macos_sandbox > firejail > docker > native
    if (isTRUE(getOption("replr.use.macos.sandbox"))) {
      worker_type <- "macos-sandbox"
      warning(
        "Option 'replr.use.macos.sandbox' is deprecated. ",
        "Please use options(replr.worker.type = \"macos-sandbox\") instead.",
        call. = FALSE
      )
    } else if (isTRUE(getOption("replr.use.firejail"))) {
      worker_type <- "firejail"
      warning(
        "Option 'replr.use.firejail' is deprecated. ",
        "Please use options(replr.worker.type = \"firejail\") instead.",
        call. = FALSE
      )
    } else if (isTRUE(getOption("replr.use.docker"))) {
      worker_type <- "docker"
      warning(
        "Option 'replr.use.docker' is deprecated. ",
        "Please use options(replr.worker.type = \"docker\") instead.",
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
        "Invalid worker type: '", worker_type, "'. ",
        "Valid options are: 'native', 'docker', 'firejail', 'macos-sandbox'",
        call. = FALSE
      )
    }
  )

  wrapper
}
