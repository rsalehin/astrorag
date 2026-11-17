#!/usr/bin/env bash
# =============================================================================
# scripts/doctor.sh — checks that this machine is ready for AstroRAG development.
#
# Run it from the repository root with:   make doctor
#
# Every check prints exactly one line:  ✓ (passed)  or  ✗ (failed) + a hint.
# The script does NOT stop at the first failure, so you see every problem at
# once. It exits with status 0 if all checks passed and 1 if any check failed,
# which lets other tools (CI, other scripts) react to the result.
# =============================================================================

# -u : treat an unset variable as an error (catches typos in variable names).
# We deliberately do NOT use -e: a failing check must not end the script.
set -u

# --- Settings (change these in one place) -------------------------------------
MIN_FREE_GB_ON_D=100                          # space to keep free on D: for images and data
MIN_MAX_MAP_COUNT=262144                      # Elasticsearch refuses to start below this
MAX_WSL_MEMORY_GB=40                          # the cap we set in %UserProfile%\.wslconfig
CUDA_TEST_IMAGE="nvidia/cuda:12.8.0-base-ubuntu24.04"
PORTS_THAT_MUST_BE_FREE=(5432 6379)           # PostgreSQL and Redis (used from AST-12)

# --- Output helpers ---------------------------------------------------------------
GREEN=$'\033[32m'
RED=$'\033[31m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

failures=0   # counts failed checks; decides the exit status at the end

# pass MESSAGE : print a green tick line.
pass() {
  printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"
}

# fail MESSAGE HINT : print a red cross line plus a hint, and count the failure.
fail() {
  printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"
  printf '      → %s\n' "$2"
  failures=$((failures + 1))
}

# section TITLE : print a bold heading to group related checks.
section() {
  printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
}

# check_command NAME HINT : pass if NAME is on the PATH, and show its version.
check_command() {
  local name="$1"
  local hint="$2"
  if command -v "$name" >/dev/null 2>&1; then
    # Some tools print several lines for --version; keep only the first one.
    local version
    version="$("$name" --version 2>&1 | head -n 1)"
    pass "$name found: $version"
  else
    fail "$name is not installed" "$hint"
  fi
}

# =============================================================================
section "1. Where am I running?"
# =============================================================================

# WSL kernels mention "microsoft" in /proc/version; a normal Linux machine does not.
if grep -qi microsoft /proc/version 2>/dev/null; then
  pass "Running inside WSL"
else
  fail "Not running inside WSL" \
       "Open the Ubuntu terminal (or VS Code connected to WSL) and run make doctor there."
fi

