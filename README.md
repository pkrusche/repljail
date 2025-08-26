# replr

The goal of replr is to provide functions that make it easier to work with R in a REPL (Read-Eval-Print Loop) environment for use by AI tools, e.g. through an MCP server.

## Installation

You can install the development version of replr like so:

``` r
# install.packages("devtools")
devtools::install_github("pkrusche/replr")
```

## Development Environment

This repository includes a custom GitHub Copilot environment with R and all required packages pre-installed. The environment is configured using:

- **Dev Container**: `.devcontainer/` directory with Docker configuration
- **GitHub Codespaces**: Optimized settings for cloud development
- **Pre-installed packages**: All dependencies ready for immediate use

### Quick Start with Codespaces

1. Click "Code" → "Open with Codespaces" → "New codespace"
2. Wait for the environment to build (first time takes ~5-10 minutes)
3. Start developing with R and all dependencies ready!

### Local Development with Dev Containers

1. Install Docker and VS Code with Dev Containers extension
2. Clone this repository
3. Open in VS Code and select "Reopen in Container"
4. Environment will build automatically with all dependencies

The custom environment includes:
- R 4.3.2
- Required packages: `mirai`, `nanonext`, `processx`, `evaluate`, `R6`, `uuid`
- Development tools: `devtools`, `roxygen2`, `testthat`, `lintr`
- GitHub Copilot extensions enabled
