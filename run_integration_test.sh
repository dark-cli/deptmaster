#!/bin/bash
# Wrapper script to run integration tests with database flash
# This ensures the database is always reset before running tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse flags
MANAGE_FLAGS=()
TEST_ARGS=()
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-build|--skip-build)
            MANAGE_FLAGS+=("$1")
            SKIP_BUILD=true
            shift
            ;;
        --verbose|-v)
            MANAGE_FLAGS+=("$1")
            shift
            ;;
        *)
            TEST_ARGS+=("$1")
            shift
            ;;
    esac
done

# Default test file (first non-flag argument or default)
TEST_FILE="${TEST_ARGS[0]:-integration_test/ui_integration_test.dart}"

# Support test name shortcuts
case "$TEST_FILE" in
  "stress"|"stress_test")
    TEST_FILE="integration_test/stress_test.dart"
    ;;
  "comprehensive"|"comprehensive_stress")
    TEST_FILE="integration_test/comprehensive_stress_test.dart"
    ;;
  "ui"|"ui_test")
    TEST_FILE="integration_test/ui_integration_test.dart"
    ;;
esac

# Build manage.sh command with flags
MANAGE_CMD="./manage.sh"
if [ ${#MANAGE_FLAGS[@]} -gt 0 ]; then
    MANAGE_CMD="$MANAGE_CMD ${MANAGE_FLAGS[*]}"
fi

echo "🔄 Running full-flash before tests..."
if [ "$SKIP_BUILD" = true ]; then
    echo "   (Skipping server build for faster execution)"
fi
$MANAGE_CMD full-flash

echo ""
echo "🧪 Running integration test: $TEST_FILE"
cd mobile
/home/max/flutter/bin/flutter test "$TEST_FILE" -d R5CXB1BJ9RN "${TEST_ARGS[@]:1}"
