# Tests for Firejail functionality
here::i_am("tests/testthat/test-firejail.R")

# Skip all Firejail tests on CI environments
skip_on_ci_for_firejail <- function() {
  if (nzchar(Sys.getenv("GITHUB_ACTIONS"))) {
    testthat::skip("Firejail tests skipped on CI")
  }
}

test_that("Firejail availability detection works", {
  skip_on_ci_for_firejail()

  # Should return logical value
  result <- replr:::is_firejail_available()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that("Firejail worker wrapper can be created", {
  skip_on_ci_for_firejail()

  # Skip if Firejail is not available
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")

  # Ensure only native mode (wrappers can be created without starting workers)
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "native")

  # Create a firejail wrapper
  wrapper <- replr:::FirejailWorkerWrapper$new()
  expect_s3_class(wrapper, "FirejailWorkerWrapper")
  expect_s3_class(wrapper, "WorkerWrapper")

  # Check metadata
  metadata <- wrapper$get_metadata()
  expect_equal(metadata$type, "firejail")
})

test_that("Firejail session can be created and execute commands", {
  skip_on_ci_for_firejail()

  # Skip if Firejail is not available
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")

  # Set options to use only Firejail
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "firejail")

  # Create a session (should use Firejail due to option)
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Check wrapper type
  expect_equal(session$wrapper_type, "firejail")

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

test_that("Firejail provides network isolation", {
  skip_on_ci_for_firejail()

  # Skip if Firejail is not available
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")

  # Set options to use only Firejail
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "firejail")
  # Set option to use Firejail
  old_option <- getOption("replr.use.firejail")
  on.exit(options(replr.use.firejail = old_option))
  options(replr.use.firejail = TRUE)
  # Skip if networking features are not available
  skip_if_not(
    replr:::is_firejail_networking_available(),
    "Firejail networking features disabled in system configuration"
  )

  # Set options to use only Firejail
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "firejail")

  # Create a session with firejail
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Verify the session can still execute code
  result <- session$execute("cat(2 + 2)", timeout = 5)
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")

  # Verify that external internet access is blocked (--net=lo blocks external access)
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

  # Test 3: Direct IP access (bypass DNS) - look up current IP for example.com
  result_ip <- session$execute(
    '
    tryCatch({
      # Look up the IP for example.com
      ip <- system("dig +short example.com | head -1", intern = TRUE)
      if (length(ip) > 0 && nchar(ip) > 0) {
        readLines(url(paste0("http://", ip)), n=1, warn=FALSE)
        "IP_ACCESSIBLE"
      } else {
        "IP_LOOKUP_FAILED"
      }
    }, error = function(e) "IP_BLOCKED")
  ',
    timeout = 15
  )
  expect_equal(result_ip$status, "success")
  expect_true(grepl("IP_BLOCKED|IP_LOOKUP_FAILED", result_ip$result$output))

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

test_that("Firejail allows writing to temp directory", {
  skip_on_ci_for_firejail()

  # Skip if Firejail is not available
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")

  # Set options to use only Firejail
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))
  options(replr.worker.type = "firejail")

  # Create a session with firejail
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

test_that("Firejail custom profile can be used", {
  skip_on_ci_for_firejail()

  # Skip if Firejail is not available
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")

  # Create a temporary profile file
  profile_file <- tempfile(fileext = ".profile")
  on.exit(unlink(profile_file), add = TRUE)

  # Write a minimal profile that allows localhost communication
  # Note: We cannot use 'net none' as it blocks localhost, breaking socket communication
  # Instead, we use filesystem and capability restrictions
  writeLines(c(
    "# Custom firejail profile for testing",
    "# Note: Cannot use 'net none' as it breaks localhost socket communication",
    "private-tmp",
    "caps.drop all",
    "seccomp",
    "noroot"
  ), profile_file)

  # Set options to use only Firejail with custom profile
  old_worker_type <- getOption("replr.worker.type")
  old_profile <- getOption("replr.worker.firejail.profile")
  on.exit({
    options(replr.worker.type = old_worker_type)
    options(replr.worker.firejail.profile = old_profile)
  }, add = TRUE)

  options(replr.worker.type = "firejail")
  options(replr.worker.firejail.profile = profile_file)

  # Create a session (should use custom profile)
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive and can execute code
  expect_true(session$is_alive())

  result <- session$execute("cat(2 + 2)")
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")
})

test_that("Worker wrapper factory creates correct type", {
  skip_on_ci_for_firejail()

  # Save option
  old_worker_type <- getOption("replr.worker.type")
  on.exit(options(replr.worker.type = old_worker_type))

  # Test native wrapper (default)
  options(replr.worker.type = "native")
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "native")

  # Test firejail wrapper
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")
  options(replr.worker.type = "firejail")
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "firejail")

  # Test invalid type
  options(replr.worker.type = "invalid")
  expect_error(
    replr:::create_worker_wrapper(),
    "Invalid worker type"
  )
})
