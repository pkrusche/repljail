# Tests for Docker functionality
here::i_am("tests/testthat/test-docker.R")

test_that("Docker availability detection works", {
  # Should return logical value
  result <- replr:::is_docker_available()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that("Docker image name is defined", {
  image_name <- replr:::get_worker_docker_image()
  expect_type(image_name, "character")
  expect_length(image_name, 1)
  expect_true(nchar(image_name) > 0)
})

test_that("RREPLSession accepts use_docker parameter", {
  # Skip if Docker not available
  skip_if_not(replr:::is_docker_available(), "Docker not available")
  
  # This test verifies parameter acceptance without actually creating session
  expect_error({
    # This should fail gracefully without Docker image
    session <- RREPLSession$new(use_docker = TRUE, timeout = 1)
  }, regexp = "(Docker|image)", class = "simpleError")
})

test_that("ellmer tools auto-detect Docker", {
  # Test the auto-detection logic
  result <- replr_create_repl_session_docker(use_docker = NULL)
  
  expect_type(result, "list")
  expect_true("success" %in% names(result))
  expect_true("using_docker" %in% names(result$data) || !result$success)
})

test_that("ellmer tools handle Docker unavailable gracefully", {
  # Test explicit Docker request when not available
  if (!replr:::is_docker_available()) {
    result <- replr_create_repl_session_docker(use_docker = TRUE)
    expect_false(result$success)
    expect_match(result$error, "DOCKER_NOT_AVAILABLE")
  } else {
    # If Docker is available, this should work (may fail on image build)
    result <- replr_create_repl_session_docker(use_docker = TRUE, timeout = 5)
    expect_type(result, "list")
    expect_true("success" %in% names(result))
  }
})