#' Debug Logging Utilities
#'
#' Configurable debug logging using the cli package and the repljail.debug option

#' Check if debug logging is enabled
#'
#' @return logical, TRUE if debug logging is enabled
is_debug_enabled <- function() {
  getOption("repljail.debug", default = FALSE)
}

#' Debug log message
#'
#' Log a debug message if debug mode is enabled
#'
#' @param ... arguments passed to cli_alert_info
#' @param .envir environment for cli interpolation
debug_log <- function(..., .envir = parent.frame()) {
  if (is_debug_enabled()) {
    cli::cli_alert_info(..., .envir = .envir)
  }
}

#' Debug log success message
#'
#' Log a debug success message if debug mode is enabled
#'
#' @param ... arguments passed to cli_alert_success
#' @param .envir environment for cli interpolation
debug_success <- function(..., .envir = parent.frame()) {
  if (is_debug_enabled()) {
    cli::cli_alert_success(..., .envir = .envir)
  }
}

#' Debug log warning message
#'
#' Log a debug warning message if debug mode is enabled
#'
#' @param ... arguments passed to cli_alert_warning
#' @param .envir environment for cli interpolation
debug_warn <- function(..., .envir = parent.frame()) {
  if (is_debug_enabled()) {
    cli::cli_alert_warning(..., .envir = .envir)
  }
}

#' Debug log error message
#'
#' Log a debug error message if debug mode is enabled
#'
#' @param ... arguments passed to cli_alert_danger
#' @param .envir environment for cli interpolation
debug_error <- function(..., .envir = parent.frame()) {
  if (is_debug_enabled()) {
    cli::cli_alert_danger(..., .envir = .envir)
  }
}
