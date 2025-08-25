#' Check Package Dependencies
#'
#' Verify that all required packages are available and compatible
#'
#' @return logical indicating if all dependencies are satisfied
#' @export
check_dependencies <- function() {
  required_packages <- c("nanonext", "mirai", "processx", "evaluate", "R6", "uuid")
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
      "Missing required packages: ", paste(missing_required, collapse = ", "),
      "\nInstall with: install.packages(c(",
      paste0('"', missing_required, '"', collapse = ", "), "))"
    )
  }

  if (length(missing_suggested) > 0) {
    message("Missing suggested packages: ", paste(missing_suggested, collapse = ", "))
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
        sock <- nanonext::socket("rep", listen = paste0("tcp://127.0.0.1:", port))
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

#' Initialize Package
#'
#' Run all initialization checks when package is loaded
#'
#' @param libname character, library name
#' @param pkgname character, package name
#' @return invisible(TRUE) if successful
#' @noRd
.onLoad <- function(libname, pkgname) {
  # Check dependencies silently during package load
  tryCatch(
    {
      check_dependencies()
      check_process_requirements()
    },
    error = function(e) {
      packageStartupMessage("replr: ", e$message)
    }
  )

  invisible(TRUE)
}
