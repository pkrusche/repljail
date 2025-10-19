# End-to-end tests for the complete worker lifecycle
here::i_am("tests/testthat/test-end-to-end.R")

test_that("Complete worker lifecycle works", {
  # Create session
  session <- replr::RREPLSession$new(timeout = 10)

  # Verify session started successfully
  expect_true(session$is_alive())
  session_info <- session$get_info()
  expect_true(!is.na(session_info$port))
  expect_true(!is.na(session_info$pid))
  expect_true(!is.na(session_info$started_at))

  # Test basic arithmetic
  result1 <- session$execute("2 + 2", timeout = 5)
  expect_true(is.list(result1))
  expect_equal(result1$status, "success")
  expect_true(any(grepl("4", result1$result$output)))

  # Test assignment and retrieval
  result2 <- session$execute("x <- 42", timeout = 5)
  expect_equal(result2$status, "success")

  result3 <- session$execute("x", timeout = 5)
  expect_equal(result3$status, "success")
  expect_true(any(grepl("42", result3$result$output)))

  # Stop session
  stopped <- session$stop(timeout = 5)
  expect_true(stopped)
  expect_false(session$is_alive())
})

test_that("Worker handles R code execution correctly", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test simple expression
      result1 <- session$execute("1 + 1", timeout = 5)
      expect_equal(result1$status, "success")
      expect_true(length(result1$result$output) > 0)

      # Test function call
      result2 <- session$execute("sqrt(16)", timeout = 5)
      expect_equal(result2$status, "success")
      expect_true(any(grepl("4", result2$result$output)))

      # Test variable assignment and use
      result3 <- session$execute("my_var <- c(1, 2, 3)", timeout = 5)
      expect_equal(result3$status, "success")

      result4 <- session$execute("sum(my_var)", timeout = 5)
      expect_equal(result4$status, "success")
      expect_true(any(grepl("6", result4$result$output)))

      # Test data frame creation
      result5 <- session$execute(
        "data.frame(x = 1:3, y = 4:6)",
        timeout = 5
      )
      expect_equal(result5$status, "success")
      expect_true(any(grepl("x", result5$result$output)))
      expect_true(any(grepl("y", result5$result$output)))
    },
    finally = {
      session$stop(timeout = 5)
    }
  )
})

test_that("Worker handles errors gracefully", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test syntax error
      result1 <- session$execute("1 +", timeout = 5)
      expect_equal(result1$status, "error")
      expect_true(length(result1$result$errors) > 0)

      # Test runtime error
      result2 <- session$execute("stop('test error')", timeout = 5)
      expect_equal(result2$status, "error")
      expect_true(any(grepl("test error", result2$result$errors)))

      # Test that worker is still alive after errors
      expect_true(session$is_alive())

      # Test that worker can still execute after error
      result3 <- session$execute("2 * 3", timeout = 5)
      expect_equal(result3$status, "success")
      expect_true(any(grepl("6", result3$result$output)))
    },
    finally = {
      session$stop(timeout = 5)
    }
  )
})

test_that("Worker handles warnings correctly", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test warning generation
      result1 <- session$execute(
        "warning('test warning')",
        timeout = 5
      )
      expect_equal(result1$status, "success")
      expect_true(length(result1$result$warnings) > 0)
      expect_true(any(grepl("test warning", result1$result$warnings)))

      # Test that worker continues after warning
      result2 <- session$execute("7 + 8", timeout = 5)
      expect_equal(result2$status, "success")
      expect_true(any(grepl("15", result2$result$output)))
    },
    finally = {
      session$stop(timeout = 5)
    }
  )
})

test_that("Multiple workers can run simultaneously", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  session1 <- RREPLSession$new(timeout = 10)
  session2 <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Verify both workers started
      expect_true(session1$is_alive())
      expect_true(session2$is_alive())
      expect_false(session1$port == session2$port) # Different ports

      # Test independent execution
      result1 <- session1$execute("x1 <- 100", timeout = 5)
      result2 <- session2$execute("x2 <- 200", timeout = 5)

      expect_equal(result1$status, "success")
      expect_equal(result2$status, "success")

      # Verify isolation - session1 shouldn't see x2
      result3 <- session1$execute("exists('x2')", timeout = 5)
      expect_equal(result3$status, "success")
      expect_true(any(grepl("FALSE", result3$result$output)))

      # Verify isolation - session2 shouldn't see x1
      result4 <- session2$execute("exists('x1')", timeout = 5)
      expect_equal(result4$status, "success")
      expect_true(any(grepl("FALSE", result4$result$output)))
    },
    finally = {
      session1$stop(timeout = 5)
      session2$stop(timeout = 5)
    }
  )
})

test_that("Worker startup handles port conflicts", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  # Start first session on specific port
  port1 <- replr:::get_available_port()
  session1 <- RREPLSession$new(port = port1, timeout = 10)

  tryCatch(
    {
      expect_equal(session1$port, port1)
      expect_true(session1$is_alive())

      # Start second session without specifying port (should find different port)
      session2 <- RREPLSession$new(timeout = 10)

      tryCatch(
        {
          expect_true(session2$is_alive())
          expect_false(session1$port == session2$port)
        },
        finally = {
          session2$stop(timeout = 5)
        }
      )
    },
    finally = {
      session1$stop(timeout = 5)
    }
  )
})
