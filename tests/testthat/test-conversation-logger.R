test_that("ConversationLogger can be created", {
  logger <- ConversationLogger$new()
  expect_s3_class(logger, "ConversationLogger")
  expect_true(grepl("# Conversation Log", logger$get_log()))
})

test_that("ConversationLogger can be created with log file", {
  temp_file <- tempfile(fileext = ".md")
  logger <- ConversationLogger$new(log_file = temp_file, auto_save = FALSE)
  expect_equal(logger$log_file, temp_file)
  expect_false(logger$auto_save)
})

test_that("ConversationLogger logs header correctly", {
  logger <- ConversationLogger$new()
  log <- logger$get_log()

  expect_true(grepl("# Conversation Log", log))
  expect_true(grepl("\\*\\*Started:\\*\\*", log))
})

test_that("create_conversation_logger convenience function works", {
  logger <- create_conversation_logger()
  expect_s3_class(logger, "ConversationLogger")
})

test_that("ConversationLogger can save to file", {
  temp_file <- tempfile(fileext = ".md")
  logger <- ConversationLogger$new(log_file = temp_file)

  # Save the log
  logger$save()

  # Check file exists
  expect_true(file.exists(temp_file))

  # Check content
  content <- readLines(temp_file)
  expect_true(any(grepl("# Conversation Log", content)))

  # Clean up
  unlink(temp_file)
})

test_that("ConversationLogger can save to specified file", {
  temp_file <- tempfile(fileext = ".md")
  logger <- ConversationLogger$new()

  # Save to specific file
  logger$save(temp_file)

  # Check file exists
  expect_true(file.exists(temp_file))

  # Clean up
  unlink(temp_file)
})

test_that("ConversationLogger errors when saving without file path", {
  logger <- ConversationLogger$new()
  expect_error(logger$save(), "No file path provided")
})

test_that("ConversationLogger can clear log", {
  logger <- ConversationLogger$new()

  # Get initial log
  initial_log <- logger$get_log()

  # Add some content (simulate logging)
  logger$get_log()

  # Clear
  logger$clear()

  # Log should be reset
  cleared_log <- logger$get_log()
  expect_true(grepl("# Conversation Log", cleared_log))
})

test_that("ConversationLogger validates chat object on attach", {
  logger <- ConversationLogger$new()
  expect_error(logger$attach("not a chat object"), "Must provide an ellmer Chat object")
})

# Mock Chat object for testing without ellmer dependency
create_mock_chat <- function() {
  mock_chat <- R6::R6Class(
    "Chat",
    lock_objects = FALSE,  # Allow modification of bindings
    public = list(
      chat = function(...) {
        private$chat_history <- c(private$chat_history, list(list(...)))
        "Mock response"
      },
      on_tool_request = function(callback) {
        private$tool_request_callback <- callback
      },
      on_tool_result = function(callback) {
        private$tool_result_callback <- callback
      },
      trigger_tool_request = function(request) {
        if (!is.null(private$tool_request_callback)) {
          private$tool_request_callback(request)
        }
      },
      trigger_tool_result = function(result) {
        if (!is.null(private$tool_result_callback)) {
          private$tool_result_callback(result)
        }
      }
    ),
    private = list(
      chat_history = list(),
      tool_request_callback = NULL,
      tool_result_callback = NULL
    )
  )$new()

  # Unlock the 'chat' binding to allow ConversationLogger to wrap it
  unlockBinding("chat", mock_chat)

  return(mock_chat)
}

test_that("ConversationLogger can attach to mock chat", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()

  expect_silent(logger$attach(mock_chat))
})

test_that("ConversationLogger logs chat turns", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a chat turn
  response <- mock_chat$chat("What is 2+2?")

  # Check log contains user prompt
  log <- logger$get_log()
  expect_true(grepl("## Turn 1", log))
  expect_true(grepl("### User", log))
  expect_true(grepl("What is 2\\+2\\?", log))
  expect_true(grepl("### Assistant", log))
  expect_true(grepl("Mock response", log))
})

test_that("ConversationLogger logs tool requests for R code", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a tool request
  tool_request <- list(
    name = "replr_execute_code",
    arguments = list(
      session_id = "test-session",
      code = "x <- 1 + 1\nprint(x)"
    )
  )

  mock_chat$trigger_tool_request(tool_request)

  # Check log contains tool call
  log <- logger$get_log()
  expect_true(grepl("### Tool Call", log))
  expect_true(grepl("\\*\\*Tool:\\*\\* `replr_execute_code`", log))
  expect_true(grepl("\\*\\*Code:\\*\\*", log))
  expect_true(grepl("```r", log))
  expect_true(grepl("x <- 1 \\+ 1", log))
  expect_true(grepl("\\*\\*Session:\\*\\* test-session", log))
})

