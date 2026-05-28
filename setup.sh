#!/usr/bin/env bash
# =============================================================================
#  setup.sh — BharatTruck / LogisticOS  one-time workspace setup
#
#  Run this once after cloning the LogisticOS repo:
#
#    git clone git@github.com:deltaos1997/LogisticOS.git
#    cd LogisticOS
#    ./setup.sh
#
# =============================================================================

# ── Safety flags ──────────────────────────────────────────────────────────────
# -e  : exit immediately if any command fails
# -u  : treat unset variables as errors
# -o pipefail : a pipe fails if ANY command in it fails (not just the last one)
set -euo pipefail

# ── Resolve the workspace directory ───────────────────────────────────────────
# BASH_SOURCE[0] is the path to this script file itself.
# dirname strips the filename, leaving the directory.
# cd + pwd resolves any symlinks and gives us a clean absolute path.
# This means the script works correctly no matter where you call it from.
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── ANSI color codes ───────────────────────────────────────────────────────────
# These are escape sequences that terminals interpret as colors.
# \033[  → start of escape sequence
# 0m     → reset all formatting
# 32m    → green text
# 33m    → yellow text
# 31m    → red text
# 36m    → cyan text
# 1m     → bold
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"

# ── Helper print functions ─────────────────────────────────────────────────────
info()    { printf "  ${CYAN}→${RESET}  %s\n" "$*"; }
success() { printf "  ${GREEN}✓${RESET}  %s\n" "$*"; }
warn()    { printf "  ${YELLOW}⚠${RESET}  %s\n" "$*"; }
skip()    { printf "  ${YELLOW}–${RESET}  %s\n" "$*"; }
fail()    { printf "  ${RED}✗${RESET}  %s\n" "$*"; }

# ── Repo list ──────────────────────────────────────────────────────────────────
# Format: "local-folder-name|git-ssh-url"
# The pipe character | is used as a separator so we can store both pieces
# of info in a single array entry and split them later with ${var%%|*} / ${var##*|}
#
# Why SSH and not HTTPS?
# SSH uses your local key pair for auth — no password prompts.
# HTTPS requires a Personal Access Token stored somewhere.
# For a dev team, SSH is cleaner.
REPOS=(
  "bt-gateway|git@github.com:deltaos1997/bt-gateway.git"
  "bt-auth-service|git@github.com:deltaos1997/bt-auth-service.git"
  "bt-booking-service|git@github.com:deltaos1997/bt-booking-service.git"
  "bt-pricing-service|git@github.com:deltaos1997/bt-pricing-service.git"
  "bt-payment-service|git@github.com:deltaos1997/bt-payment-service.git"
  "bt-cargo-ledger|git@github.com:deltaos1997/bt-cargo-ledger.git"
  "bt-ops-web|git@github.com:deltaos1997/bt-ops-web.git"
  "bt-driver-app|git@github.com:deltaos1997/bt-driver-app.git"
  "bt-shipper-app|git@github.com:deltaos1997/bt-shipper-app.git"
)

# ── Banner ─────────────────────────────────────────────────────────────────────
printf "\n${BOLD}BharatTruck / LogisticOS — Workspace Setup${RESET}\n"
printf "Workspace root: ${CYAN}%s${RESET}\n" "$WORKSPACE"
printf -- "──────────────────────────────────────────────────────────\n\n"

# ── Clone repos ────────────────────────────────────────────────────────────────
# We loop over every entry in the REPOS array.
#
# "${REPOS[@]}"  →  expands the entire array, one element per word
# The quotes are important: without them, spaces in repo names would break things.
#
# ${entry%%|*}  →  strips everything from the FIRST | to the end  → gives the folder name
# ${entry##*|}  →  strips everything from the start to the LAST | → gives the git URL
printf "${BOLD}Cloning service repositories...${RESET}\n\n"

FAILED=()   # we'll collect any repos that fail to clone here

for entry in "${REPOS[@]}"; do
  folder="${entry%%|*}"
  url="${entry##*|}"
  target="$WORKSPACE/$folder"

  # Check if the folder already contains a git repo.
  # We look for the .git directory specifically — just having a folder isn't enough.
  if [ -d "$target/.git" ]; then
    skip "$folder  (already cloned — skipping)"
    continue   # 'continue' skips the rest of this loop iteration and goes to the next repo
  fi

  info "Cloning $folder ..."

  # 'git clone <url> <destination>' clones into the given path.
  # We suppress git's default output with -q (quiet) for cleaner terminal output.
  # The || block runs only if git clone FAILS (repo not on GitHub yet, no SSH access, etc.)
  # Without set -e catching it here, we catch the failure ourselves and store it in FAILED.
  if git clone -q "$url" "$target" 2>/dev/null; then
    success "$folder"
  else
    fail "$folder  — could not clone (repo may not exist on GitHub yet or you lack SSH access)"
    FAILED+=("$folder")   # append to array
  fi
done

# ── Make bt executable ─────────────────────────────────────────────────────────
# When git clones a repo, file permissions are set based on the repo's stored mode.
# If bt was committed without execute permission, './bt' would fail with "Permission denied".
# chmod +x explicitly adds the execute bit so any user on the system can run it.
printf "\n${BOLD}Configuring tools...${RESET}\n\n"
chmod +x "$WORKSPACE/bt"
success "bt CLI is executable"

# ── Summary ────────────────────────────────────────────────────────────────────
printf "\n──────────────────────────────────────────────────────────\n"

if [ ${#FAILED[@]} -gt 0 ]; then
  # ${#FAILED[@]} is the length of the FAILED array.
  # If it's greater than 0, some repos failed.
  printf "\n${YELLOW}${BOLD}Some repos could not be cloned:${RESET}\n"
  for name in "${FAILED[@]}"; do
    warn "$name  — push this repo to GitHub first, then re-run ./setup.sh"
  done
  printf "\n${BOLD}Everything else is ready.${RESET}\n"
else
  printf "\n${GREEN}${BOLD}All repositories cloned successfully.${RESET}\n"
fi

printf "\nNext steps:\n"
printf "  1. Add your ${BOLD}.env${RESET} files to each service directory\n"
printf "  2. Run ${BOLD}make install${RESET} to install backend dependencies\n"
printf "  3. Run ${BOLD}make start${RESET} to start all services\n\n"
