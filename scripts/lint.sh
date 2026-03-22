#!/bin/sh
# Local lint script — mirrors CI checks.
# Install as pre-push hook:
#   ln -sf ../../scripts/lint.sh .git/hooks/pre-push
#
# Or run manually:
#   sh scripts/lint.sh
#
# Required tools:
#   python3
#   pymarkdownlnt — pip install -r requirements-dev.txt
#   codespell    — pip install -r requirements-dev.txt
#   shellcheck   — brew install shellcheck
#   helm         — https://helm.sh/docs/intro/install/

set -e

PASS=0
FAIL=0
SKIP=0

run() {
  label="$1"; cmd="$2"; shift 2
  printf "  %-30s" "$label"
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "– (skip: $cmd not found)"
    SKIP=$((SKIP + 1))
    return 0
  fi
  if "$cmd" "$@" > /tmp/lint_out 2>&1; then
    echo "✓"
    PASS=$((PASS + 1))
  else
    echo "✗"
    cat /tmp/lint_out
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "Running lint checks..."
echo "────────────────────────────────────────"

run     "markdown lint"      pymarkdownlnt --config .pymarkdown.json scan .
run     "spellcheck (EN)"    codespell --config .codespellrc en README.md examples
run     "python syntax"      python3 -m py_compile examples/docker/app.py
run     "shellcheck"         shellcheck examples/k3s/deploy.sh
run     "helm lint"          helm lint examples/helm/myapp

echo "────────────────────────────────────────"
echo "  Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
echo ""

[ "$FAIL" -eq 0 ]
