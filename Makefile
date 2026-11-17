# =============================================================================
# Makefile — short, memorable commands for everyday tasks.
#
# Usage:  make <target>      e.g.  make doctor
# Run "make" or "make help" to list all targets.
#
# IMPORTANT: every command line under a target must start with a TAB,
# not spaces. (.editorconfig makes VS Code do this for you.)
# =============================================================================

# Running plain "make" shows the help instead of running the first target.
.DEFAULT_GOAL := help

# These targets are commands, not files; .PHONY stops make from
# getting confused if a file with the same name ever exists.
.PHONY: help doctor

help: ## Show the available commands
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  %-10s %s\n", $$1, $$2}'

doctor: ## Check that this machine is ready for AstroRAG development
	@bash scripts/doctor.sh