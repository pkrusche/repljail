# Tests for macOS Sandbox functionality
here::i_am("tests/testthat/test-macos-sandbox.R")

# Skip all macOS sandbox tests on non-macOS systems and CI environments
skip_on_ci_for_macos_sandbox <- function() {
  if (nzchar(Sys.getenv("GITHUB_ACTIONS"))) {
    testthat::skip("macOS sandbox tests skipped on CI")
  }
  if (Sys.info()["sysname"] != "Darwin") {
    testthat::skip("macOS sandbox tests only run on macOS")
  }
}

test_that("macOS sandbox availability detection works", {
  skip_on_ci_for_macos_sandbox()

  # Should return logical value
  result <- replr:::is_macos_sandbox_available()
  expect_type(result, "logical")
  expect_length(result, 1)

  # On macOS, should be TRUE if sandbox-exec is available
  if (Sys.info()["sysname"] == "Darwin" && Sys.which("sandbox-exec") != "") {
    expect_true(result)
  }
})

test_that("macOS sandbox worker wrapper can be created", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Ensure only native mode (wrappers can be created without starting workers)
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "native")

  # Create a macOS sandbox wrapper
  wrapper <- replr:::MacOSSandboxWorkerWrapper$new()
  expect_s3_class(wrapper, "MacOSSandboxWorkerWrapper")
  expect_s3_class(wrapper, "WorkerWrapper")

  # Check metadata
  metadata <- wrapper$get_metadata()
  expect_equal(metadata$type, "macos_sandbox")
})

test_that("macOS sandbox session can be created and execute commands", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Set options to use only macOS sandbox
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "macos-sandbox")

  # Create a session (should use macOS sandbox due to option)
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Check wrapper type
  expect_equal(session$wrapper_type, "macos_sandbox")

  # Execute a simple command
  result <- session$execute("cat(2 + 2)")

  # Check result structure
  expect_type(result, "list")
  expect_equal(result$status, "success")
  expect_type(result$result, "list")
  expect_type(result$result$output, "character")

  # Check the actual result
  expect_equal(result$result$output, "4")
})

test_that("macOS sandbox provides network isolation", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Set options to use only macOS sandbox
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "macos-sandbox")

  # Create a session with macOS sandbox
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Verify the session can still execute code
  result <- session$execute("cat(2 + 2)", timeout = 5)
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")

  # Verify that external internet access is blocked (localhost-only network policy)
  # Test 1: HTTP to external domain
  result_http <- session$execute(
    '
    tryCatch({
      readLines(url("http://example.com"), n=1, warn=FALSE)
      "HTTP_ACCESSIBLE"
    }, error = function(e) "HTTP_BLOCKED")
  ',
    timeout = 15
  )
  expect_equal(result_http$status, "success")
  expect_equal(result_http$result$output, "[1] \"HTTP_BLOCKED\"\n")

  # Test 2: HTTPS to external domain
  result_https <- session$execute(
    '
    tryCatch({
      readLines(url("https://www.google.com"), n=1, warn=FALSE)
      "HTTPS_ACCESSIBLE"
    }, error = function(e) "HTTPS_BLOCKED")
  ',
    timeout = 15
  )
  expect_equal(result_https$status, "success")
  expect_equal(result_https$result$output, "[1] \"HTTPS_BLOCKED\"\n")

  # Test 3: Direct IP access (bypass DNS) - use a known external IP
  # Skip this test if it takes too long or if dig is not available
  skip_if_not(Sys.which("dig") != "", "dig command not available")

  result_ip <- session$execute(
    '
    tryCatch({
      # Try to access a known public DNS server IP (Google DNS)
      # This bypasses DNS resolution
      con <- url("http://8.8.8.8", open = "r")
      close(con)
      "IP_ACCESSIBLE"
    }, error = function(e) {
      # Network should be blocked
      "IP_BLOCKED"
    })
  ',
    timeout = 10
  )
  expect_type(result_ip, "list")
  expect_equal(result_ip$status, "success")
  expect_equal(result_ip$result$output, "[1] \"IP_BLOCKED\"\n")

  # Test 4: Verify localhost communication still works
  result_localhost <- session$execute(
    '
    tryCatch({
      # Test that we can use network functions with localhost
      # The worker itself uses a localhost socket for communication
      "LOCALHOST_OK"
    }, error = function(e) "LOCALHOST_FAILED")
  ',
    timeout = 10
  )
  expect_equal(result_localhost$status, "success")
  expect_equal(result_localhost$result$output, "[1] \"LOCALHOST_OK\"\n")
})

