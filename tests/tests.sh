#!/bin/bash
set -eo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DIR="$(cd "$TESTS_DIR/.." &> /dev/null && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0;0m'

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name passed"
    else
        echo -e "  ${RED}✗${NC} $test_name FAILED"
        echo -e "    Expected to find: '$needle'"
        echo -e "    But got: '$haystack'"
        exit 1
    fi
}

echo "========================================"
echo "Running llayer Unit & Integration Tests "
echo "========================================"

# -----------------------------------------------------------------
# 1. Testing ll-read
# -----------------------------------------------------------------
echo "Testing ll-read..."
READ_OUT=$(echo "Hello llayer" | "$DIR/ll-read")
assert_contains "$READ_OUT" '"type":"message"' "ll-read envelope creation"
assert_contains "$READ_OUT" '"text":"Hello llayer"' "ll-read payload injection"

# -----------------------------------------------------------------
# 2. Testing ll-context
# -----------------------------------------------------------------
echo "Testing ll-context..."
# Feed ll-context a raw stream of granular text chunks and tool results
MOCK_HISTORY=$(cat <<EOF
{"type":"message","source":"user","payload":{"text":"Hi"}}
{"type":"token","source":"assistant","payload":{"text":"Hello"}}
{"type":"token","source":"assistant","payload":{"text":" world!"}}
EOF
)
CONTEXT_OUT=$(echo "$MOCK_HISTORY" | "$DIR/ll-context")
assert_contains "$CONTEXT_OUT" '"role":"user"' "ll-context user mapping"
assert_contains "$CONTEXT_OUT" '"role":"assistant"' "ll-context token aggregation"
assert_contains "$CONTEXT_OUT" '"content":"Hello world!"' "ll-context string reduction"

# -----------------------------------------------------------------
# 3. Testing ll-dispatch
# -----------------------------------------------------------------
echo "Testing ll-dispatch..."

# Test Case A: No tool calls passed (should exit 0)
MOCK_NO_TOOL='{"type":"token","source":"assistant","payload":{"text":"Just saying hello."}}'
if echo "$MOCK_NO_TOOL" | "$DIR/ll-dispatch" > /dev/null; then
    echo -e "  ${GREEN}✓${NC} ll-dispatch passthrough (exit 0) passed"
else
    echo -e "  ${RED}✗${NC} ll-dispatch passthrough FAILED" && exit 1
fi

# Test Case B: Intercepting a tool call (should execute and exit 1)
# Note: Using set +e momentarily because a successful tool execution exits 1 by design
set +e
MOCK_TOOL_CALL='{"type":"tool_call","source":"assistant","payload":{"name":"fetch_url","arguments":{"url":"https://example.com"}}}'
DISPATCH_OUT=$(echo "$MOCK_TOOL_CALL" | "$DIR/ll-dispatch" 2>/dev/null)
DISPATCH_EXIT=$?
set -e

if [ "$DISPATCH_EXIT" -eq 1 ]; then
    echo -e "  ${GREEN}✓${NC} ll-dispatch loop signaling (exit 1) passed"
else
    echo -e "  ${RED}✗${NC} ll-dispatch loop signaling FAILED (Got exit $DISPATCH_EXIT)" && exit 1
fi
assert_contains "$DISPATCH_OUT" '"type":"tool_result"' "ll-dispatch output wrapping"
assert_contains "$DISPATCH_OUT" '"tool_name":"fetch_url"' "ll-dispatch tracking"

# -----------------------------------------------------------------
# 4. Testing ll-print
# -----------------------------------------------------------------
echo "Testing ll-print..."
MOCK_TOKENS=$(cat <<EOF
{"type":"token","source":"assistant","payload":{"text":"Deep"}}
{"type":"token","source":"assistant","payload":{"text":" thought."}}
EOF
)
PRINT_OUT=$(echo "$MOCK_TOKENS" | "$DIR/ll-print")
if [ "$PRINT_OUT" = "Deep thought." ]; then
     echo -e "  ${GREEN}✓${NC} ll-print token extraction passed"
else
     echo -e "  ${RED}✗${NC} ll-print token extraction FAILED (Got: '$PRINT_OUT')" && exit 1
fi

# -----------------------------------------------------------------
# 5. Testing ll-eval (Dry Run Validation)
# -----------------------------------------------------------------
echo "Testing ll-eval parameters..."
# Verify that ll-eval validates input stream presence even if server is offline
set +e
EVAL_OUT=$(echo "[]" | "$DIR/ll-eval" --invalid-flag 2>&1)
set -e
assert_contains "$EVAL_OUT" "Unknown option" "ll-eval error handling/argument parsing"

echo "========================================"
echo -e "${GREEN}ALL TESTS PASSED SUCCESSFULLY${NC}"
echo "========================================"
