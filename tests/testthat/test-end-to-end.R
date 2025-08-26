# End-to-end tests for the complete worker lifecycle
here::i_am("tests/testthat/test-end-to-end.R")

test_that("Complete worker lifecycle works", {
  # Start worker
  worker_info <- replr::start_worker(timeout = 10)

  # Verify worker started successfully
  expect_true(is.list(worker_info))
  expect_true("process" %in% names(worker_info))
  expect_true("port" %in% names(worker_info))
  expect_true("started_at" %in% names(worker_info))
  expect_true(worker_info$process$is_alive())

  # Test basic arithmetic
  result1 <- send_command(worker_info, "2 + 2", timeout = 5)
  expect_true(is.list(result1))
  expect_equal(result1$status, "success")
  expect_true(any(grepl("4", result1$result$output)))

  # Test assignment and retrieval
  result2 <- send_command(worker_info, "x <- 42", timeout = 5)
  expect_equal(result2$status, "success")

  result3 <- send_command(worker_info, "x", timeout = 5)
  expect_equal(result3$status, "success")
  expect_true(any(grepl("42", result3$result$output)))

  # Stop worker
  stopped <- stop_worker(worker_info, timeout = 5)
  expect_true(stopped)
  expect_false(worker_info$process$is_alive())
})

test_that("Worker handles R code execution correctly", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  worker_info <- start_worker(timeout = 10)

  tryCatch(
    {
      # Test simple expression
      result1 <- send_command(worker_info, "1 + 1", timeout = 5)
      expect_equal(result1$status, "success")
      expect_true(length(result1$result$output) > 0)

      # Test function call
      result2 <- send_command(worker_info, "sqrt(16)", timeout = 5)
      expect_equal(result2$status, "success")
      expect_true(any(grepl("4", result2$result$output)))

      # Test variable assignment and use
      result3 <- send_command(worker_info, "my_var <- c(1, 2, 3)", timeout = 5)
      expect_equal(result3$status, "success")

      result4 <- send_command(worker_info, "sum(my_var)", timeout = 5)
      expect_equal(result4$status, "success")
      expect_true(any(grepl("6", result4$result$output)))

      # Test data frame creation
      result5 <- send_command(
        worker_info,
        "data.frame(x = 1:3, y = 4:6)",
        timeout = 5
      )
      expect_equal(result5$status, "success")
      expect_true(any(grepl("x", result5$result$output)))
      expect_true(any(grepl("y", result5$result$output)))
    },
    finally = {
      stop_worker(worker_info, timeout = 5)
    }
  )
})

test_that("Worker handles errors gracefully", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  worker_info <- start_worker(timeout = 10)

  tryCatch(
    {
      # Test syntax error
      result1 <- send_command(worker_info, "1 +", timeout = 5)
      expect_equal(result1$status, "error")
      expect_true(length(result1$result$errors) > 0)

      # Test runtime error
      result2 <- send_command(worker_info, "stop('test error')", timeout = 5)
      expect_equal(result2$status, "error")
      expect_true(any(grepl("test error", result2$result$errors)))

      # Test that worker is still alive after errors
      expect_true(worker_info$process$is_alive())

      # Test that worker can still execute after error
      result3 <- send_command(worker_info, "2 * 3", timeout = 5)
      expect_equal(result3$status, "success")
      expect_true(any(grepl("6", result3$result$output)))
    },
    finally = {
      stop_worker(worker_info, timeout = 5)
    }
  )
})

test_that("Worker handles warnings correctly", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  worker_info <- start_worker(timeout = 10)

  tryCatch(
    {
      # Test warning generation
      result1 <- send_command(
        worker_info,
        "warning('test warning')",
        timeout = 5
      )
      expect_equal(result1$status, "success")
      expect_true(length(result1$result$warnings) > 0)
      expect_true(any(grepl("test warning", result1$result$warnings)))

      # Test that worker continues after warning
      result2 <- send_command(worker_info, "7 + 8", timeout = 5)
      expect_equal(result2$status, "success")
      expect_true(any(grepl("15", result2$result$output)))
    },
    finally = {
      stop_worker(worker_info, timeout = 5)
    }
  )
})

test_that("Multiple workers can run simultaneously", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  worker1 <- start_worker(timeout = 10)
  worker2 <- start_worker(timeout = 10)

  tryCatch(
    {
      # Verify both workers started
      expect_true(worker1$process$is_alive())
      expect_true(worker2$process$is_alive())
      expect_false(worker1$port == worker2$port) # Different ports

      # Test independent execution
      result1 <- send_command(worker1, "x1 <- 100", timeout = 5)
      result2 <- send_command(worker2, "x2 <- 200", timeout = 5)

      expect_equal(result1$status, "success")
      expect_equal(result2$status, "success")

      # Verify isolation - worker1 shouldn't see x2
      result3 <- send_command(worker1, "exists('x2')", timeout = 5)
      expect_equal(result3$status, "success")
      expect_true(any(grepl("FALSE", result3$result$output)))

      # Verify isolation - worker2 shouldn't see x1
      result4 <- send_command(worker2, "exists('x1')", timeout = 5)
      expect_equal(result4$status, "success")
      expect_true(any(grepl("FALSE", result4$result$output)))
    },
    finally = {
      stop_worker(worker1, timeout = 5)
      stop_worker(worker2, timeout = 5)
    }
  )
})

test_that("Worker startup handles port conflicts", {
  skip_if_not_installed("nanonext")
  skip_if_not_installed("processx")

  # Start first worker on specific port
  port1 <- get_available_port()
  worker1 <- start_worker(port = port1, timeout = 10)

  tryCatch(
    {
      expect_equal(worker1$port, port1)
      expect_true(worker1$process$is_alive())

      # Start second worker without specifying port (should find different port)
      worker2 <- start_worker(timeout = 10)

      tryCatch(
        {
          expect_true(worker2$process$is_alive())
          expect_false(worker1$port == worker2$port)
        },
        finally = {
          stop_worker(worker2, timeout = 5)
        }
      )
    },
    finally = {
      stop_worker(worker1, timeout = 5)
    }
  )
})
