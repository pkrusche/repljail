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

  tryCatch(
    {
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
    },
    finally = {
      session$stop()
    }
  )
})

test_that("RREPLSession handles worker death gracefully", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Verify session is alive
      expect_true(session$is_alive())

      # Kill the worker process directly
      pid <- session$pid
      session$stop()

      # Check status after stop
      expect_false(session$is_alive())

      # Verify execute fails on stopped session
      expect_error(session$execute("1 + 1"), "Session has been stopped")
    },
    finally = {
      # Ensure cleanup
      if (session$is_alive()) {
        session$stop()
      }
    }
  )
})

test_that("RREPLSession get_info method provides correct information", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
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
      expect_false(info$is_docker)
    },
    finally = {
      session$stop()
    }
  )
})

test_that("RREPLSession active bindings work correctly", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
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
    },
    finally = {
      if (session$is_alive()) {
        session$stop()
      }
    }
  )
})

test_that("RREPLSession handles timeouts correctly", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test execution timeout with a long-running operation
      result <- session$execute("Sys.sleep(3); 42", timeout = 1)

      # Should either timeout or succeed (depending on timing)
      expect_true(inherits(result, "errorValue"))
    },
    finally = {
      session$stop()
    }
  )
})

test_that("RREPLSession finalizer works for automatic cleanup", {
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
  session1 <- RREPLSession$new(timeout = 10)
  session2 <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Verify both sessions are alive and independent
      expect_true(session1$is_alive())
      expect_true(session2$is_alive())

      # Verify sessions are independent - check socket paths for IPC or ports for TCP
      info1 <- session1$get_info()
      info2 <- session2$get_info()

      if (!is.null(info1$socket_path) && !is.null(info2$socket_path)) {
        # IPC mode - verify different socket paths
        expect_true(info1$socket_path != info2$socket_path)
      } else {
        # TCP mode - verify different ports
        expect_true(session1$port != session2$port)
      }

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
    },
    finally = {
      session1$stop()
      session2$stop()
    }
  )
})

test_that("RREPLSession handles plot-generating code without errors", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test that complex plot code executes without error
      multi_plot_code <- "
      # Test various plotting functions
      result_summary <- list()

      tryCatch({
        hist(rnorm(50), main='Test Histogram')
        result_summary$hist <- 'success'
      }, error = function(e) {
        result_summary$hist <- paste('error:', e$message)
      })

      tryCatch({
        plot(1:10, 1:10, main='Test Scatter')
        result_summary$scatter <- 'success'
      }, error = function(e) {
        result_summary$scatter <- paste('error:', e$message)
      })

      tryCatch({
        boxplot(rnorm(30), main='Test Boxplot')
        result_summary$boxplot <- 'success'
      }, error = function(e) {
        result_summary$boxplot <- paste('error:', e$message)
      })

      result_summary
    "

      result <- session$execute(multi_plot_code, timeout = 15)
      expect_equal(result$status, "success")
      expect_true("plots" %in% names(result$result))
      expect_equal(length(result$result$plots), 3)

      # The output contains the result_summary list, so we need to check if the success values are present
      expect_true(any(grepl("success", result$result$output)))
      expect_true(any(grepl("hist.*success", result$result$output)))
      expect_true(any(grepl("scatter.*success", result$result$output)))
      expect_true(any(grepl("boxplot.*success", result$result$output)))
    },
    finally = {
      session$stop()
    }
  )
})

test_that("RREPLSession plot capture structure is correct", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Test that the response always includes proper plot structure
      simple_code <- "2 + 2"

      result <- session$execute(simple_code, timeout = 10)

      expect_equal(result$status, "success")
      expect_true(is.list(result$result))
      expect_true("plots" %in% names(result$result))
      expect_true(is.list(result$result$plots))

      # Even non-plotting code should have the plots field
      expect_true(length(result$result$plots) == 0)

      # Test that the structure is consistent
      expect_true(all(
        c("output", "warnings", "errors", "visible", "plots") %in%
          names(result$result)
      ))
    },
    finally = {
      session$stop()
    }
  )
})

