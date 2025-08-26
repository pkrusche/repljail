# Test debug logging integration
here::i_am("tests/testthat/test-debug-integration.R")

test_that("Debug logging works end-to-end", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  # Test without debug logging first
  options(replr.debug = FALSE)
  worker_info <- start_worker(timeout = 10)

  tryCatch(
    {
      # Worker should start successfully even without debug
      expect_true(worker_info$process$is_alive())

      # Basic execution should work
      result <- send_command(worker_info, "1 + 1", timeout = 5)
      expect_equal(result$status, "success")
    },
    finally = {
      stop_worker(worker_info, timeout = 5)
    }
  )
})

test_that("Debug logging can be enabled and disabled", {
  # Test enabling debug
  enable_debug(TRUE)
  expect_true(getOption("replr.debug"))

  # Test disabling debug
  enable_debug(FALSE)
  expect_false(getOption("replr.debug"))

  # Test debug status reporting
  options(replr.debug = TRUE)
  status <- debug_status()
  expect_true(status)

  options(replr.debug = FALSE)
  status <- debug_status()
  expect_false(status)
})

test_that("Worker inherits debug setting from parent", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  # Enable debug logging
  options(replr.debug = TRUE)

  worker_info <- start_worker(timeout = 10)

  tryCatch(
    {
      expect_true(worker_info$process$is_alive())

      # Read stderr to check for debug messages
      Sys.sleep(1) # Give time for debug messages to appear
      stderr_lines <- worker_info$process$read_error_lines()

      # Should see debug mode enabled message
      expect_true(any(grepl("Debug mode enabled", stderr_lines)))
    },
    finally = {
      stop_worker(worker_info, timeout = 5)
      options(replr.debug = FALSE) # Clean up
    }
  )
})
