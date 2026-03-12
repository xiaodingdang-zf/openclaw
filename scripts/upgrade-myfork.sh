#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REMOTE="${OPENCLAW_UPSTREAM_REMOTE:-origin}"
FORK_REMOTE="${OPENCLAW_FORK_REMOTE:-myfork}"
MAIN_BRANCH="${OPENCLAW_MAIN_BRANCH:-main}"
PATCH_BRANCH="${OPENCLAW_PATCH_BRANCH:-codex/fix-agent-capability-prompt}"
TEST_CMD="${OPENCLAW_UPGRADE_TEST_CMD:-pnpm vitest run src/agents/system-prompt.test.ts}"
BUILD_CMD="${OPENCLAW_UPGRADE_BUILD_CMD:-pnpm build}"
INSTALL_CMD="${OPENCLAW_UPGRADE_INSTALL_CMD:-npm install -g .}"
RESTART_CMD="${OPENCLAW_UPGRADE_RESTART_CMD:-openclaw gateway restart}"

AUTO_STASH=1
SKIP_TESTS=0
SKIP_PUSH=0
DRY_RUN=0

ORIGINAL_BRANCH=""
STASH_REF=""
STASH_LABEL=""
RESTORE_ORIGINAL_BRANCH=1

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

run_step() {
  local label="$1"
  shift
  log "==> ${label}"
  "$@"
}

run_shell() {
  local label="$1"
  local command="$2"
  log "==> ${label}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] %s\n' "$command"
    return 0
  fi
  bash -lc "cd '${ROOT_DIR}' && ${command}"
}

usage() {
  cat <<'EOF'
Usage: bash scripts/upgrade-myfork.sh [options]

Upgrades OpenClaw from the upstream repo, reapplies your local patch branch,
rebuilds, reinstalls globally, restarts the gateway, and pushes your branch.

Options:
  --no-stash    Fail instead of auto-stashing local changes
  --skip-tests  Skip the targeted test run
  --skip-push   Skip git push to your fork
  --dry-run     Print actions without changing anything
  --stay        Leave you on the patch branch after finishing
  --help        Show this help

Environment overrides:
  OPENCLAW_UPSTREAM_REMOTE
  OPENCLAW_FORK_REMOTE
  OPENCLAW_MAIN_BRANCH
  OPENCLAW_PATCH_BRANCH
  OPENCLAW_UPGRADE_TEST_CMD
  OPENCLAW_UPGRADE_BUILD_CMD
  OPENCLAW_UPGRADE_INSTALL_CMD
  OPENCLAW_UPGRADE_RESTART_CMD
EOF
}

restore_local_changes() {
  if [[ -z "${STASH_REF}" ]]; then
    return 0
  fi

  log "==> Restoring stashed local changes (${STASH_REF})"
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] git stash pop %s\n' "${STASH_REF}"
    return 0
  fi

  if git -C "${ROOT_DIR}" stash pop "${STASH_REF}"; then
    return 0
  fi

  log "Local changes were not fully restored automatically."
  log "Your stash is still saved as ${STASH_REF}."
  log "Resolve any conflicts, then run: git -C '${ROOT_DIR}' stash pop ${STASH_REF}"
}

cleanup() {
  local exit_code=$?

  if [[ "${RESTORE_ORIGINAL_BRANCH}" == "1" && -n "${ORIGINAL_BRANCH}" ]]; then
    if [[ "${DRY_RUN}" == "1" ]]; then
      printf '[dry-run] git checkout %s\n' "${ORIGINAL_BRANCH}"
    else
      git -C "${ROOT_DIR}" checkout "${ORIGINAL_BRANCH}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    restore_local_changes
  elif [[ -n "${STASH_REF}" ]]; then
    log "Upgrade stopped early. Your local changes are preserved in ${STASH_REF}."
  fi

  exit $exit_code
}

trap cleanup EXIT

