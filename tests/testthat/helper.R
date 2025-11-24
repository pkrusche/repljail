tryCatch(
  {
    library(repljail)
  },
  error = function(e) {
    # Try to load all source files manually if repljail package is not installed
    tryCatch(
      {
        devtools::load_all()
      },
      error = function(e2) {
        # Skip loading if we can't load source files
        cat(
          "Warning: Could not load repljail package or source files:",
          e2$message,
          "\n"
        )
      }
    )
  }
)

is_checking <- function() {
  nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")) ||
    nzchar(Sys.getenv("_R_CHECK_TIMINGS_"))
}

# Skip tests during R CMD check (but allow them in CI with NOT_CRAN=true)
# IPC sockets may not work reliably in the restricted check environment
skip_on_check <- function() {
  if (is_checking()) {
    testthat::skip("Skipping long test during R CMD check")
  }
  invisible()
}
