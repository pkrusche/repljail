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

test_that("Docker session can be created and execute commands", {
  # Skip if Docker is not available
  skip_if_not(replr:::is_docker_available(), "Docker not available")

  # Set option to use Docker
  old_option <- getOption("replr.use.docker")
  on.exit(options(replr.use.docker = old_option))
  options(replr.use.docker = TRUE)

  # Create a session (should use Docker due to option)
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Execute a simple command
  result <- session$execute("2 + 2")

  # Check result structure
  expect_type(result, "list")
  expect_equal(result$status, "success")
  expect_type(result$result, "list")
  expect_type(result$result$output, "character")

  # Check the actual result
  expect_equal(result$result$output, "4")
})
