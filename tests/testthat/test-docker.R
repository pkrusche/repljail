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
  result <- repljail:::is_docker_available()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that("Docker image name is defined", {
  skip_on_ci_for_docker()

  image_name <- repljail:::get_worker_docker_image()
  expect_type(image_name, "character")
  expect_length(image_name, 1)
  expect_true(nchar(image_name) > 0)
})

test_that("Docker session can be created and execute commands", {
  skip_on_check()
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(repljail:::is_docker_available(), "Docker not available")

  # Set option to use Docker
  old_worker_type <- getOption("repljail.worker.type")
  on.exit(options(repljail.worker.type = old_worker_type))
  options(repljail.worker.type = "docker")

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
  skip_on_check()
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(repljail:::is_docker_available(), "Docker not available")

  # Set options to use only Docker with network isolation
  old_worker_type <- getOption("repljail.worker.type")
  old_network <- getOption("repljail.worker.docker.network.isolation")
  on.exit({
    options(repljail.worker.type = old_worker_type)
    options(repljail.worker.docker.network.isolation = old_network)
  })

  options(repljail.worker.type = "docker")
  options(repljail.worker.docker.network.isolation = TRUE)

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
  worker_info <- session$.__enclos_env__$private$.worker_info
  expect_true(!is.null(worker_info$network_name))
})

test_that("Docker network cleanup works", {
  skip_on_check()
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(repljail:::is_docker_available(), "Docker not available")

  # Create a test network
  test_network <- paste0("repljail-network-test-", as.integer(Sys.time()))

  # Create the network
  result <- repljail:::create_docker_network(test_network)
  expect_true(result)

  # Verify network exists
  networks <- system2(
    "docker",
    c(
      "network",
      "ls",
      "--filter",
      paste0("name=", test_network),
      "--format",
      "{{.Name}}"
    ),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_true(test_network %in% networks)

  # Clean up the network
  result <- repljail:::remove_docker_network(test_network)
  expect_true(result)

  # Verify network is gone
  networks <- system2(
    "docker",
    c(
      "network",
      "ls",
      "--filter",
      paste0("name=", test_network),
      "--format",
      "{{.Name}}"
    ),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_false(test_network %in% networks)
})

test_that("Docker network is cleaned up when session stops", {
  skip_on_check()
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(repljail:::is_docker_available(), "Docker not available")

  # Set options to use only Docker with network isolation
  old_worker_type <- getOption("repljail.worker.type")
  old_network <- getOption("repljail.worker.docker.network.isolation")
  on.exit({
    options(repljail.worker.type = old_worker_type)
    options(repljail.worker.docker.network.isolation = old_network)
  })

  options(repljail.worker.type = "docker")
  options(repljail.worker.docker.network.isolation = TRUE)

  # Create a session
  session <- RREPLSession$new(timeout = 30)

  # Get the network name
  worker_info <- session$.__enclos_env__$private$.worker_info
  network_name <- worker_info$network_name
  expect_true(!is.null(network_name))

  # Verify network exists
  networks <- system2(
    "docker",
    c(
      "network",
      "ls",
      "--filter",
      paste0("name=", network_name),
      "--format",
      "{{.Name}}"
    ),
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
    c(
      "network",
      "ls",
      "--filter",
      paste0("name=", network_name),
      "--format",
      "{{.Name}}"
    ),
    stdout = TRUE,
    stderr = FALSE
  )
  expect_false(network_name %in% networks)
})

test_that("Network isolation provides inter-container isolation", {
  skip_on_check()
  skip_on_ci_for_docker()

  # Skip if Docker is not available
  skip_if_not(repljail:::is_docker_available(), "Docker not available")

  # Set options to use only Docker with network isolation
  old_worker_type <- getOption("repljail.worker.type")
  old_network <- getOption("repljail.worker.docker.network.isolation")
  on.exit({
    options(repljail.worker.type = old_worker_type)
    options(repljail.worker.docker.network.isolation = old_network)
  })

  options(repljail.worker.type = "docker")
  options(repljail.worker.docker.network.isolation = TRUE)

  # Create a session with network isolation
  session <- RREPLSession$new(timeout = 30)
  on.exit(session$stop(timeout = 10), add = TRUE)

  # Verify session is alive
  expect_true(session$is_alive())

  # Verify the session can still execute code (host communication works via gateway)
  result <- session$execute("cat(2 + 2)", timeout = 5)
  expect_equal(result$status, "success")
  expect_equal(result$result$output, "4")

  # Verify that external internet access is blocked (--internal network with gateway sidecar)
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
      # Look up the IP for example.com using getaddrinfo (works in Docker)
      ip <- system("getent hosts example.com | awk \'{ print $1 }\' | head -1", intern = TRUE)
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

  # Test 4: Verify host communication still works via gateway
  result_gateway <- session$execute(
    '
    tryCatch({
      # The fact that we can execute code proves gateway communication works
      "GATEWAY_OK"
    }, error = function(e) "GATEWAY_FAILED")
  ',
    timeout = 10
  )
  expect_equal(result_gateway$status, "success")
  expect_equal(result_gateway$result$output, "[1] \"GATEWAY_OK\"\n")
})

test_that("Multiple Docker workers can run simultaneously with different ports", {
  skip_on_check()
  skip_on_ci_for_docker()
  skip_if_not(repljail::is_docker_available(), "Docker not available")

  # Set worker type to Docker
  old_worker_type <- getOption("repljail.worker.type")
  on.exit(options(repljail.worker.type = old_worker_type))
  options(repljail.worker.type = "docker")

  session1 <- RREPLSession$new(timeout = 20)
  session2 <- RREPLSession$new(timeout = 20)

  tryCatch(
    {
      # Verify both workers started
      expect_true(session1$is_alive())
      expect_true(session2$is_alive())
      expect_false(session1$port == session2$port) # Different ports

      # Test independent execution
      result1 <- session1$execute("x1 <- 100", timeout = 5)
      result2 <- session2$execute("x2 <- 200", timeout = 5)

      expect_equal(result1$status, "success")
      expect_equal(result2$status, "success")

      # Verify isolation - session1 shouldn't see x2
      result3 <- session1$execute("exists('x2')", timeout = 5)
      expect_equal(result3$status, "success")
      expect_true(any(grepl("FALSE", result3$result$output)))

      # Verify isolation - session2 shouldn't see x1
      result4 <- session2$execute("exists('x1')", timeout = 5)
      expect_equal(result4$status, "success")
      expect_true(any(grepl("FALSE", result4$result$output)))
    },
    finally = {
      session1$stop(timeout = 5)
      session2$stop(timeout = 5)
    }
  )
})

test_that("Docker worker startup handles port conflicts", {
  skip_on_check()
  skip_on_ci_for_docker()
  skip_if_not(repljail::is_docker_available(), "Docker not available")

  # Set worker type to Docker
  old_worker_type <- getOption("repljail.worker.type")
  on.exit(options(repljail.worker.type = old_worker_type))
  options(repljail.worker.type = "docker")

  # Start first session on specific port
  port1 <- repljail:::get_available_port()
  session1 <- RREPLSession$new(port = port1, timeout = 20)

  tryCatch(
    {
      expect_equal(session1$port, port1)
      expect_true(session1$is_alive())

      # Start second session without specifying port (should find different port)
      session2 <- RREPLSession$new(timeout = 20)

      tryCatch(
        {
          expect_true(session2$is_alive())
          expect_false(session1$port == session2$port)
        },
        finally = {
          session2$stop(timeout = 5)
        }
      )
    },
    finally = {
      session1$stop(timeout = 5)
    }
  )
})
