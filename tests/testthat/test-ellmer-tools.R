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

test_that("replr_create_repl_session with custom ID works", {
  custom_id <- "test_session_123"

  # Test creating a session with custom ID
  result <- replr_create_repl_session(custom_id, timeout = 15)

  expect_true(result$success)
  expect_equal(result$data$session_id, custom_id)
  expect_true(result$data$is_alive)

  # Test that duplicate ID is rejected
  duplicate_result <- replr_create_repl_session(custom_id)
  expect_false(duplicate_result$success)
  expect_equal(duplicate_result$error, "DUPLICATE_SESSION_ID")

  # Clean up
  cleanup_result <- replr_stop_session(custom_id)
  expect_true(cleanup_result$success)
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
  session1_result <- replr_create_repl_session("session_1", timeout = 15)
  session2_result <- replr_create_repl_session("session_2", timeout = 15)
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
      expect_true("session_1" %in% session_ids)
      expect_true("session_2" %in% session_ids)
    },
    finally = {
      # Clean up
      replr_stop_session("session_1")
      replr_stop_session("session_2")
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
  session1_result <- replr_create_repl_session("session_a", timeout = 15)
  session2_result <- replr_create_repl_session("session_b", timeout = 15)
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
  session1_result <- replr_create_repl_session("isolation_test_1", timeout = 15)
  session2_result <- replr_create_repl_session("isolation_test_2", timeout = 15)
  expect_true(session1_result$success)
  expect_true(session2_result$success)

  tryCatch(
    {
      # Set different variables in each session
      result1 <- replr_execute_code("isolation_test_1", "my_var <- 'Session 1'")
      result2 <- replr_execute_code("isolation_test_2", "my_var <- 'Session 2'")
      expect_true(result1$success)
      expect_true(result2$success)

      # Verify isolation - each session should only see its own variable
      check1 <- replr_execute_code("isolation_test_1", "my_var")
      check2 <- replr_execute_code("isolation_test_2", "my_var")

      expect_true(check1$success)
      expect_true(check2$success)
      expect_true(any(grepl("Session 1", check1$data$output)))
      expect_true(any(grepl("Session 2", check2$data$output)))
    },
    finally = {
      # Clean up
      replr_stop_session("isolation_test_1")
      replr_stop_session("isolation_test_2")
    }
  )
})
