tryCatch(
  {
    library(replr)
  },
  error = function(e) {
    devtools::load_all()
  }
)