# Files under /mnt/c or /mnt/d live on Windows drives: slow for Linux tools and
# file watching (hot reload) is unreliable there. The repo must live in Linux.
repo_dir="$(pwd)"
if [[ "$repo_dir" == /mnt/* ]]; then
  fail "Repository is on a Windows drive ($repo_dir)" \
       "Clone it inside Linux instead, e.g. ~/code/astrorag."
else
  pass "Repository is on the Linux filesystem ($repo_dir)"
fi

# =============================================================================
section "2. Tools"
# =============================================================================

check_command git  "sudo apt install -y git"
check_command make "sudo apt install -y make"
check_command uv   "curl -LsSf https://astral.sh/uv/install.sh | sh   (then open a new terminal)"
check_command gh   "Install the GitHub CLI (see AST-7, part 4), then run: gh auth login"
check_command docker "Install Docker Desktop on Windows and enable WSL integration for Ubuntu."

# 'docker compose' is a sub-command, so check_command cannot test it.
if docker compose version >/dev/null 2>&1; then
  pass "docker compose found: $(docker compose version --short 2>/dev/null)"
else
  fail "docker compose is not available" \
       "Docker Desktop includes it; check Settings → Resources → WSL integration → Ubuntu."
fi

# Having the docker command is not enough: the Docker engine must be running.
docker_running=false
if docker info >/dev/null 2>&1; then
  docker_running=true
  pass "Docker engine is running"
else
  fail "Docker engine is not reachable" \
       "Start Docker Desktop on Windows and wait until it says 'Engine running'."
fi

# =============================================================================
section "3. GPU"
# =============================================================================

# Inside WSL, nvidia-smi comes from the Windows driver (do not install a Linux driver).
gpu_name=""
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1)"
fi
if [[ -n "$gpu_name" ]]; then
  pass "GPU visible in WSL: $gpu_name"
else
  fail "No GPU visible in WSL" \
       "Install/update the NVIDIA driver on Windows, then run 'wsl --shutdown' and reopen Ubuntu."
fi

# Containers need the GPU too (model server, Docling). Only test if Docker runs.
# The first run downloads the small CUDA test image; later runs are fast.
if [[ "$docker_running" == true ]]; then
  gpu_in_container="$(docker run --rm --gpus all "$CUDA_TEST_IMAGE" \
      nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1)"
  if [[ -n "$gpu_in_container" ]]; then
    pass "GPU visible inside Docker: $gpu_in_container"
  else
    fail "Docker containers cannot see the GPU" \
         "Update Docker Desktop and the NVIDIA driver; test with: docker run --rm --gpus all $CUDA_TEST_IMAGE nvidia-smi"
  fi
else
  fail "Skipped GPU-in-Docker check" "Fix the Docker engine check above first."
fi

# =============================================================================
section "4. System settings"
# =============================================================================

# Elasticsearch maps many files into memory and needs this kernel limit raised.
max_map_count="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if (( max_map_count >= MIN_MAX_MAP_COUNT )); then
  pass "vm.max_map_count is $max_map_count"
else
  fail "vm.max_map_count is $max_map_count (need ≥ $MIN_MAX_MAP_COUNT)" \
       "Add kernelCommandLine = sysctl.vm.max_map_count=$MIN_MAX_MAP_COUNT to .wslconfig, then 'wsl --shutdown'."
fi

# total memory as seen by WSL, in whole GB (column 2 of the 'Mem:' row)
total_mem_gb="$(free -g | awk '/^Mem:/ {print $2}')"
if (( total_mem_gb <= MAX_WSL_MEMORY_GB )); then
  pass "WSL memory is capped at about ${total_mem_gb} GB"
else
  fail "WSL can use ${total_mem_gb} GB (expected ≤ ${MAX_WSL_MEMORY_GB} GB)" \
       "Set memory=${MAX_WSL_MEMORY_GB}GB in %UserProfile%\\.wslconfig, then 'wsl --shutdown'."
fi

# Windows drive D: is mounted at /mnt/d inside WSL; check its free space.
if [[ -d /mnt/d ]]; then
  free_gb_on_d="$(df -BG --output=avail /mnt/d | tail -n 1 | tr -dc '0-9')"
  if (( free_gb_on_d >= MIN_FREE_GB_ON_D )); then
    pass "D: has ${free_gb_on_d} GB free"
  else
    fail "D: has only ${free_gb_on_d} GB free (want ≥ ${MIN_FREE_GB_ON_D} GB)" \
         "Free up space on D: — Docker images and data will need it."
  fi
else
  fail "Drive D: is not mounted at /mnt/d" "Check that D: exists in Windows and WSL automount is enabled."
fi

# =============================================================================
section "5. Ports"
# =============================================================================

# 'ss -ltn' lists TCP ports something is listening on; we need these ones free.
for port in "${PORTS_THAT_MUST_BE_FREE[@]}"; do
  if ss -ltn "sport = :$port" 2>/dev/null | grep -q LISTEN; then
    fail "Port $port is already in use" "Find the program with: sudo ss -ltnp 'sport = :$port'"
  else
    pass "Port $port is free"
  fi
done

# =============================================================================
section "Result"
# =============================================================================

if (( failures == 0 )); then
  printf '  %sAll checks passed — this machine is ready.%s\n\n' "$GREEN" "$RESET"
  exit 0
else
  printf '  %s%d check(s) failed.%s Fix them and run make doctor again.\n\n' "$RED" "$failures" "$RESET"
  exit 1
fi