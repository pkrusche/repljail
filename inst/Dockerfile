# Minimal Dockerfile for repljail worker containers
# Based on R 4.4 with security hardening
FROM rocker/r-ver:4.4

# Install minimal system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    gfortran \
    cmake \
    libcurl4-openssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set CRAN repository
RUN echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"))' >> /usr/local/lib/R/etc/Rprofile.site

# Install required R packages for worker
RUN Rscript -e \
    "install.packages(c('nanonext', 'evaluate', 'cli'), repos='https://cran.rstudio.com/', dependencies=TRUE)"

# Security hardening: create non-root user
RUN groupadd -r repljail && useradd -r -g repljail -m -d /home/repljail repljail

# Create working directory and set ownership
RUN mkdir -p /app && chown repljail:repljail /app
WORKDIR /app

# The actual worker.R will be mounted as a volume

# Switch to non-root user
USER repljail

# Set default command (will be overridden)
CMD ["Rscript", "--version"]
