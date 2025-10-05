# Tests for Docker functionality
here::i_am("tests/testthat/test-docker.R")

# Skip all Docker tests on CI environments
skip_on_ci_for_docker <- function() {
  if (nzchar(Sys.getenv("GITHUB_ACTIONS"))) {
    testthat::skip("Docker tests skipped on CI")
  }
}

test_that("Docker availability detection works", {
  skip_on_ci_for_docker()

  # Should return logical value
  result <- replr:::is_docker_available()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that("Docker image name is defined", {
  skip_on_ci_for_docker()

  image_name <- replr:::get_worker_docker_image()
  expect_type(image_name, "character")
  expect_length(image_name, 1)
  expect_true(nchar(image_name) > 0)
})

test_that("Docker session can be created and execute commands", {
  skip_on_ci_for_docker()

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
  result <- session$execute("cat(2 + 2)")

  # Check result structure
  expect_type(result, "list")
  expect_equal(result$status, "success")
  expect_type(result$result, "list")
  expect_type(result$result$output, "character")

  # Check the actual result
  expect_equal(result$result$output, "4")
})

test_that("Docker network isolation can be enabled", {
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(replr:::is_docker_available(), "Docker not available")

  # Set options to use Docker with network isolation
  old_docker_option <- getOption("replr.use.docker")
  old_network_option <- getOption("replr.worker.docker.network.isolation")
  on.exit({
    options(replr.use.docker = old_docker_option)
    options(replr.worker.docker.network.isolation = old_network_option)
  })

  options(replr.use.docker = TRUE)
  options(replr.worker.docker.network.isolation = TRUE)

  # Create a session (should use Docker with network isolation)
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Execute a simple command to verify it works
  result <- session$execute("cat(2 + 2)")

  # Check result
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")

  # Check that network_name was stored in worker_info
  worker_info <- session$.__enclos_env__$private$worker_info
  expect_true(!is.null(worker_info$network_name))
})

test_that("Docker network cleanup works", {
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(replr:::is_docker_available(), "Docker not available")

  # Create a test network
  test_network <- paste0("replr-network-test-", as.integer(Sys.time()))

  # Create the network
  result <- replr:::create_docker_network(test_network)
  expect_true(result)

  # Verify network exists
  networks <- system2(
    "docker",
    c("network", "ls", "--filter", paste0("name=", test_network), "--format", "{{.Name}}"),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_true(test_network %in% networks)

  # Clean up the network
  result <- replr:::remove_docker_network(test_network)
  expect_true(result)

  # Verify network is gone
  networks <- system2(
    "docker",
    c("network", "ls", "--filter", paste0("name=", test_network), "--format", "{{.Name}}"),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_false(test_network %in% networks)
})

test_that("Docker network is cleaned up when session stops", {
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(replr:::is_docker_available(), "Docker not available")

  # Set options to use Docker with network isolation
  old_docker_option <- getOption("replr.use.docker")
  old_network_option <- getOption("replr.worker.docker.network.isolation")
  on.exit({
    options(replr.use.docker = old_docker_option)
    options(replr.worker.docker.network.isolation = old_network_option)
  })

  options(replr.use.docker = TRUE)
  options(replr.worker.docker.network.isolation = TRUE)

  # Create a session
  session <- RREPLSession$new(timeout = 30)

  # Get the network name
  worker_info <- session$.__enclos_env__$private$worker_info
  network_name <- worker_info$network_name
  expect_true(!is.null(network_name))

  # Verify network exists
  networks <- system2(
    "docker",
    c("network", "ls", "--filter", paste0("name=", network_name), "--format", "{{.Name}}"),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_true(network_name %in% networks)

  # Stop the session
  session$stop(timeout = 10)

  # Verify network is cleaned up
  # Give it a moment for cleanup to complete
  Sys.sleep(1)
  networks <- system2(
    "docker",
    c("network", "ls", "--filter", paste0("name=", network_name), "--format", "{{.Name}}"),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_false(network_name %in% networks)
})

test_that("Network isolation actually blocks external access", {
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(replr:::is_docker_available(), "Docker not available")

  # Set options to use Docker with network isolation
  old_docker_option <- getOption("replr.use.docker")
  old_network_option <- getOption("replr.worker.docker.network.isolation")
  on.exit({
    options(replr.use.docker = old_docker_option)
    options(replr.worker.docker.network.isolation = old_network_option)
  })

  options(replr.use.docker = TRUE)
  options(replr.worker.docker.network.isolation = TRUE)

  # Create a session with network isolation
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Try to access an external URL - this should fail due to network isolation
  # We use a timeout to ensure the test doesn't hang indefinitely
  result <- session$execute("
    tryCatch({
      # Attempt to access external network (e.g., DNS lookup and HTTP request)
      con <- url('http://example.com', open = 'r', timeout = 2)
      content <- readLines(con, warn = FALSE)
      close(con)
      cat('SUCCESS: External access worked')
      'external_access_success'
    }, error = function(e) {
      cat('ERROR: External access blocked -', e$message)
      'external_access_blocked'
    })
  ", timeout = 10)

  # Check that the result indicates an error (network isolation working)
  expect_equal(result$status, "success")
  expect_true(any(grepl("external_access_blocked", result$result$output)) ||
              any(grepl("ERROR", result$result$output)))
  expect_false(any(grepl("external_access_success", result$result$output)))
  expect_false(any(grepl("SUCCESS: External access worked", result$result$output)))
})

