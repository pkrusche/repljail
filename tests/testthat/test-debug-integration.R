# Test debug logging integration
here::i_am("tests/testthat/test-debug-integration.R")

test_that("Debug logging works end-to-end", {
  skip_on_check()
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  # Test without debug logging first
  options(repljail.debug = FALSE)
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Worker should start successfully even without debug
      expect_true(session$is_alive())

      # Basic execution should work
      result <- session$execute("1 + 1", timeout = 5)
      expect_equal(result$status, "success")
    },
    finally = {
      session$stop(timeout = 5)
    }
  )
})

test_that("Debug logging can be enabled and disabled", {
  # Test enabling debug
  enable_debug(TRUE)
  expect_true(getOption("repljail.debug"))

  # Test disabling debug
  enable_debug(FALSE)
  expect_false(getOption("repljail.debug"))

  # Test debug status reporting
  options(repljail.debug = TRUE)
  status <- debug_status()
  expect_true(status)

  options(repljail.debug = FALSE)
  status <- debug_status()
  expect_false(status)
})

test_that("Worker inherits debug setting from parent", {
  skip_on_check()

  # Enable debug logging
  options(repljail.debug = TRUE)

  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      expect_true(session$is_alive())

      # Read stderr to check for debug messages
      Sys.sleep(1) # Give time for debug messages to appear
      debug_logs <- session$get_debug_logs()

      # Should see debug mode enabled message
      expect_true(any(grepl("Debug mode enabled", debug_logs)))
    },
    finally = {
      session$stop(timeout = 5)
      options(repljail.debug = FALSE) # Clean up
    }
  )
})
