#!/bin/bash

# Quick start script for SMT Round-Robin Prefetch Testing
# This script builds and runs the round-robin prefetch test with default settings

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "SMT Round-Robin Prefetch Test - Quick Start"
echo "=============================================="
echo ""

# Configuration
MAX_CYCLES=${1:-2000}
DEBUG=${2:-0}

echo "Configuration:"
echo "  Working Directory: $SCRIPT_DIR"
echo "  Max Test Cycles: $MAX_CYCLES"
echo "  Debug Output: $([ $DEBUG -eq 1 ] && echo 'ON' || echo 'OFF')"
echo ""

# Check if makefile exists
if [ ! -f "Makefile.TestSMT_RoundRobinPrefetch.mk" ]; then
    echo "[ERROR] Makefile.TestSMT_RoundRobinPrefetch.mk not found!"
    echo "Make sure you're in the correct directory: $SCRIPT_DIR"
    exit 1
fi

# Build
echo "[1/2] Building TestSMT_RoundRobinPrefetch..."
make -f Makefile.TestSMT_RoundRobinPrefetch.mk \
    MAX_TEST_CYCLES=$MAX_CYCLES \
    build

if [ $? -ne 0 ]; then
    echo "[ERROR] Build failed!"
    exit 1
fi

echo "[✓] Build successful"
echo ""

# Run
echo "[2/2] Running TestSMT_RoundRobinPrefetch..."
make -f Makefile.TestSMT_RoundRobinPrefetch.mk \
    MAX_TEST_CYCLES=$MAX_CYCLES \
    SHOW_PREFETCH_DEBUG=$DEBUG \
    run

if [ $? -ne 0 ]; then
    echo "[ERROR] Test failed!"
    exit 1
fi

echo ""
echo "[✓] Test completed successfully!"
echo ""

# Check for report
REPORT="Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt"
if [ -f "$REPORT" ]; then
    echo "Test Report: $REPORT"
    echo ""
    echo "=== Test Summary ==="
    grep -A 10 "Test Summary" "$REPORT" || true
    echo ""
fi

echo "=============================================="
echo "For more options, run:"
echo "  make -f Makefile.TestSMT_RoundRobinPrefetch.mk help"
echo "=============================================="
