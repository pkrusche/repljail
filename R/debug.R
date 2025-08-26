#' Debug Logging Utilities
#'
#' Configurable debug logging using the cli package and the replr.debug option

#' Check if debug logging is enabled
#'
#' @return logical, TRUE if debug logging is enabled
is_debug_enabled <- function() {
  getOption("replr.debug", default = FALSE)
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

#' Worker debug log message
#'
#' Special debug logging for worker processes that writes to stderr
#' Uses cli formatting but outputs to stderr for worker visibility
#'
#' @param ... arguments for the debug message
worker_debug_log <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_dim(cli::col_blue("\u2139")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

#' Worker debug success message
#'
#' @param ... arguments for the success message
worker_debug_success <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_bold(cli::col_green("\u2714")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

#' Worker debug warning message
#'
#' @param ... arguments for the warning message
worker_debug_warn <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_bold(cli::col_yellow("\u26a0")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}

#' Worker debug error message
#'
#' @param ... arguments for the error message
worker_debug_error <- function(...) {
  if (is_debug_enabled()) {
    msg <- paste0("[", Sys.time(), "] ", ...)
    cat(
      cli::style_bold(cli::col_red("\u2716")),
      " ",
      msg,
      "\n",
      file = stderr(),
      sep = ""
    )
  }
}
