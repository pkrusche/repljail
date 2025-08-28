tryCatch(
  {
    library(replr)
  },
  error = function(e) {
    # Try to load all source files manually if replr package is not installed
    tryCatch({
      source("R/replr-package.R")
      source("R/debug.R")
      source("R/communication.R")
      source("R/utils.R") 
      source("R/session.R")
      source("R/ellmer-tools.R")
    }, error = function(e2) {
      # Skip loading if we can't load source files
      cat("Warning: Could not load replr package or source files:", e2$message, "\n")
    })
  }
)
