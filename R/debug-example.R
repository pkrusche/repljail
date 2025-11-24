#' Enable Debug Logging
#'
#' Convenience function to enable debug logging for the repljail package
#'
#' @param enable logical, TRUE to enable debug logging, FALSE to disable
#' @export
enable_debug <- function(enable = TRUE) {
  options(repljail.debug = enable)

  if (enable) {
    cli::cli_alert_success("Debug logging enabled for repljail package")
    cli::cli_alert_info("Use options(repljail.debug = FALSE) to disable")
  } else {
    cli::cli_alert_info("Debug logging disabled for repljail package")
  }

  invisible(enable)
}

#' Show Debug Status
#'
#' Show current debug logging status
#'
#' @export
debug_status <- function() {
  status <- getOption("repljail.debug", default = FALSE)

  if (status) {
    cli::cli_alert_success("Debug logging is currently ENABLED")
  } else {
    cli::cli_alert_info("Debug logging is currently DISABLED")
    cli::cli_alert_info("Use enable_debug(TRUE) to enable debug logging")
  }

  invisible(status)
}
