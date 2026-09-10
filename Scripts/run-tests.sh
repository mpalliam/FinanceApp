#!/bin/bash
#
# Runs the test suite in batches, with a fresh simulator for each.
#
# Running all ~333 tests in one xcodebuild invocation is not reliable on this
# machine. Roughly forty minutes in, the simulator degrades: individual UI tests
# that normally take 15-30 seconds start taking 900+ and fail with "Timed out
# while synthesizing event". Three consecutive full runs each failed a different
# two or three tests, and every one of them passed when run alone.
#
# Splitting the run fixes that without touching a single assertion. The tests
# are exactly as strict as they were; they just get a simulator that is still
# healthy.
#
# Usage:  Scripts/run-tests.sh [derived-data-path] [log-path]
#
set -o pipefail

DEVICE="${DEVICE:-iPhone 17 Pro}"
PROJECT="FinanceNotebook.xcodeproj"
SCHEME="FinanceNotebook"
DERIVED="${1:-build/DerivedData}"
LOGS="${2:-build/test-logs}"

mkdir -p "$LOGS"

restart_simulator() {
    xcrun simctl shutdown all >/dev/null 2>&1
    sleep 2
    xcrun simctl boot "$DEVICE" >/dev/null 2>&1
    xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1
}

failed_batches=()
total_passed=0
total_failed=0

run_batch() {
    local name="$1"; shift
    local log="$LOGS/$name.log"

    echo "── $name"
    restart_simulator

    xcodebuild test-without-building \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS Simulator,name=$DEVICE" \
        -derivedDataPath "$DERIVED" \
        "$@" > "$log" 2>&1
    local status=$?

    local passed failed
    passed=$(grep -cE "Test Case .*passed" "$log")
    failed=$(grep -cE "Test Case .*failed" "$log")
    total_passed=$((total_passed + passed))
    total_failed=$((total_failed + failed))

    if [ "$status" -ne 0 ] || [ "$failed" -ne 0 ]; then
        failed_batches+=("$name")
        echo "   $passed passed, $failed failed"
        grep -E "Test Case .*failed" "$log" | sed 's/.*Tests\.//;s/\]//;s/^/     /'
    else
        echo "   $passed passed"
    fi
}

echo "Building for testing…"
xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$DERIVED" > "$LOGS/build.log" 2>&1
if [ $? -ne 0 ]; then
    echo "Build failed. See $LOGS/build.log"
    grep -E "error:" "$LOGS/build.log" | sort -u | head
    exit 1
fi

warnings=$(grep -E "warning:" "$LOGS/build.log" | grep -v appintentsmetadata | sort -u)
if [ -n "$warnings" ]; then
    echo "Build warnings:"
    echo "$warnings"
fi

# Unit tests are fast and do not drive the simulator UI, so they all go together.
run_batch "unit" -only-testing:FinanceNotebookTests

# UI suites are split so no simulator has to survive the whole run.
run_batch "ui-expenses" \
    -only-testing:FinanceNotebookUITests/ExpenseFlowUITests \
    -only-testing:FinanceNotebookUITests/MoneyAddedFlowUITests \
    -only-testing:FinanceNotebookUITests/UncategorizedFlowUITests

run_batch "ui-months" \
    -only-testing:FinanceNotebookUITests/MonthLifecycleUITests \
    -only-testing:FinanceNotebookUITests/PlanFlowUITests

run_batch "ui-review" \
    -only-testing:FinanceNotebookUITests/ReviewFlowUITests

# Report and Settings each drive the system share sheet and file importer, which
# are slow and leave the simulator in a heavier state, so they get their own.
run_batch "ui-report" \
    -only-testing:FinanceNotebookUITests/ReportFlowUITests

run_batch "ui-settings" \
    -only-testing:FinanceNotebookUITests/SettingsFlowUITests

echo
echo "────────────────────────────────"
echo "$total_passed passed, $total_failed failed"
if [ ${#failed_batches[@]} -ne 0 ]; then
    echo "Failing batches: ${failed_batches[*]}"
    exit 1
fi
echo "All batches green."