test_that("ConversationLogger logs tool requests for replr_run_r_code", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a tool request
  tool_request <- list(
    name = "replr_run_r_code",
    arguments = list(
      code = "mean(1:10)"
    )
  )

  mock_chat$trigger_tool_request(tool_request)

  # Check log contains tool call with code block
  log <- logger$get_log()
  expect_true(grepl("### Tool Call", log))
  expect_true(grepl("\\*\\*Tool:\\*\\* `replr_run_r_code`", log))
  expect_true(grepl("```r", log))
  expect_true(grepl("mean\\(1:10\\)", log))
})

test_that("ConversationLogger logs generic tool requests", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a generic tool request
  tool_request <- list(
    name = "some_other_tool",
    arguments = list(
      param1 = "value1",
      param2 = 42
    )
  )

  mock_chat$trigger_tool_request(tool_request)

  # Check log contains tool call with JSON arguments
  log <- logger$get_log()
  expect_true(grepl("### Tool Call", log))
  expect_true(grepl("\\*\\*Tool:\\*\\* `some_other_tool`", log))
  expect_true(grepl("\\*\\*Arguments:\\*\\*", log))
  expect_true(grepl("```json", log))
})

test_that("ConversationLogger logs tool results with replr format", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a tool result in replr format
  tool_result <- list(
    success = TRUE,
    message = "Code executed successfully",
    data = list(
      output = c("[1] 2"),
      warnings = character(0),
      errors = character(0),
      execution_time = 0.012,
      plots = list(count = 0)
    )
  )

  mock_chat$trigger_tool_result(tool_result)

  # Check log contains tool result
  log <- logger$get_log()
  expect_true(grepl("### Tool Result", log))
  expect_true(grepl("\\*\\*Status:\\*\\* ✓ Success", log))
  expect_true(grepl("\\*\\*Message:\\*\\* Code executed successfully", log))
  expect_true(grepl("\\*\\*Output:\\*\\*", log))
  expect_true(grepl("\\[1\\] 2", log))
  expect_true(grepl("\\*\\*Execution time:\\*\\*", log))
})

test_that("ConversationLogger logs tool results with errors", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a tool result with errors
  tool_result <- list(
    success = FALSE,
    message = "Code execution failed",
    data = list(
      output = character(0),
      warnings = c("Warning: something happened"),
      errors = c("Error in foo(): object not found"),
      execution_time = 0.005
    ),
    error = "object not found"
  )

  mock_chat$trigger_tool_result(tool_result)

  # Check log contains error information
  log <- logger$get_log()
  expect_true(grepl("### Tool Result", log))
  expect_true(grepl("\\*\\*Status:\\*\\* ✗ Failed", log))
  expect_true(grepl("\\*\\*Warnings:\\*\\*", log))
  expect_true(grepl("\\*\\*Errors:\\*\\*", log))
  expect_true(grepl("object not found", log))
})

test_that("ConversationLogger logs tool results with plots", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a tool result with plots
  tool_result <- list(
    success = TRUE,
    message = "Code executed successfully",
    data = list(
      output = character(0),
      warnings = character(0),
      errors = character(0),
      execution_time = 0.45,
      plots = list(
        count = 2,
        data_urls = c("data:image/png;base64,abc123", "data:image/png;base64,def456")
      )
    )
  )

  mock_chat$trigger_tool_result(tool_result)

  # Check log contains plot information
  log <- logger$get_log()
  expect_true(grepl("\\*\\*Plots:\\*\\* 2 plot\\(s\\) generated", log))

  # Check that plot images are embedded with markdown image syntax
  expect_true(grepl("!\\[Plot 1\\]\\(data:image/png;base64,abc123\\)", log))
  expect_true(grepl("!\\[Plot 2\\]\\(data:image/png;base64,def456\\)", log))
})

test_that("ConversationLogger logs generic tool results", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a generic tool result (not replr format)
  tool_result <- list(
    result = "some generic result",
    status = "ok"
  )

  mock_chat$trigger_tool_result(tool_result)

  # Check log contains JSON result
  log <- logger$get_log()
  expect_true(grepl("### Tool Result", log))
  expect_true(grepl("```json", log))
})

test_that("ConversationLogger auto-saves when enabled", {
  temp_file <- tempfile(fileext = ".md")
  logger <- ConversationLogger$new(log_file = temp_file, auto_save = TRUE)
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate a chat turn
  mock_chat$chat("Test message")

  # File should be saved automatically
  expect_true(file.exists(temp_file))

  # Clean up
  unlink(temp_file)
})

test_that("ConversationLogger tracks multiple turns", {
  logger <- ConversationLogger$new()
  mock_chat <- create_mock_chat()
  logger$attach(mock_chat)

  # Simulate multiple turns
  mock_chat$chat("First question")
  mock_chat$chat("Second question")
  mock_chat$chat("Third question")

  # Check log contains all turns
  log <- logger$get_log()
  expect_true(grepl("## Turn 1", log))
  expect_true(grepl("## Turn 2", log))
  expect_true(grepl("## Turn 3", log))
})
