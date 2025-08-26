# Use the official Rocker R image as base
FROM rocker/r-ver:4.3.2

# Install system dependencies required for R packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
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
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages for replr
RUN Rscript -e "install.packages(c('mirai', 'nanonext', 'processx', 'evaluate', 'R6', 'uuid'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Install suggested R packages  
RUN Rscript -e "install.packages(c('pryr', 'testthat'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Install R development tools
RUN Rscript -e "install.packages(c('devtools', 'roxygen2', 'pkgdown', 'lintr', 'remotes'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Create rstudio user if it doesn't exist
RUN if ! id -u rstudio > /dev/null 2>&1; then \
    useradd -m -s /bin/bash rstudio && \
    echo "rstudio:rstudio" | chpasswd && \
    usermod -aG sudo rstudio; \
    fi

# Verify installation by checking package versions
RUN Rscript -e "cat('Required packages installed:\\n'); \
    required <- c('mirai', 'nanonext', 'processx', 'evaluate', 'R6', 'uuid'); \
    sapply(required, function(x) { \
        if(requireNamespace(x, quietly=TRUE)) { \
            cat(x, ':', as.character(packageVersion(x)), '\\n') \
        } else { \
            stop('Package ', x, ' not found') \
        } \
    })"

# Set working directory
WORKDIR /workspaces/replr

# Switch to rstudio user
USER rstudio

# Set default command
CMD ["/bin/bash"]