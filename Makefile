PYTHON ?= python3
PIP = $(PYTHON) -m pip

.DEFAULT_GOAL := help

.PHONY: help install lint test check hooks demo-build demo-run demo-stop

help:
	@printf "Available targets:\n"
	@printf "  install     Install Python dev dependencies\n"
	@printf "  lint        Run repository lint checks\n"
	@printf "  test        Run demo app tests\n"
	@printf "  check       Run lint and tests\n"
	@printf "  hooks       Install pre-commit hooks\n"
	@printf "  demo-build  Build the demo Docker image\n"
	@printf "  demo-run    Run the demo Docker image locally\n"
	@printf "  demo-stop   Stop running demo containers\n"

install:
	$(PIP) install -r requirements-dev.txt

lint:
	sh scripts/lint.sh

test:
	pytest

check: lint test

hooks:
	pre-commit install

demo-build:
	docker build -t myapp:latest examples/docker

demo-run:
	docker run --rm -p 8080:8080 myapp:latest

demo-stop:
	ids=$$(docker ps --filter ancestor=myapp:latest --quiet); \
	if [ -n "$$ids" ]; then docker stop $$ids; fi
