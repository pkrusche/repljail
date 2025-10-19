# Test ellmer tools functionality
here::i_am("tests/testthat/test-ellmer-tools.R")

test_that("replr_create_repl_session works", {
  # Test creating a session with auto-generated ID
  result <- replr::replr_create_repl_session(timeout = 15)

  expect_true(result$success)
  expect_true(is.character(result$data$session_id))
  expect_true(nchar(result$data$session_id) > 0)
  expect_true(is.numeric(result$data$port))
  expect_true(result$data$is_alive)

  # Clean up
  session_id <- result$data$session_id
  cleanup_result <- replr_stop_session(session_id)
  expect_true(cleanup_result$success)
})

test_that("replr_create_repl_session generates unique IDs", {
  # Test creating multiple sessions and verify they get unique IDs
  result1 <- replr_create_repl_session(timeout = 15)
  result2 <- replr_create_repl_session(timeout = 15)

  expect_true(result1$success)
  expect_true(result2$success)
  expect_true(is.character(result1$data$session_id))
  expect_true(is.character(result2$data$session_id))
  expect_true(result1$data$session_id != result2$data$session_id)
  expect_true(result1$data$is_alive)
  expect_true(result2$data$is_alive)

  # Clean up
  cleanup_result1 <- replr_stop_session(result1$data$session_id)
  cleanup_result2 <- replr_stop_session(result2$data$session_id)
  expect_true(cleanup_result1$success)
  expect_true(cleanup_result2$success)
})

test_that("replr_execute_code works", {
  # Create session
  session_result <- replr_create_repl_session(timeout = 15)
  expect_true(session_result$success)
  session_id <- session_result$data$session_id

  tryCatch(
    {
      # Test simple arithmetic
      result <- replr_execute_code(session_id, "2 + 2")
      expect_true(result$success)
      expect_equal(result$data$status, "success")
      expect_true(length(result$data$output) > 0)
      expect_true(any(grepl("4", result$data$output)))

      # Test code with warning
      warning_result <- replr_execute_code(
        session_id,
        "warning('test warning'); 42"
      )
      expect_true(warning_result$success)
      expect_equal(warning_result$data$status, "success")
      expect_true(length(warning_result$data$warnings) > 0)
      expect_true(any(grepl("test warning", warning_result$data$warnings)))

      # Test code with error
      error_result <- replr_execute_code(session_id, "stop('test error')")
      expect_false(error_result$success)
      expect_equal(error_result$data$status, "error")
      expect_true(length(error_result$data$errors) > 0)

      # Test that session survives error and continues working
      recovery_result <- replr_execute_code(session_id, "3 * 4")
      expect_true(recovery_result$success)
      expect_true(any(grepl("12", recovery_result$data$output)))
    },
    finally = {
      # Clean up
      replr_stop_session(session_id)
    }
  )
})

test_that("replr_execute_code handles non-existent session", {
  result <- replr_execute_code("non_existent_session", "1 + 1")
  expect_false(result$success)
  expect_equal(result$error, "SESSION_NOT_FOUND")
})

test_that("replr_get_session_info works", {
  # Create session
  session_result <- replr_create_repl_session(timeout = 15)
  expect_true(session_result$success)
  session_id <- session_result$data$session_id

  tryCatch(
    {
      # Get session info
      info_result <- replr_get_session_info(session_id)
      expect_true(info_result$success)
      expect_equal(info_result$data$session_id, session_id)
      expect_true(info_result$data$is_alive)
      expect_true(is.numeric(info_result$data$port))
      expect_true(is.numeric(info_result$data$pid))
    },
    finally = {
      # Clean up
      replr_stop_session(session_id)
    }
  )
})

test_that("replr_get_session_info handles non-existent session", {
  result <- replr_get_session_info("non_existent_session")
  expect_false(result$success)
  expect_equal(result$error, "SESSION_NOT_FOUND")
})

