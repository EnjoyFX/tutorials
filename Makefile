.DEFAULT_GOAL := help

.PHONY: help install lint test check hooks demo-build demo-run demo-stop

UV_CACHE_DIR ?= .uv-cache
export UV_CACHE_DIR

help:
	@printf "Available targets:\n"
	@printf "  install     Sync Python dev dependencies (uv sync)\n"
	@printf "  lint        Run repository lint checks\n"
	@printf "  test        Run demo app tests\n"
	@printf "  check       Run lint and tests\n"
	@printf "  hooks       Install pre-commit hooks\n"
	@printf "  demo-build  Build the demo Docker image\n"
	@printf "  demo-run    Run the demo Docker image locally\n"
	@printf "  demo-stop   Stop running demo containers\n"

install:
	uv sync

lint:
	sh scripts/lint.sh

test:
	uv run pytest

check: lint test

hooks:
	pre-commit install

demo-build:
	docker build -t myapp:local examples/docker

demo-run:
	docker run --rm -p 8080:8080 myapp:local

demo-stop:
	ids=$$(docker ps --filter ancestor=myapp:local --quiet); \
	if [ -n "$$ids" ]; then docker stop $$ids; fi
