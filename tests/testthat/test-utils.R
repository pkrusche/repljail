test_that("check_dependencies works", {
  expect_true(is.logical(check_dependencies()))
})

test_that("check_process_requirements works", {
  expect_true(is.logical(check_process_requirements()))
})