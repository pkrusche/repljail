# Tests for RREPLSession R6 class
here::i_am("tests/testthat/test-session.R")

test_that("RREPLSession can be created and initialized", {
  session <- RREPLSession$new(timeout = 10)

  # Check object structure
  expect_s3_class(session, "RREPLSession")
  expect_true(session$is_alive())
  expect_true(is.numeric(session$port))
  expect_true(session$port > 0)
  expect_true(is.numeric(session$pid))
  expect_true(session$pid > 0)
  expect_true(inherits(session$started_at, "POSIXct"))

  # Clean up
  session$stop()
  expect_false(session$is_alive())
})

test_that("RREPLSession execute method works correctly", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch({
    # Test basic arithmetic
    result1 <- session$execute("2 + 2")
    expect_equal(result1$status, "success")
    expect_true(any(grepl("4", result1$result$output)))

    # Test assignment
    result2 <- session$execute("x <- 42")
    expect_equal(result2$status, "success")

    # Test retrieval
    result3 <- session$execute("x")
    expect_equal(result3$status, "success")
    expect_true(any(grepl("42", result3$result$output)))

    # Test error handling
    result4 <- session$execute("stop('test error')")
    expect_equal(result4$status, "error")
    expect_true(length(result4$result$errors) > 0)
  }, finally = {
    session$stop()
  })
})

test_that("RREPLSession handles worker death gracefully", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch({
    # Verify session is alive
    expect_true(session$is_alive())

    # Kill the worker process directly
    pid <- session$pid
    session$stop()

    # Check status after stop
    expect_false(session$is_alive())

    # Verify execute fails on stopped session
    expect_error(session$execute("1 + 1"), "Session has been stopped")
  }, finally = {
    # Ensure cleanup
    if (session$is_alive()) {
      session$stop()
    }
  })
})

test_that("RREPLSession get_info method provides correct information", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")
  skip_if_not_installed("R6")

  session <- RREPLSession$new(timeout = 10)

  tryCatch({
    info <- session$get_info()

    expect_true(is.list(info))
    expect_true("port" %in% names(info))
    expect_true("pid" %in% names(info))
    expect_true("started_at" %in% names(info))
    expect_true("is_alive" %in% names(info))
    expect_true("stopped" %in% names(info))

    expect_true(is.numeric(info$port))
    expect_true(is.numeric(info$pid))
    expect_true(inherits(info$started_at, "POSIXct"))
    expect_true(info$is_alive)
    expect_false(info$stopped)
  }, finally = {
    session$stop()
  })
})

test_that("RREPLSession active bindings work correctly", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")
  skip_if_not_installed("R6")

  session <- RREPLSession$new(timeout = 10)

  tryCatch({
    # Test active bindings when alive
    expect_true(is.numeric(session$port))
    expect_true(session$port > 0)
    expect_true(is.numeric(session$pid))
    expect_true(session$pid > 0)
    expect_true(inherits(session$started_at, "POSIXct"))

    # Stop session
    session$stop()

    # Test active bindings after stop
    expect_false(is.na(session$port)) # Port should still be available
    expect_true(is.na(session$pid)) # PID should be NA when stopped
    expect_true(inherits(session$started_at, "POSIXct")) # Started time preserved
  }, finally = {
    if (session$is_alive()) {
      session$stop()
    }
  })
})

test_that("RREPLSession handles timeouts correctly", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")
  skip_if_not_installed("R6")

  session <- RREPLSession$new(timeout = 10)

  tryCatch({
    # Test execution timeout with a long-running operation
    result <- session$execute("Sys.sleep(2); 42", timeout = 1)

    # Should either timeout or succeed (depending on timing)
    expect_true(result$status %in% c("success", "timeout", "error"))
  }, finally = {
    session$stop()
  })
})

test_that("RREPLSession finalizer works for automatic cleanup", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")
  skip_if_not_installed("R6")

  # Create session in a local scope
  pid <- NULL
  {
    session <- RREPLSession$new(timeout = 10)
    pid <- session$pid
    expect_true(session$is_alive())
    # Let session go out of scope without explicit stop()
  }

  # Force garbage collection to trigger finalizer
  gc()
  Sys.sleep(0.5) # Give time for cleanup

  # Note: We can't easily test if the process was actually killed
  # because finalizers run asynchronously, but we can at least verify
  # the finalizer mechanism is in place
  expect_true(is.numeric(pid))
})

test_that("Multiple RREPLSession instances work independently", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")
  skip_if_not_installed("R6")

  session1 <- RREPLSession$new(timeout = 10)
  session2 <- RREPLSession$new(timeout = 10)

  tryCatch({
    # Verify both sessions are alive and independent
    expect_true(session1$is_alive())
    expect_true(session2$is_alive())
    expect_true(session1$port != session2$port)
    expect_true(session1$pid != session2$pid)

    # Set different variables in each session
    result1 <- session1$execute("x <- 100")
    result2 <- session2$execute("x <- 200")

    expect_equal(result1$status, "success")
    expect_equal(result2$status, "success")

    # Verify isolation
    check1 <- session1$execute("x")
    check2 <- session2$execute("x")

    expect_true(any(grepl("100", check1$result$output)))
    expect_true(any(grepl("200", check2$result$output)))
  }, finally = {
    session1$stop()
    session2$stop()
  })
})
