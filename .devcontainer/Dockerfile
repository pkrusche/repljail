# Use the official Rocker R image as base
FROM rocker/r-ver:4.4

# Install system dependencies required for R packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    libcurl4-openssl-dev \ libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgit2-dev \
    libssh2-1-dev \
    cmake \
    libmagick++-dev \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Set CRAN repository to improve package installation reliability
RUN echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"))' >> /usr/local/lib/R/etc/Rprofile.site

# Install required R packages for replr in order of dependency complexity
RUN Rscript -e "install.packages('R6', repos='https://cran.rstudio.com/', dependencies=TRUE)"
RUN Rscript -e "install.packages('uuid', repos='https://cran.rstudio.com/', dependencies=TRUE)" 
RUN Rscript -e "install.packages('processx', repos='https://cran.rstudio.com/', dependencies=TRUE)"
RUN Rscript -e "install.packages('evaluate', repos='https://cran.rstudio.com/', dependencies=TRUE)"
RUN Rscript -e "install.packages('nanonext', repos='https://cran.rstudio.com/', dependencies=TRUE)"
RUN Rscript -e "install.packages('mirai', repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Install suggested R packages  
RUN Rscript -e "install.packages(c('pryr', 'testthat'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Install R development tools
RUN Rscript -e "install.packages(c('devtools', 'roxygen2', 'pkgdown', 'lintr', 'remotes', 'here', 'mirai', 'languageserver', 'httpgd', 'png'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Verify installation by checking package versions
RUN Rscript -e "cat('Required packages installed:\\n'); \
    required <- c('here', 'mirai', 'nanonext', 'processx', 'evaluate', 'R6', 'uuid'); \
    sapply(required, function(x) { \
        if(requireNamespace(x, quietly=TRUE)) { \
            cat(x, ':', as.character(packageVersion(x)), '\\n') \
        } else { \
            stop('Package ', x, ' not found') \
        } \
    })"

# Set working directory
WORKDIR /workspaces/replr

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD Rscript -e "stopifnot(requireNamespace('nanonext', quietly=TRUE))" || exit 1

# Set default command
CMD ["/bin/bash"]