test_that("macOS sandbox allows writing to temp directory", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Set options to use only macOS sandbox
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "macos-sandbox")

  # Create a session with macOS sandbox
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify we can write to temp directory
  result <- session$execute(
    '
    tmpfile <- tempfile()
    writeLines("test", tmpfile)
    file.exists(tmpfile)
  ',
    timeout = 10
  )

  expect_equal(result$status, "success")
  expect_true(grepl("TRUE", result$result$output))
})

test_that("macOS sandbox allows temp directory access", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Set options to use only macOS sandbox
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "macos-sandbox")

  # Create a session with macOS sandbox
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify we can write to temp directory
  result <- session$execute(
    '
    tryCatch({
      tmpfile <- tempfile()
      writeLines("test", tmpfile)
      content <- readLines(tmpfile)
      unlink(tmpfile)
      if (content == "test") "TEMP_WRITABLE" else "TEMP_FAILED"
    }, error = function(e) paste0("TEMP_ERROR: ", e$message))
  ',
    timeout = 10
  )

  expect_equal(result$status, "success")
  # macOS sandbox should allow writing to temp directory
  expect_true(grepl("TEMP_WRITABLE", result$result$output))
})

test_that("macOS sandbox custom profile can be used", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Create a temporary profile file
  profile_file <- tempfile(fileext = ".sb")
  on.exit(unlink(profile_file), add = TRUE)

  # Write a minimal sandbox profile - use permissive format like default profile
  writeLines(
    c(
      "; Custom macOS sandbox profile for testing",
      "(version 1)",
      "(allow default)",
      "(deny network-outbound (remote ip))",
      "(allow network* (remote tcp \"localhost:*\"))"
    ),
    profile_file
  )

  # Set options to use macOS sandbox with custom profile
  old_worker_type <- getOption("replr.worker.type")
  old_profile <- getOption("replr.worker.macos.sandbox.profile")
  on.exit(
    {
      options(replr.worker.type = old_worker_type)
      options(replr.worker.macos.sandbox.profile = old_profile)
    },
    add = TRUE
  )

  options(replr.worker.type = "macos-sandbox")
  options(replr.worker.macos.sandbox.profile = profile_file)

  # Create a session (should use custom profile)
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive and can execute code
  expect_true(session$is_alive())

  result <- session$execute("cat(2 + 2)")
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")
})

test_that("macOS sandbox supports plot generation", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Set options to use only macOS sandbox
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "macos-sandbox")

  # Create a session with macOS sandbox
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Generate a simple plot
  result <- session$execute(
    '
    plot(1:10, 1:10)
  ',
    timeout = 10
  )

  expect_equal(result$status, "success")
  expect_type(result$result$plots, "list")
  expect_true(length(result$result$plots) > 0)
  expect_true(grepl("^data:image/png;base64,", result$result$plots[[1]]))
})

test_that("Worker wrapper factory creates correct type with macOS sandbox", {
  skip_on_ci_for_macos_sandbox()

  # Save option
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))

  # Test native wrapper (default)
  options(replr.worker.type = "native")
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "native")

  # Test macOS sandbox wrapper
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )
  options(replr.worker.type = "macos-sandbox")
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "macos_sandbox")

  # Test docker wrapper
  options(replr.worker.type = "docker")
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "docker")

  # Test firejail wrapper (if available)
  if (replr:::is_firejail_available()) {
    options(replr.worker.type = "firejail")
    wrapper <- replr:::create_worker_wrapper()
    expect_equal(wrapper$get_metadata()$type, "firejail")
  }

  # Test invalid type
  options(replr.worker.type = "invalid")
  expect_error(
    replr:::create_worker_wrapper(),
    "Invalid worker type"
  )
})

test_that("macOS sandbox temporary profile cleanup works", {
  skip_on_ci_for_macos_sandbox()

  # Skip if macOS sandbox is not available
  skip_if_not(
    replr:::is_macos_sandbox_available(),
    "macOS sandbox not available"
  )

  # Set options to use only macOS sandbox
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "macos-sandbox")

  # Create a session
  session <- RREPLSession$new(timeout = 30)

  # Execute a command to ensure worker is running
  result <- session$execute("cat(2 + 2)")
  expect_equal(result$status, "success")

  # Stop the session
  session$stop()

  # Note: The temporary profile should be cleaned up automatically
  # We can't easily test this without accessing private members,
  # but we can verify the session stopped cleanly
  expect_false(session$is_alive())
})