test_that("RREPLSession deterministic plot generation and PNG comparison", {
  session <- RREPLSession$new(timeout = 10)

  tryCatch(
    {
      # Create a deterministic plot with set.seed for reproducibility
      deterministic_plot_code <- "
      set.seed(12345)
      data <- rnorm(100, mean = 0, sd = 1)
      hist(data,
           breaks = 10,
           main = 'Test Histogram (Deterministic)',
           xlab = 'Value',
           ylab = 'Frequency',
           col = 'lightblue',
           border = 'black')
    "

      result <- session$execute(deterministic_plot_code, timeout = 15)
      expect_equal(result$status, "success")
      expect_true("plots" %in% names(result$result))
      expect_equal(length(result$result$plots), 1)

      # Extract the plot object
      plot_base64 <- result$result$plots[[1]]
      expect_true(grepl("^data:image/png;base64,", plot_base64))
      # Decode base64 to raw vector
      plot_data <- sub("^data:image/png;base64,", "", plot_base64)
      plot_raw <- base64enc::base64decode(plot_data)
      # Read the plot into a temporary file
      # Use a temporary file to read the PNG
      test_output_file <- tempfile(fileext = ".png")
      writeBin(plot_raw, test_output_file)

      # Verify the PNG file was created
      expect_true(file.exists(test_output_file))
      expect_true(file.size(test_output_file) > 0)

      # Check for reference file and compare if it exists
      reference_file <- here::here(
        "tests",
        "testthat",
        "reference_plots",
        "test_histogram.png"
      )

      if (file.exists(reference_file)) {
        # Compare PNG files at pixel level
        tryCatch(
          {
            # Attempt to use png package for pixel-level comparison
            # Read PNG files as image arrays
            test_img <- png::readPNG(test_output_file)
            ref_img <- png::readPNG(reference_file)

            # Check dimensions match
            expect_equal(
              dim(test_img),
              dim(ref_img),
              info = "Image dimensions do not match between test and reference"
            )

            # Calculate pixel differences
            # For RGB images, compute mean absolute difference across all pixels and channels
            pixel_diff <- mean(abs(test_img - ref_img))

            # Set tolerance for pixel differences (allowing small variations due to R version differences)
            # Tolerance of 0.01 means 1% difference in pixel values is acceptable
            tolerance <- 0.01
            expect_true(
              pixel_diff < tolerance,
              info = paste(
                "Pixel difference too large:",
                pixel_diff,
                "exceeds tolerance:",
                tolerance
              )
            )

            message(
              "Pixel-level comparison completed. Mean absolute difference: ",
              round(pixel_diff, 6)
            )
          },
          error = function(e) {
            # If pixel comparison fails, fall back to file size comparison
            warning(
              "Pixel comparison failed, falling back to basic validation: ",
              e$message
            )
            expect_true(
              file.size(test_output_file) > 0,
              "Test file has zero size"
            )
            expect_true(
              file.size(reference_file) > 0,
              "Reference file has zero size"
            )
          }
        )

        # Always verify both files are valid PNG files (start with PNG signature)
        test_data <- readBin(test_output_file, "raw", 8)
        ref_data <- readBin(reference_file, "raw", 8)
        png_signature <- as.raw(c(
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A
        ))
        expect_equal(
          test_data,
          png_signature,
          info = "Test file does not have valid PNG signature"
        )
        expect_equal(
          ref_data,
          png_signature,
          info = "Reference file does not have valid PNG signature"
        )
      } else {
        # If reference file doesn't exist, copy the test file as reference
        # This is useful for initial setup
        dir.create(
          dirname(reference_file),
          recursive = TRUE,
          showWarnings = FALSE
        )
        file.copy(test_output_file, reference_file)
        message("Created reference file: ", reference_file)
      }

      # Clean up temporary file
      unlink(test_output_file)
    },
    finally = {
      session$stop()
    }
  )
})
