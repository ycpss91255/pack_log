#!/bin/bash
# Creates realistic log file structures on the remote (sshd) host.
# Piped via SSH: ssh testuser@sshd bash -s < test/setup_remote_logs.sh
set -euo pipefail

BASE="${HOME}/ros-docker/AMR/myuser"

# Create directory structure
mkdir -p "${BASE}/log_core"
mkdir -p "${BASE}/log_data/lidar_detection"
mkdir -p "${BASE}/log_data/lidar_detection/glog"
mkdir -p "${BASE}/log_slam"
mkdir -p "${BASE}/core_storage"

HOSTNAME_VAL=$(hostname)
USER_VAL=$(whoami)

# corenavi_auto logs (date format: %Y%m%d-%H%M%S)
echo "core log 1" > "${BASE}/log_core/corenavi_auto.${HOSTNAME_VAL}.${USER_VAL}.log.INFO.20260115-100000.1"
echo "core log 2" > "${BASE}/log_core/corenavi_auto.${HOSTNAME_VAL}.${USER_VAL}.log.INFO.20260115-140000.2"
echo "core log 3" > "${BASE}/log_core/corenavi_auto.${HOSTNAME_VAL}.${USER_VAL}.log.INFO.20260116-080000.3"

# detect_shelf .dat files (date format: %Y%m%d%H%M%S)
echo "dat 1" > "${BASE}/log_data/lidar_detection/detect_shelf_node-DetectShelf_20260115100000_001.dat"
echo "dat 2" > "${BASE}/log_data/lidar_detection/detect_shelf_node-DetectShelf_20260115160000_002.dat"
echo "dat 3" > "${BASE}/log_data/lidar_detection/detect_shelf_node-DetectShelf_20260116120000_003.dat"

# detect_shelf .pcd files (date format: %Y%m%d%H%M%S)
echo "pcd 1" > "${BASE}/log_data/lidar_detection/detect_shelf_20260115100000_001.pcd"
echo "pcd 2" > "${BASE}/log_data/lidar_detection/detect_shelf_20260115160000_002.pcd"

# glog files (date format: %Y%m%d-%H%M%S)
echo "glog 1" > "${BASE}/log_data/lidar_detection/glog/detect_shelf_node-DetectShelf-20260115-100000.log"
echo "glog 2" > "${BASE}/log_data/lidar_detection/glog/detect_shelf_node-DetectShelf-20260115-160000.log"

# epoch-based slam logs (date format: %s)
EPOCH_IN=$(date -d "2026-01-15 12:00:00" "+%s" 2>/dev/null || echo "1768507200")
EPOCH_OUT=$(date -d "2026-01-16 12:00:00" "+%s" 2>/dev/null || echo "1768593600")
echo "slam in"  > "${BASE}/log_slam/coreslam_2D_${EPOCH_IN}.log"
echo "slam out" > "${BASE}/log_slam/coreslam_2D_${EPOCH_OUT}.log"

# coreslam_2D record files (date format: %Y-%m-%d-%H-%M-%S)
mkdir -p "${BASE}/log_slam/record"
echo "rec in"  > "${BASE}/log_slam/record/coreslam_2D_2026-01-15-12-00-00.rec"
echo "rec out" > "${BASE}/log_slam/record/coreslam_2D_2026-01-16-12-00-00.rec"

# Old files only (all before any reasonable query range) for boundary tests
mkdir -p "${BASE}/log_old"
echo "old 1" > "${BASE}/log_old/app_20250101100000.log"
echo "old 2" > "${BASE}/log_old/app_20250101120000.log"

# Config files (no date token - direct pass)
echo "node_config: test" > "${BASE}/core_storage/node_config.yaml"
echo "[shelf]"           > "${BASE}/core_storage/shelf.ini"
echo "<launch>"          > "${BASE}/core_storage/external_param.launch"
echo "run_config: test"  > "${BASE}/core_storage/run_config.yaml"

# Symlink test data
ln -sf "${BASE}/core_storage/node_config.yaml" "${BASE}/core_storage/link_config.yaml"

# Symlink directory (simulates mapfile/default -> mapfile/)
mkdir -p "${BASE}/core_storage/mapfile"
echo "map data" > "${BASE}/core_storage/mapfile/uimap.png"
echo "map yaml" > "${BASE}/core_storage/mapfile/uimap.yaml"
ln -sf "${BASE}/core_storage/mapfile" "${BASE}/core_storage/default"

# AvoidStop cross-date folders
mkdir -p "${BASE}/log/AvoidStop_2026-01-15"
mkdir -p "${BASE}/log/AvoidStop_2026-01-16"
echo "avoid 15" > "${BASE}/log/AvoidStop_2026-01-15/2026-01-15-10.00.00_111_avoid.png"
echo "avoid 15b" > "${BASE}/log/AvoidStop_2026-01-15/2026-01-15-14.00.00_222_avoid.png"
echo "avoid 16" > "${BASE}/log/AvoidStop_2026-01-16/2026-01-16-09.00.00_333_avoid.png"

echo "Remote log setup complete: $(find "${BASE}" \( -type f -o -type l \) | wc -l) files created."
