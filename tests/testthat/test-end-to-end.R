# End-to-end tests for the complete worker lifecycle
here::i_am("tests/testthat/test-end-to-end.R")

test_that("Complete worker lifecycle works", {
  skip_on_check()

  # Create session
  session <- repljail::RREPLSession$new(timeout = 10)

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
  skip_on_check()
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
  skip_on_check()
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
  skip_on_check()
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

test_that("Multiple workers can run simultaneously with different IPC sockets", {
  skip_on_check()
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  session1 <- RREPLSession$new(timeout = 10)
  session2 <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Verify both workers started
      expect_true(session1$is_alive())
      expect_true(session2$is_alive())

      # For IPC mode (native/firejail/macos), check socket paths are different
      # For TCP mode (docker), check ports are different
      info1 <- session1$get_info()
      info2 <- session2$get_info()

      if (!is.null(info1$socket_path) && !is.null(info2$socket_path)) {
        # IPC mode - verify different socket paths
        expect_false(info1$socket_path == info2$socket_path)
      } else {
        # TCP mode - verify different ports
        expect_false(session1$port == session2$port)
      }

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
