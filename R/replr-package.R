#' replr: Isolated REPL functionality for R
#'
#' Provides isolated REPL functionality for R, allowing users to execute R code
#' in a separate environment using worker processes for security and stability.
#'
#' @section Main Classes:
#' \itemize{
#'   \item \code{RREPLSession} - Main class for managing isolated R sessions
#' }
#'
#' @section Key Features:
#' \itemize{
#'   \item Process isolation for secure code execution
#'   \item Robust inter-process communication via nanonext
#'   \item Rich output capture including plots and warnings
#'   \item Automatic error recovery and process management
#'   \item Configurable timeouts and resource limits
#' }
#'
#' @name replr
#' @importFrom nanonext socket
#' @importFrom processx process
#' @importFrom R6 R6Class
#' @importFrom uuid UUIDgenerate
#' @importFrom evaluate evaluate
#' @importFrom mirai mirai
NULL
