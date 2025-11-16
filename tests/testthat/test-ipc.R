# Tests for IPC (Unix domain socket) functionality
here::i_am("tests/testthat/test-ipc.R")

test_that("IPC socket path generation works", {
  socket_path <- replr:::get_ipc_socket_path()

  # Check that path is a character string
  expect_type(socket_path, "character")

  # Check that path starts with temp directory
  expect_true(grepl(tempdir(), socket_path, fixed = TRUE))

  # Check that path contains replr_socket pattern
  expect_true(grepl("replr_socket_", socket_path))
})

test_that("Native worker uses IPC sockets", {
  skip_on_check()
  testthat::skip_on_ci()

  # Set worker type to native explicitly
  options(replr.worker.type = "native")

  # Create a session
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Check that session has socket_path (IPC mode)
      info <- session$get_info()
      expect_true(
        !is.null(info$socket_path),
        "Native worker should use IPC socket"
      )

      # Verify socket path exists as a file
      expect_true(file.exists(info$socket_path), "IPC socket file should exist")

      # Test that execution works over IPC
      result <- session$execute("1 + 1")
      expect_equal(result$status, "success")
      expect_true(any(grepl("2", result$result$output)))
    },
    finally = {
      session$stop()

      # Verify socket file is cleaned up after stop
      if (!is.null(session$get_info()$socket_path)) {
        Sys.sleep(0.5) # Give cleanup a moment
        expect_false(
          file.exists(session$get_info()$socket_path),
          "IPC socket file should be cleaned up"
        )
      }
    }
  )
})

test_that("Firejail worker uses IPC sockets when available", {
  skip_on_check()
  testthat::skip_on_ci()
  skip_if_not(replr::is_firejail_available(), "Firejail not available")

  # Set worker type to firejail explicitly
  options(replr.worker.type = "firejail")

  # Create a session
  session <- RREPLSession$new(timeout = 15)

  tryCatch(
    {
      # Check that session has socket_path (IPC mode)
      info <- session$get_info()
      expect_true(
        !is.null(info$socket_path),
        "Firejail worker should use IPC socket"
      )

      # Verify socket path exists as a file
      expect_true(file.exists(info$socket_path), "IPC socket file should exist")

      # Test that execution works over IPC
      result <- session$execute("2 + 2")
      expect_equal(result$status, "success")
      expect_true(any(grepl("4", result$result$output)))
    },
    finally = {
      session$stop()

      # Verify socket file is cleaned up after stop
      if (!is.null(session$get_info()$socket_path)) {
        Sys.sleep(0.5) # Give cleanup a moment
        expect_false(
          file.exists(session$get_info()$socket_path),
          "IPC socket file should be cleaned up"
        )
      }
    }
  )
})

test_that("Docker worker still uses TCP (not IPC)", {
  skip_on_check()
  testthat::skip_on_ci()
  skip_if_not(replr::is_docker_available(), "Docker not available")

  # Set worker type to docker explicitly
  options(replr.worker.type = "docker")

  # Create a session
  session <- RREPLSession$new(timeout = 20)

  tryCatch(
    {
      # Check that session uses port (TCP mode), not socket_path
      info <- session$get_info()
      expect_true(
        is.null(info$socket_path),
        "Docker worker should NOT use IPC socket"
      )
      expect_true(
        !is.null(info$port) && info$port > 0,
        "Docker worker should use TCP port"
      )

      # Test that execution works
      result <- session$execute("3 + 3")
      expect_equal(result$status, "success")
      expect_true(any(grepl("6", result$result$output)))
    },
    finally = {
      session$stop()
    }
  )
})

test_that("Worker script accepts socket path argument", {
  skip_on_check()
  testthat::skip_on_ci()
  library(processx)

  # Get worker script path
  worker_path <- replr:::get_worker_script_path()

  # Create a temporary socket path
  socket_path <- tempfile(pattern = "test_socket_", tmpdir = tempdir())

  # Start worker with socket path
  proc <- process$new(
    file.path(R.home("bin"), "Rscript"),
    c(worker_path, socket_path),
    stdout = "|",
    stderr = "|"
  )

  Sys.sleep(2) # Wait for worker to start

  tryCatch(
    {
      # Check worker is alive
      expect_true(proc$is_alive())

      # Check worker output mentions IPC
      stderr_output <- proc$read_error_lines()
      expect_true(any(grepl("Worker starting on ipc://", stderr_output)))

      # Verify socket file was created
      expect_true(
        file.exists(socket_path),
        "Socket file should be created by worker"
      )
    },
    finally = {
      # Clean up
      if (proc$is_alive()) {
        proc$kill()
      }

      # Clean up socket file
      if (file.exists(socket_path)) {
        unlink(socket_path)
      }
    }
  )
})

test_that("IPC communication works end-to-end", {
  skip_on_check()
  testthat::skip_on_ci()
  # Set worker type to native for IPC
  options(replr.worker.type = "native")

  # Create session
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test multiple commands to verify stable IPC communication
      result1 <- session$execute("x <- 10")
      expect_equal(result1$status, "success")

      result2 <- session$execute("y <- 20")
      expect_equal(result2$status, "success")

      result3 <- session$execute("x + y")
      expect_equal(result3$status, "success")
      expect_true(any(grepl("30", result3$result$output)))

      # Test error handling over IPC
      result4 <- session$execute("stop('test error')")
      expect_equal(result4$status, "error")

      # Verify session continues to work after error
      result5 <- session$execute("5 * 5")
      expect_equal(result5$status, "success")
      expect_true(any(grepl("25", result5$result$output)))
    },
    finally = {
      session$stop()
    }
  )
})