test_that("replr_list_sessions works", {
  # Test with no sessions
  initial_result <- replr_list_sessions()
  expect_true(initial_result$success)
  expect_equal(initial_result$data$count, 0)

  # Create a couple of sessions
  session1_result <- replr_create_repl_session(timeout = 15)
  session2_result <- replr_create_repl_session(timeout = 15)
  expect_true(session1_result$success)
  expect_true(session2_result$success)

  tryCatch(
    {
      # List sessions
      list_result <- replr_list_sessions()
      expect_true(list_result$success)
      expect_equal(list_result$data$count, 2)
      expect_equal(length(list_result$data$sessions), 2)

      # Check that both sessions are listed
      session_ids <- sapply(list_result$data$sessions, function(s) s$session_id)
      expect_true(session1_result$data$session_id %in% session_ids)
      expect_true(session2_result$data$session_id %in% session_ids)
    },
    finally = {
      # Clean up
      replr_stop_session(session1_result$data$session_id)
      replr_stop_session(session2_result$data$session_id)
    }
  )
})

test_that("replr_stop_session works", {
  # Create session
  session_result <- replr_create_repl_session(timeout = 15)
  expect_true(session_result$success)
  session_id <- session_result$data$session_id

  # Stop session
  stop_result <- replr_stop_session(session_id)
  expect_true(stop_result$success)
  expect_equal(stop_result$data$session_id, session_id)

  # Verify session is no longer in registry
  list_result <- replr_list_sessions()
  session_ids <- sapply(list_result$data$sessions, function(s) s$session_id)
  expect_false(session_id %in% session_ids)
})

test_that("replr_stop_session handles non-existent session", {
  result <- replr_stop_session("non_existent_session")
  expect_false(result$success)
  expect_equal(result$error, "SESSION_NOT_FOUND")
})

test_that("replr_stop_all_sessions works", {
  # Create multiple sessions
  session1_result <- replr_create_repl_session(timeout = 15)
  session2_result <- replr_create_repl_session(timeout = 15)
  expect_true(session1_result$success)
  expect_true(session2_result$success)

  # Verify sessions exist
  list_result <- replr_list_sessions()
  expect_equal(list_result$data$count, 2)

  # Stop all sessions
  stop_all_result <- replr_stop_all_sessions()
  expect_true(stop_all_result$success)
  expect_equal(stop_all_result$data$stopped_count, 2)

  # Verify no sessions remain
  final_list_result <- replr_list_sessions()
  expect_equal(final_list_result$data$count, 0)
})

test_that("replr_cleanup_sessions works", {
  # For this test, we'll just verify the function runs without error
  # since it's hard to simulate dead sessions in a test
  cleanup_result <- replr_cleanup_sessions()
  expect_true(cleanup_result$success)
  expect_true(is.numeric(cleanup_result$data$cleaned_count))
  expect_true(is.numeric(cleanup_result$data$remaining_sessions))
})

test_that("Multiple sessions maintain isolation", {
  # Create two sessions
  session1_result <- replr_create_repl_session(timeout = 15)
  session2_result <- replr_create_repl_session(timeout = 15)
  expect_true(session1_result$success)
  expect_true(session2_result$success)

  tryCatch(
    {
      # Set different variables in each session
      result1 <- replr_execute_code(
        session1_result$data$session_id,
        "my_var <- 'Session 1'"
      )
      result2 <- replr_execute_code(
        session2_result$data$session_id,
        "my_var <- 'Session 2'"
      )
      expect_true(result1$success)
      expect_true(result2$success)

      # Verify isolation - each session should only see its own variable
      check1 <- replr_execute_code(session1_result$data$session_id, "my_var")
      check2 <- replr_execute_code(session2_result$data$session_id, "my_var")

      expect_true(check1$success)
      expect_true(check2$success)
      expect_true(any(grepl("Session 1", check1$data$output)))
      expect_true(any(grepl("Session 2", check2$data$output)))
    },
    finally = {
      # Clean up
      replr_stop_session(session1_result$data$session_id)
      replr_stop_session(session2_result$data$session_id)
    }
  )
})

test_that("replr_run_r_code works with simple arithmetic", {
  # Test simple arithmetic
  result <- replr_run_r_code("2 + 2")
  expect_true(result$success)
  expect_equal(result$data$status, "success")
  expect_true(length(result$data$output) > 0)
  expect_true(any(grepl("4", result$data$output)))
  
  # Verify session was cleaned up (check no new sessions exist)
  list_result <- replr_list_sessions()
  initial_count <- list_result$data$count
  
  # Run another simple calculation
  result2 <- replr_run_r_code("3 * 7")
  expect_true(result2$success)
  expect_true(any(grepl("21", result2$data$output)))
  
  # Verify still same number of sessions (auto-cleanup worked)
  list_result2 <- replr_list_sessions()
  expect_equal(list_result2$data$count, initial_count)
})

