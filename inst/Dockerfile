# Minimal Dockerfile for replr worker containers
# Based on R 4.4 with security hardening
FROM rocker/r-ver:4.4

# Install minimal system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set CRAN repository
RUN echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"))' >> /usr/local/lib/R/etc/Rprofile.site

# Install required R packages for worker
RUN Rscript -e "install.packages(c('nanonext', 'evaluate', 'cli'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Security hardening: create non-root user
RUN groupadd -r replr && useradd -r -g replr -m -d /home/replr replr

# Create working directory and set ownership
RUN mkdir -p /app && chown replr:replr /app
WORKDIR /app

# Copy worker script (will be mounted at runtime)
# The actual worker.R will be mounted as a volume

# Switch to non-root user
USER replr

# Set default command (will be overridden)
CMD ["Rscript", "--version"]