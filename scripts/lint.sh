#!/bin/sh
# Local lint script — runs the repository checks that can be run on this host.
# Install as pre-push hook:
#   ln -sf ../../scripts/lint.sh .git/hooks/pre-push
#
# Or run manually:
#   sh scripts/lint.sh
#
# Required tools:
#   uv          — Python dev deps run via `uv run` (auto-syncs from pyproject.toml)
#   helm        — https://helm.sh/docs/intro/install/
# Optional tools:
#   ShellCheck  — brew install shellcheck
#   hadolint    — brew install hadolint
#   lychee      — brew install lychee
#   docker      — used for the demo image smoke test when the daemon is available

set -e

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"

PASS=0
FAIL=0
SKIP=0
LINT_OUT="$(mktemp "${TMPDIR:-/tmp}/k3s-learn-lint.XXXXXX")"

cleanup() {
  rm -f "$LINT_OUT"
}
trap cleanup EXIT

run_check() {
  mode="$1"; label="$2"; cmd="$3"; shift 3
  printf "  %-30s" "$label"
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "- (skip: $cmd not found)"
    SKIP=$((SKIP + 1))
    return 0
  fi
  if "$cmd" "$@" > "$LINT_OUT" 2>&1; then
    echo "✓"
    PASS=$((PASS + 1))
  else
    status=$?
    if [ "$mode" = "optional" ] && [ "$status" -eq 77 ]; then
      printf -- "- (skip: "
      tr '\n' ' ' < "$LINT_OUT"
      echo ")"
      SKIP=$((SKIP + 1))
      return 0
    fi
    echo "x"
    cat "$LINT_OUT"
    FAIL=$((FAIL + 1))
  fi
}

run_required() {
  run_check required "$@"
}

run_optional() {
  run_check optional "$@"
}

docker_smoke() {
  if ! command -v curl > /dev/null 2>&1; then
    echo "curl not found"
    return 77
  fi
  if ! docker info > /dev/null 2>&1; then
    echo "Docker daemon unavailable"
    return 77
  fi

  image="myapp:lint"
  docker build -t "$image" examples/docker
  container="$(docker run -d -p 127.0.0.1::8080 "$image")"

  docker_cleanup() {
    docker rm -f "$container" > /dev/null 2>&1 || true
  }

  port="$(docker port "$container" 8080/tcp | awk -F: 'NR == 1 {print $NF}')"
  if [ -z "$port" ]; then
    docker logs "$container" || true
    docker_cleanup
    return 1
  fi

  for _ in 1 2 3 4 5; do
    if curl -fsS "http://127.0.0.1:$port/health" > /dev/null; then
      docker_cleanup
      return 0
    fi
    sleep 1
  done

  docker logs "$container" || true
  docker_cleanup
  return 1
}

echo ""
echo "Running lint checks..."
echo "────────────────────────────────────────"

run_required "markdown lint"      uv run pymarkdownlnt --config .pymarkdown.json scan .
run_required "spellcheck (EN)"    uv run codespell --config .codespellrc en README.md examples
run_required "python syntax"      uv run python -m py_compile examples/docker/app.py
run_required "pytest"             uv run pytest tests/ -q
run_required "helm lint"          helm lint examples/helm/myapp
run_required "helm template"       helm template myapp examples/helm/myapp --namespace demo
run_optional "shellcheck"          shellcheck examples/k3s/deploy.sh
run_optional "hadolint"            hadolint examples/docker/Dockerfile
run_optional "links check"         lychee --config .lychee.toml --verbose README.md en/*.md ua/*.md examples/*.md
run_optional "docker smoke"        docker_smoke

echo "────────────────────────────────────────"
echo "  Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
echo ""

[ "$FAIL" -eq 0 ]
