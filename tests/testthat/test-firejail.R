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

  # Set option to use Firejail
  old_option <- getOption("replr.use.firejail")
  on.exit(options(replr.use.firejail = old_option))
  options(replr.use.firejail = TRUE)

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

  # Set option to use Firejail
  old_option <- getOption("replr.use.firejail")
  on.exit(options(replr.use.firejail = old_option))
  options(replr.use.firejail = TRUE)

  # Create a session with firejail
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Verify the session can still execute code
  result <- session$execute("cat(2 + 2)", timeout = 5)
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")

  # Verify that internet access is blocked (--net=lo blocks external access)
  result_internet <- session$execute(
    '
    tryCatch({
      readLines(url("http://example.com"), n=1, warn=FALSE)
      "ACCESSIBLE"
    }, error = function(e) "BLOCKED")
  ',
    timeout = 15
  )
  expect_equal(result_internet$status, "success")
  expect_equal(result_internet$result$output, "[1] \"BLOCKED\"\n")
})

test_that("Firejail allows writing to temp directory", {
  skip_on_ci_for_firejail()

  # Skip if Firejail is not available
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")

  # Set option to use Firejail
  old_option <- getOption("replr.use.firejail")
  on.exit(options(replr.use.firejail = old_option))
  options(replr.use.firejail = TRUE)

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

  # Write a minimal profile (just network isolation for simplicity)
  writeLines(c(
    "# Custom firejail profile for testing",
    "net none",
    "private-tmp"
  ), profile_file)

  # Set options to use Firejail with custom profile
  old_firejail_option <- getOption("replr.use.firejail")
  old_profile_option <- getOption("replr.worker.firejail.profile")
  on.exit({
    options(replr.use.firejail = old_firejail_option)
    options(replr.worker.firejail.profile = old_profile_option)
  }, add = TRUE)

  options(replr.use.firejail = TRUE)
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

  # Test native wrapper (default)
  options(replr.use.firejail = FALSE)
  options(replr.use.docker = FALSE)
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "native")

  # Test firejail wrapper
  skip_if_not(replr:::is_firejail_available(), "Firejail not available")
  options(replr.use.firejail = TRUE)
  options(replr.use.docker = FALSE)
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "firejail")

  # Test that firejail takes priority over docker
  options(replr.use.firejail = TRUE)
  options(replr.use.docker = TRUE)
  wrapper <- replr:::create_worker_wrapper()
  expect_equal(wrapper$get_metadata()$type, "firejail")
})
