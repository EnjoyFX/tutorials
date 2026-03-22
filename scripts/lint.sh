#!/bin/sh
# Local lint script — mirrors CI checks.
# Install as pre-push hook:
#   ln -sf ../../scripts/lint.sh .git/hooks/pre-push
#
# Or run manually:
#   sh scripts/lint.sh
#
# Required tools (installed on demand via npx, or manually):
#   npm (for markdownlint-cli2 and cspell)
#   python3
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

run_npx() {
  label="$1"; pkg="$2"; shift 2
  printf "  %-30s" "$label"
  if ! command -v npx > /dev/null 2>&1; then
    echo "– (skip: npx not found)"
    SKIP=$((SKIP + 1))
    return 0
  fi
  if npx --yes "$pkg" "$@" > /tmp/lint_out 2>&1; then
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

run_npx "markdownlint"       markdownlint-cli2 "**/*.md" --config .markdownlint.json
run_npx "spellcheck (EN)"    cspell --config cspell.json --no-progress "en/**/*.md" "examples/**/*.md" "README.md"
run     "python syntax"      python3 -m py_compile examples/docker/app.py
run     "shellcheck"         shellcheck examples/k3s/deploy.sh
run     "helm lint"          helm lint examples/helm/myapp

echo "────────────────────────────────────────"
echo "  Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
echo ""

[ "$FAIL" -eq 0 ]
