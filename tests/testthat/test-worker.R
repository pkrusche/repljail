# Basic tests for worker functionality
# These tests document the core functionality even if nanonext has connectivity issues
here::i_am("tests/testthat/test-worker.R")

test_that("Worker script exists and is executable", {
  worker_path <- replr:::get_worker_script_path()
  expect_false(worker_path == "")
  expect_true(file.exists(worker_path))
  expect_true(file.access(worker_path, mode = 1) == 0)
})

test_that("Worker script validates command line arguments", {
  # Test with no arguments
  worker_path <- replr:::get_worker_script_path()
  result1 <- suppressWarnings(system2(
    "Rscript",
    c(worker_path),
    stdout = TRUE,
    stderr = TRUE,
    timeout = 10
  ))
  expect_true(attr(result1, "status") == 1)

  # Test with invalid port number (out of range)
  # Note: Strings are now accepted as IPC socket paths, so we need to test
  # an actual invalid port number (out of valid range 1-65535)
  result2 <- suppressWarnings(system2(
    "Rscript",
    c(worker_path, "999999"),
    stdout = TRUE,
    stderr = TRUE,
    timeout = 10
  ))
  expect_true(attr(result2, "status") == 1)

  # Test with too many arguments
  result3 <- suppressWarnings(system2(
    "Rscript",
    c(worker_path, "8888", "--debug", "extra", "extra", "extra"),
    stdout = TRUE,
    stderr = TRUE,
    timeout = 10
  ))
  expect_true(attr(result3, "status") == 1)
})

test_that("Worker can be started via processx with IPC socket", {
  skip_on_check()
  library(processx)

  # Test that processx can start the worker script with IPC socket
  worker_path <- replr:::get_worker_script_path()
  socket_path <- tempfile(pattern = "test_worker_socket_")
  on.exit(unlink(socket_path), add = TRUE)

  proc <- process$new(
    file.path(R.home("bin"), "Rscript"),
    c(worker_path, socket_path),
    stdout = "|",
    stderr = "|"
  )
  Sys.sleep(1)
  expect_true(proc$is_alive())

  # Check worker output
  stderr_output <- proc$read_error_lines()
  expect_true(any(grepl("Worker starting", stderr_output)))
  expect_true(any(grepl("Worker ready", stderr_output)))
  expect_true(any(grepl("ipc://", stderr_output)))

  proc$kill()
  Sys.sleep(0.5)
  expect_false(proc$is_alive())
})

test_that("Worker accepts debug flag with IPC socket", {
  # inside check this fails because we can't capture stderr
  skip_on_check()
  library(processx)

  worker_path <- replr:::get_worker_script_path()
  socket_path <- tempfile(pattern = "test_worker_socket_debug_")
  on.exit(unlink(socket_path), add = TRUE)

  # Test worker with debug flag
  proc <- process$new(
    file.path(R.home("bin"), "Rscript"),
    c(worker_path, socket_path, "--debug"),
    stdout = "|",
    stderr = "|"
  )
  Sys.sleep(1)
  expect_true(proc$is_alive())

  # Check that debug mode message appears in stderr
  stderr_output <- proc$read_error_lines()
  expect_true(any(grepl("Debug mode enabled", stderr_output)))
  expect_true(any(grepl("ipc://", stderr_output)))

  proc$kill()
  Sys.sleep(0.5)
  expect_false(proc$is_alive())
})

test_that("Evaluate integration works", {
  library(evaluate)

  # Test simple expression
  result1 <- evaluate("2 + 2")
  expect_true(length(result1) > 0)
  expect_true(any(sapply(result1, function(x) grepl("4", x))))

  # Test expression with error
  result2 <- evaluate("stop('test error')")
  expect_true(any(sapply(result2, function(x) inherits(x, "error"))))
})