for arg in "$@"; do
  case "${arg}" in
    --no-stash)
      AUTO_STASH=0
      ;;
    --skip-tests)
      SKIP_TESTS=1
      ;;
    --skip-push)
      SKIP_PUSH=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --stay)
      RESTORE_ORIGINAL_BRANCH=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: ${arg}"
      ;;
  esac
done

ORIGINAL_BRANCH="$(git -C "${ROOT_DIR}" branch --show-current)"
[[ -n "${ORIGINAL_BRANCH}" ]] || fail "Could not determine the current branch."

git -C "${ROOT_DIR}" remote get-url "${UPSTREAM_REMOTE}" >/dev/null 2>&1 || \
  fail "Missing upstream remote: ${UPSTREAM_REMOTE}"
git -C "${ROOT_DIR}" remote get-url "${FORK_REMOTE}" >/dev/null 2>&1 || \
  fail "Missing fork remote: ${FORK_REMOTE}"
git -C "${ROOT_DIR}" show-ref --verify --quiet "refs/heads/${MAIN_BRANCH}" || \
  fail "Missing local branch: ${MAIN_BRANCH}"
git -C "${ROOT_DIR}" show-ref --verify --quiet "refs/heads/${PATCH_BRANCH}" || \
  fail "Missing local branch: ${PATCH_BRANCH}"

if [[ -n "$(git -C "${ROOT_DIR}" status --short)" ]]; then
  if [[ "${AUTO_STASH}" != "1" ]]; then
    fail "Working tree is not clean. Commit or stash changes first, or rerun without --no-stash."
  fi

  STASH_LABEL="openclaw-upgrade-$(date +%Y%m%d-%H%M%S)"
  log "==> Stashing local changes (${STASH_LABEL})"
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] git stash push -u -m %s\n' "${STASH_LABEL}"
    STASH_REF="stash@{0}"
  else
    git -C "${ROOT_DIR}" stash push -u -m "${STASH_LABEL}" >/dev/null
    STASH_REF="$(git -C "${ROOT_DIR}" stash list --format='%gd %s' | awk -v label="${STASH_LABEL}" '$0 ~ label { print $1; exit }')"
    [[ -n "${STASH_REF}" ]] || fail "Failed to locate the stash created for this upgrade."
  fi
fi

run_step "fetch upstream" git -C "${ROOT_DIR}" fetch "${UPSTREAM_REMOTE}"
run_step "fetch fork" git -C "${ROOT_DIR}" fetch "${FORK_REMOTE}"
run_step "checkout ${MAIN_BRANCH}" git -C "${ROOT_DIR}" checkout "${MAIN_BRANCH}"
run_step "fast-forward ${MAIN_BRANCH}" git -C "${ROOT_DIR}" pull --ff-only "${UPSTREAM_REMOTE}" "${MAIN_BRANCH}"
run_step "checkout ${PATCH_BRANCH}" git -C "${ROOT_DIR}" checkout "${PATCH_BRANCH}"
run_step "rebase ${PATCH_BRANCH} onto ${MAIN_BRANCH}" git -C "${ROOT_DIR}" rebase "${MAIN_BRANCH}"

if [[ "${SKIP_TESTS}" != "1" ]]; then
  run_shell "run verification tests" "${TEST_CMD}"
fi

run_shell "build project" "${BUILD_CMD}"
run_shell "install global OpenClaw" "${INSTALL_CMD}"
run_shell "restart gateway" "${RESTART_CMD}"

if [[ "${SKIP_PUSH}" != "1" ]]; then
  run_step "push ${PATCH_BRANCH} to ${FORK_REMOTE}" git -C "${ROOT_DIR}" push "${FORK_REMOTE}" "${PATCH_BRANCH}"
fi

log ""
log "Upgrade finished successfully."
log "Current patch branch: ${PATCH_BRANCH}"
log "Upstream main branch: ${UPSTREAM_REMOTE}/${MAIN_BRANCH}"
log "Fork branch: ${FORK_REMOTE}/${PATCH_BRANCH}"
