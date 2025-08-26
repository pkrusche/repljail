# Basic tests for worker functionality
# These tests document the core functionality even if nanonext has connectivity issues

test_that("Worker script exists and is executable", {
  expect_true(file.exists("inst/worker.R"))
  expect_true(file.access("inst/worker.R", mode = 1) == 0)
})

test_that("Worker script validates command line arguments", {
  # Test with no arguments
  result1 <- system2("Rscript", c("inst/worker.R"), stdout = TRUE, stderr = TRUE)
  expect_true(attr(result1, "status") == 1)
  
  # Test with invalid port
  result2 <- system2("Rscript", c("inst/worker.R", "invalid"), stdout = TRUE, stderr = TRUE)
  expect_true(attr(result2, "status") == 1)
})

test_that("Utility functions are defined", {
  source("R/utils.R")
  expect_true(exists("start_worker"))
  expect_true(exists("send_command"))
  expect_true(exists("stop_worker"))
})

test_that("Communication functions are defined", {
  source("R/communication.R")
  expect_true(exists("create_req_socket"))
  expect_true(exists("send_request"))
  expect_true(exists("close_socket"))
})

test_that("Worker can be started via processx", {
  source("R/utils.R")
  library(processx)
  
  # Test that processx can start the worker script
  proc <- process$new("Rscript", c("inst/worker.R", "8888"), 
                      stdout = "|", stderr = "|")
  Sys.sleep(1)
  expect_true(proc$is_alive())
  
  # Check worker output
  stderr_output <- proc$read_error_lines()
  expect_true(any(grepl("Worker starting", stderr_output)))
  expect_true(any(grepl("Worker ready", stderr_output)))
  
  proc$kill()
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