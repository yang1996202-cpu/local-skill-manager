#!/usr/bin/env bash
# skill-mgr.sh v4.0 — PDCA 技能管家
# scan(Plan) → steal(Do) → check(Check) → act(Act)
set -euo pipefail

VERSION="5.3.0"
DEFAULT_DATA_DIR="${XDG_STATE_HOME:-$HOME/.skill-manager}"
FALLBACK_DATA_DIR="${TMPDIR:-/tmp}/skill-manager-${USER:-user}"
DATA_DIR="${SKILL_MANAGER_DATA_DIR:-$DEFAULT_DATA_DIR}"
ENV_TARGET="${SKILL_MANAGER_TARGET:-}"
DEFAULT_TARGET="$HOME/.claude/skills"
TARGET="$DEFAULT_TARGET"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
B='\033[0;34m'
C='\033[0;36m'
D='\033[2m'
N='\033[0m'
FIRE='\033[1;31m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

load_skill_manager_env() {
  local env_file="${SKILL_MANAGER_ENV_FILE:-$HOME/.skill-manager/env}"
  [ -f "$env_file" ] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
}

load_skill_manager_env

source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/context.sh"
source "${LIB_DIR}/online.sh"
source "${LIB_DIR}/check.sh"
source "${LIB_DIR}/commands.sh"

DRY_RUN=0
AUTO_YES=0
USE_COPY=0
ACT_WEB=0
TARGET_QUERY=""
_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) AUTO_YES=1; shift ;;
    --copy) USE_COPY=1; shift ;;
    --web) ACT_WEB=1; shift ;;
    --to|--target)
      [ "$#" -ge 2 ] || { echo "skill-mgr: --to 需要指定目标库" >&2; exit 1; }
      TARGET_QUERY="$2"
      shift 2
      ;;
    *) _args+=("$1"); shift ;;
  esac
done
set -- "${_args[@]+"${_args[@]}"}"

init_data_dir
init_default_target

case "${1:-help}" in
  scan)    cmd_scan ;;
  steal)   cmd_steal "${2:-}" "${@:3}" ;;
  check)   cmd_check "${@:2}" ;;
  act)     cmd_act "${@:2}" ;;
  check-web) ACT_WEB=1; cmd_check "${@:2}" ;;
  act-web)   ACT_WEB=1; cmd_act "${@:2}" ;;
  help|*)
    echo -e "skill-mgr v${VERSION} ${D}— skill manager${N}"
    echo ""
    echo "  scan             在本地扫描所有技能库"
    echo "  steal <从> [技能] 从其他技能库迁移到这里，也可直接装 GitHub skill"
    echo "  check [从]       默认检查当前库健康度"
    echo "  act              联网后按当前身份推荐 skills"
    echo ""
    echo -e "  ${D}常用别名: here / home-claude / home-openclaw / home-codex / home-amp${N}"
    echo -e "  ${D}需要换目标时再用 --to；需要联网时再用 --web${N}"
    ;;
esac