test_that("replr_run_r_code works with complex code", {
  code <- "
    data <- data.frame(x = 1:5, y = letters[1:5])
    summary(data)
  "
  result <- replr_run_r_code(code)
  expect_true(result$success)
  expect_equal(result$data$status, "success")
  expect_true(length(result$data$output) > 0)
})

test_that("replr_run_r_code handles errors correctly", {
  # Test code with error
  result <- replr_run_r_code("stop('test error')")
  expect_false(result$success)
  expect_equal(result$data$status, "error")
  expect_true(length(result$data$errors) > 0)
  
  # Verify session was still cleaned up
  list_result <- replr_list_sessions()
  expect_equal(list_result$data$count, 0)
})

test_that("replr_run_r_code handles warnings", {
  # Test code with warning
  result <- replr_run_r_code("warning('test warning'); 42")
  expect_true(result$success)
  expect_equal(result$data$status, "success")
  expect_true(length(result$data$warnings) > 0)
  expect_true(any(grepl("test warning", result$data$warnings)))
  expect_true(any(grepl("42", result$data$output)))
})

test_that("replr_run_r_code respects timeout parameter", {
  # Test with custom timeout
  result <- replr_run_r_code("Sys.sleep(0.1); 'done'", timeout = 5)
  expect_true(result$success)
  expect_true(any(grepl("done", result$data$output)))
})

test_that("replr_check_syntax works with valid code", {
  # Test simple valid code
  result <- replr_check_syntax("x <- 1 + 2")
  expect_true(result$success)
  expect_true(result$data$valid)
  expect_equal(result$data$expression_count, 1)
  expect_null(result$error)
  
  # Test multiple expressions
  result2 <- replr_check_syntax("x <- 1\ny <- 2\nz <- x + y")
  expect_true(result2$success)
  expect_true(result2$data$valid)
  expect_equal(result2$data$expression_count, 3)
})

test_that("replr_check_syntax detects syntax errors", {
  # Test missing closing parenthesis
  result <- replr_check_syntax("x <- mean(c(1, 2, 3)")
  expect_false(result$success)
  expect_false(result$data$valid)
  expect_true(nchar(result$error) > 0)
  expect_true(grepl("unexpected", result$error))
  
  # Test invalid function syntax
  result2 <- replr_check_syntax("x <- function() {\n  return 42\n}")
  expect_false(result2$success)
  expect_false(result2$data$valid)
  expect_true(nchar(result2$error) > 0)
})

test_that("replr_check_syntax handles empty code", {
  result <- replr_check_syntax("")
  expect_true(result$success)
  expect_true(result$data$valid)
  expect_equal(result$data$expression_count, 0)
})

test_that("replr_check_syntax handles complex valid code", {
  code <- "
library(ggplot2)
data <- data.frame(x = 1:10, y = rnorm(10))
plot <- ggplot(data, aes(x, y)) + 
  geom_point() +
  theme_minimal()
print(plot)
"
  result <- replr_check_syntax(code)
  expect_true(result$success)
  expect_true(result$data$valid)
  expect_true(result$data$expression_count > 0)
})

test_that("replr_check_syntax does not execute code", {
  # Code that would fail at runtime but has valid syntax
  code <- "
x <- nonexistent_function()
y <- undefined_variable + 1
"
  result <- replr_check_syntax(code)
  # Should succeed because syntax is valid even though runtime would fail
  expect_true(result$success)
  expect_true(result$data$valid)
})

test_that("replr_check_syntax_tool returns proper structure", {
  tool <- replr_check_syntax_tool()
  
  # Check basic structure
  expect_true(is.list(tool))
  expect_equal(tool$name, "replr_check_syntax")
  expect_true(nchar(tool$description) > 0)
  expect_true(is.list(tool$parameters))
  
  # Check that function is callable
  expect_true(is.function(tool$fn))
  
  # Test that the tool function works
  test_result <- tool$fn("x <- 1 + 1")
  expect_true(test_result$success)
  expect_true(test_result$data$valid)
})
