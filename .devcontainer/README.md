# Custom GitHub Copilot Environment for repljail

This directory contains configuration files to set up a custom development environment for GitHub Copilot agents working with the `repljail` R package.

## Overview

The custom environment ensures that:
- R (version 4.3.2) is pre-installed
- All required R packages are available
- Development tools are ready to use
- GitHub Copilot extensions are enabled

## Files

### `devcontainer.json`
Main configuration file that defines:
- Base Docker image built from the Dockerfile
- VS Code extensions (R support, GitHub Copilot)
- Post-creation commands to verify setup
- User configuration

### `Dockerfile`
Builds a custom container with:
- R 4.3.2 base image (rocker/r-ver)
- System dependencies for R package compilation
- Pre-installed required packages:
  - `nanonext` - NNG (nanomsg) messaging library
  - `processx` - Process spawning and management
  - `evaluate` - Safe evaluation of R expressions
  - `R6` - Encapsulated object-oriented programming
  - `uuid` - UUID generation
- Pre-installed suggested packages:
  - `pryr` - Memory usage monitoring
  - `testthat` - Unit testing framework
- Development tools:
  - `devtools` - Package development tools
  - `roxygen2` - Documentation generation
  - `pkgdown` - Website generation
  - `lintr` - Code linting

## Usage

When you open this repository in GitHub Codespaces or a VS Code dev container, the environment will automatically:

1. Build the custom Docker image with all dependencies
2. Install VS Code extensions for R development and GitHub Copilot
3. Verify that all required packages are correctly installed
4. Set up the workspace for immediate development

## Benefits for GitHub Copilot

This pre-configured environment allows GitHub Copilot to:
- Understand package dependencies and suggest appropriate code
- Work with R-specific syntax and idioms effectively
- Access documentation and examples for installed packages
- Provide contextually relevant suggestions for the repljail package

## Verification

After the container starts, the environment will automatically run a comprehensive test via `test-environment.R`. You can also manually verify the setup:

```bash
# Run the full environment test
Rscript .devcontainer/test-environment.R

# Check R version
R --version

# Verify required packages
Rscript -e "required <- c('nanonext', 'processx', 'evaluate', 'R6', 'uuid'); sapply(required, function(x) cat(x, ':', as.character(packageVersion(x)), '\n'))"

# Load the repljail package in development mode
Rscript -e "devtools::load_all(); repljail::check_dependencies()"
```

## Troubleshooting

If packages are missing or there are installation issues:

1. Rebuild the container: Command Palette → "Dev Containers: Rebuild Container"
2. Check the build logs for specific error messages
3. Verify system dependencies are correctly installed
4. Ensure CRAN mirrors are accessible

## Maintenance

To update package versions:
1. Modify the `Dockerfile` to specify new versions
2. Update the verification commands in `devcontainer.json`
3. Test the build locally before committing changes
