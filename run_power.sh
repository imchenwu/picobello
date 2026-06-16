#!/usr/bin/env bash
# Copyright (c) 2025 ETH Zurich.
# Power analysis automation script for Picobello SoC.
# Usage: ./run_power.sh <tile_name> <fusion_run_name>

set -euo pipefail

# --- Input validation ---
if [ $# -ne 2 ]; then
    echo "Usage: $0 <tile_name> <fusion_run_name>"
    echo "  tile_name:      cluster_tile or cluster_tileTMR"
    echo "  fusion_run_name: fusion run name (e.g. cluster_tile_noungroup)"
    exit 1
fi

TILE_NAME="$1"
FUSION_RUN="$2"

if [ "$TILE_NAME" != "cluster_tile" ] && [ "$TILE_NAME" != "cluster_tileTMR" ]; then
    echo "Error: tile_name must be 'cluster_tile' or 'cluster_tileTMR', got '$TILE_NAME'"
    exit 1
fi

# Map tile name to NETLISTS and optional TMR flag
if [ "$FUSION_RUN" = "cluster_tileTMR_state" ]; then
    MAKE_TILE_ARGS="NETLISTS=cluster_tile TMR=state"
    echo "success!"
elif [ "$TILE_NAME" = "cluster_tileTMR" ]; then
    MAKE_TILE_ARGS="NETLISTS=cluster_tile TMR=full"
else
    MAKE_TILE_ARGS="NETLISTS=cluster_tile"
fi

echo "=== Power Analysis: tile=$TILE_NAME fusion_run=$FUSION_RUN ==="

# --- Step 1: Clean (twice) ---
echo "[1/5] Cleaning chip simulation (first pass)..."
make vsim-clean-chip
echo "[1/5] Cleaning chip simulation (second pass)..."
make vsim-clean-chip

# --- Step 2: Compile ---
echo "[2/5] Compiling with netlists ($MAKE_TILE_ARGS, FUSION_RUN=$FUSION_RUN, VCD=ON)..."
make vsim-compile-chip $MAKE_TILE_ARGS FUSION_RUN="$FUSION_RUN" VCD=ON

# --- Step 3: VCD dump simulation ---
echo "[3/5] Running VCD dump simulation..."
make vsim-run-batch-chip \
    PRELMODE=3 \
    CHS_BINARY=sw/cheshire/tests/simple_offload.spm.elf \
    SN_BINARY=sw/snitch/apps/gemm_2d/build/gemm_2d.elf \
    VCD=ON VCD_START=366873ns VCD_DURATION=310ns

# # --- Step 4: Verify results ---
# echo "[4/5] Verifying simulation results..."
# SNITCH_PATH=$(bender path snitch_cluster)
# VERIFY_SCRIPT="${SNITCH_PATH}/sw/kernels/blas/gemm/scripts/verify.py"

# # Remove stale results.csv if present
# rm -f results.csv

# "$VERIFY_SCRIPT" placeholder \
#     sw/snitch/apps/gemm_2d/build/gemm_2d.elf \
#     --no-ipc --memdump l2mem.bin --memaddr 0x70000000

# if [ -s results.csv ]; then
#     echo "Error: Verification failed — wrong results written to results.csv"
#     exit 1
# fi
# echo "Verification passed."

# --- Step 5: Run PrimeTime power analysis ---
echo "[5/5] Running PrimeTime power analysis..."
cd pd/tsmc7/primetime
primetime-2022.03 pt_shell -x "set RUN_NAME $FUSION_RUN; source power.tcl; exit"

echo "=== Power analysis complete ==="
