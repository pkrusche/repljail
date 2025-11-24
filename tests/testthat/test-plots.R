# Tests for Phase 4: Enhanced Plot Handling with Vision Integration
here::i_am("tests/testthat/test-plots.R")

test_that("repljail_execute_code handles multiple plots correctly", {
  skip_on_check()

  # Create session
  create_result <- repljail_create_repl_session()
  expect_true(create_result$success)

  session_id <- create_result$data$session_id

  tryCatch(
    {
      # Execute code that generates multiple plots
      result <- repljail_execute_code(
        session_id,
        "
        set.seed(456)
        hist(rnorm(30), main = 'Plot 1')
        plot(1:10, rnorm(10), main = 'Plot 2')
        'Multiple plots created'
      ",
        timeout = 15
      )
      debug_log("Execution result:", result)

      expect_true(result$success)
      expect_equal(result$data$status, "success")

      # Check that multiple plots are handled
      expect_equal(result$data$plots$count, 2)
      expect_equal(length(result$data$plots$file_paths), 2)

      # All file paths should be valid and exist
      for (file_path in result$data$plots$file_paths) {
        expect_true(file.exists(file_path))
        expect_true(grepl("\\.png$", file_path))
      }
    },
    finally = {
      # Clean up
      repljail_stop_session(session_id)
    }
  )
})

test_that("repljail_execute_code works without plots (backward compatibility)", {
  skip_on_check()

  # Create session
  create_result <- repljail_create_repl_session()
  expect_true(create_result$success)

  session_id <- create_result$data$session_id

  tryCatch(
    {
      # Execute code without plots
      result <- repljail_execute_code(session_id, "2 + 2", timeout = 10)

      expect_true(result$success)
      expect_equal(result$data$status, "success")

      # Check plot structure for non-plotting code
      expect_equal(result$data$plots$count, 0)
      expect_equal(length(result$data$plots$file_paths), 0)
    },
    finally = {
      # Clean up
      repljail_stop_session(session_id)
    }
  )
})
