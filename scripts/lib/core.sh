platform_id() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

looks_like_explicit_path() {
  case "$1" in
    "~"*|/*|./*|../*|[A-Za-z]:\\*|[A-Za-z]:/*) return 0 ;;
    *) return 1 ;;
  esac
}

windows_path_to_posix() {
  local path="$1"
  case "$path" in
    [A-Za-z]:\\*)
      printf '%s' "$path" | sed -E 's#\\#/#g; s#^([A-Za-z]):#/\\L\\1#'
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

expand_input_path() {
  local path="$1"
  case "$path" in
    "~"*) path="${path/#\~/$HOME}" ;;
  esac
  windows_path_to_posix "$path"
}

append_unique_dir() {
  local candidate="$1"
  [ -n "$candidate" ] || return 0
  [ -d "$candidate" ] || return 0
  local existing
  for existing in "${SCAN_ROOTS[@]-}"; do
    [ "$existing" = "$candidate" ] && return 0
  done
  SCAN_ROOTS+=("$candidate")
}

scan_roots() {
  SCAN_ROOTS=()
  append_unique_dir "$HOME"

  local platform userprofile
  platform=$(platform_id)
  userprofile=$(windows_path_to_posix "${USERPROFILE:-}")
  append_unique_dir "$userprofile"

  if [ "$platform" = "wsl" ] && [ -n "${USER:-}" ]; then
    append_unique_dir "/mnt/c/Users/${USER}"
  fi

  printf '%s\n' "${SCAN_ROOTS[@]}"
}

relative_for_label() {
  local path="$1" root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    case "$path" in
      "$root"/*)
        printf '%s' "${path#$root/}"
        return 0
        ;;
      "$root")
        printf '.'
        return 0
        ;;
    esac
  done < <(scan_roots)
  case "$path" in
    "$HOME"/*) printf '%s' "${path#$HOME/}" ;;
    /*) printf '%s' "${path#/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

init_data_dir() {
  local candidates=("$DATA_DIR")
  [ "$DATA_DIR" != "$FALLBACK_DATA_DIR" ] && candidates+=("$FALLBACK_DATA_DIR")
  local dir
  for dir in "${candidates[@]}"; do
    if mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ]; then
      DATA_DIR="$dir"
      return 0
    fi
  done
  echo "skill-mgr: 无法创建可写缓存目录" >&2
  exit 1
}

label() {
  case "$1" in
    .claude/skills*) echo "Claude Code" ;;
    .agents/skills*) echo "Amp" ;;
    .cursor/*) echo "Cursor" ;;
    .codex/*) echo "Codex" ;;
    .openclaw/extensions/*) echo "OpenClaw-扩展" ;;
    .openclaw*) echo "OpenClaw" ;;
    .cc-switch/*) echo "CC-Switch" ;;
    .workbuddy/*) echo "WorkBuddy" ;;
    .codeium/windsurf/*) echo "Windsurf" ;;
    .opencode/*) echo "OpenCode" ;;
    .trae/*) echo "Trae" ;;
    .cline/*) echo "Cline" ;;
    .kiro/*) echo "Kiro" ;;
    .roo/*) echo "Roo" ;;
    .goose/*) echo "Goose" ;;
    .gemini/*) echo "Gemini" ;;
    Downloads/*) echo "下载" ;;
    */.claude/skills*) echo "项目级" ;;
    *) echo "${1%%/*}" ;;
  esac
}

host_id_from_label() {
  case "$1" in
    "Claude Code") echo "claude" ;;
    "Codex") echo "codex" ;;
    "OpenClaw"|"OpenClaw-扩展"|"OpenCode") echo "openclaw" ;;
    "Amp") echo "amp" ;;
    "Cursor") echo "cursor" ;;
    "Windsurf") echo "windsurf" ;;
    "Cline") echo "cline" ;;
    "Kiro") echo "kiro" ;;
    *) echo "generic" ;;
  esac
}

host_label_from_id() {
  case "$1" in
    claude) echo "Claude Code" ;;
    codex) echo "Codex" ;;
    openclaw) echo "OpenClaw" ;;
    amp) echo "Amp" ;;
    cursor) echo "Cursor" ;;
    windsurf) echo "Windsurf" ;;
    cline) echo "Cline" ;;
    kiro) echo "Kiro" ;;
    *) echo "通用" ;;
  esac
}

discover_project_target() {
  local dir="$PWD" parent
  while :; do
    for candidate in \
      "$dir/.claude/skills" \
      "$dir/.openclaw/workspace/skills" \
      "$dir/.opencode/skills" \
      "$dir/.codex/skills" \
      "$dir/.agents/skills"
    do
      [ -d "$candidate" ] && { echo "$candidate"; return 0; }
    done
    [ "$dir" = "/" ] && break
    [ "$dir" = "$HOME" ] && break
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
  return 1
}

init_default_target() {
  if [ -n "$ENV_TARGET" ]; then
    TARGET="$ENV_TARGET"
    return 0
  fi
  local project_target
  project_target=$(discover_project_target 2>/dev/null || true)
  TARGET="${project_target:-$DEFAULT_TARGET}"
}

short_path() {
  case "$1" in
    "$HOME"/*) echo "~/${1#$HOME/}" ;;
    *) echo "$1" ;;
  esac
}

source_display_name() {
  local name="$1" dir="$2" cache="$3"
  local duplicates suffix short
  duplicates=$(awk -F: -v n="$name" '$1==n{c++} END{print c+0}' "$cache" 2>/dev/null)
  if [ "${duplicates:-0}" -le 1 ]; then
    echo "$name"
    return 0
  fi

  short=$(short_path "$dir")
  suffix=$(printf '%s\n' "$short" | awk -F/ '
    {
      for (i = NF; i >= 1; i--) {
        part = $i
        gsub(/^[.]+/, "", part)
        if (part == "" || part == "skills" || part == "workspace" || part == "opencode" || part == "claude" || part == "openclaw" || part == "extensions") {
          continue
        }
        print part
        exit
      }
    }
  ')
  [ -n "$suffix" ] || suffix="$short"
  echo "${name} [${suffix}]"
}

target_label() {
  case "$TARGET" in
    */.claude/skills*) echo "Claude Code"; return 0 ;;
    */.codex/skills*) echo "Codex"; return 0 ;;
    */.agents/skills*) echo "Amp"; return 0 ;;
    */.openclaw/workspace/skills*|*/.openclaw/extensions/*/skills*|*/.opencode/skills*) echo "OpenClaw"; return 0 ;;
  esac
  local rel="$TARGET"
  case "$TARGET" in
    "$HOME"/*) rel="${TARGET#$HOME/}" ;;
    /*) rel="${TARGET#/}" ;;
  esac
  label "$rel"
}

target_host_id() {
  host_id_from_label "$(target_label)"
}

target_scope() {
  local project_target
  project_target=$(discover_project_target 2>/dev/null || true)
  if [ -n "$project_target" ] && [ "$TARGET" = "$project_target" ]; then
    echo "当前项目"
  elif [ "$TARGET" = "$HOME/.claude/skills" ] || \
       [ "$TARGET" = "$HOME/.openclaw/workspace/skills" ] || \
       [ "$TARGET" = "$HOME/.opencode/skills" ] || \
       [ "$TARGET" = "$HOME/.codex/skills" ] || \
       [ "$TARGET" = "$HOME/.agents/skills" ]; then
    echo "主目录"
  else
    echo "自定义位置"
  fi
}

friendly_target() {
  echo "$(target_scope)的 $(target_label) 技能库"
}

resolve_target_alias() {
  local q
  q=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$q" in
    here|current|local|当前项目|本项目|这里)
      discover_project_target 2>/dev/null || echo "$TARGET"
      ;;
    home-claude|claude-home|主claude)
      echo "$HOME/.claude/skills"
      ;;
    home-openclaw|openclaw-home|主openclaw)
      echo "$HOME/.openclaw/workspace/skills"
      ;;
    home-opencode|opencode-home|主opencode)
      echo "$HOME/.opencode/skills"
      ;;
    home-codex|codex-home|主codex)
      echo "$HOME/.codex/skills"
      ;;
    home-amp|amp-home|主amp)
      echo "$HOME/.agents/skills"
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_target() {
  local cache="$1"
  [ -z "$TARGET_QUERY" ] && return 0

  local resolved
  resolved=$(resolve_target_alias "$TARGET_QUERY" 2>/dev/null || true)
  if [ -n "$resolved" ]; then
    TARGET="$resolved"
    return 0
  fi
  resolved=$(resolve "$TARGET_QUERY" "$cache")
  if [ -n "$resolved" ]; then
    TARGET="$resolved"
    return 0
  fi

  case "$TARGET_QUERY" in
    "~"*) TARGET="${TARGET_QUERY/#\~/$HOME}" ;;
    */*|.*) TARGET="$TARGET_QUERY" ;;
    *)
      echo -e "  ${R}✗${N} 找不到目标库: $TARGET_QUERY" >&2
      exit 1
      ;;
  esac
}

cross_host_notes() {
  local content="$1" target_id="$2" target_name="$3"
  local ids="claude codex openclaw amp cursor windsurf cline kiro"
  local host_id pattern host_name notes=""

  for host_id in $ids; do
    [ "$host_id" = "$target_id" ] && continue
    case "$host_id" in
      claude) pattern="\\.claude/|claude code" ;;
      codex) pattern="\\.codex/|codex" ;;
      openclaw) pattern="\\.openclaw/|\\.opencode/|openclaw|opencode" ;;
      amp) pattern="\\.agents/skills|amp" ;;
      cursor) pattern="\\.cursor/|cursor" ;;
      windsurf) pattern="windsurf|\\.codeium/windsurf" ;;
      cline) pattern="\\.cline/|cline" ;;
      kiro) pattern="\\.kiro/|kiro" ;;
      *) pattern="" ;;
    esac
    [ -n "$pattern" ] || continue
    if echo "$content" | grep -qiE "$pattern"; then
      host_name=$(host_label_from_id "$host_id")
      notes+="\n    ${Y}•${N} 宿主适配: 内容疑似依赖 ${host_name} 的路径或命令约定"
      notes+="\n      ${D}└─ 当前目标库: ${target_name}；偷过来后可能需要手动改造${N}"
    fi
  done

  printf '%s' "$notes"
}

desc() {
  local f="$1/SKILL.md"
  [ -f "$f" ] || return
  awk '
    BEGIN { in_frontmatter=0; capture=0; desc=""; printed=0 }
    /^---[[:space:]]*$/ {
      if (!in_frontmatter) {
        in_frontmatter=1
        next
      }
      if (capture && desc != "") {
        print desc
        printed=1
      }
      exit
    }
    !in_frontmatter { next }
    capture {
      if ($0 ~ /^[[:space:]]+/) {
        sub(/^[[:space:]]+/, "", $0)
        if ($0 != "") {
          desc = (desc == "" ? $0 : desc " " $0)
        }
        next
      }
      if (desc != "") {
        print desc
        printed=1
      }
      exit
    }
    /^[[:space:]]*description:[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*description:[[:space:]]*/, "", line)
      gsub(/^["'"'"']|["'"'"']$/, "", line)
      if (line == "" || line ~ /^[>|]/) {
        capture=1
        next
      }
      print line
      printed=1
      exit
    }
    END {
      if (!printed && capture && desc != "") {
        print desc
      }
    }
  ' "$f" 2>/dev/null | cut -c1-60
}

do_scan() {
  local cache="$DATA_DIR/last_scan.txt" tmpraw seen
  tmpraw=$(mktemp)
  seen=$(mktemp)
  : > "$tmpraw"

  local root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    find "$root" -maxdepth 6 \
      -type d \( -name 'node_modules' -o -name 'Library' -o -name '.Trash' -o -name '.git' \
      -o -name 'Applications' -o -name 'AppData' -o -name 'Pictures' -o -name 'Music' -o -name 'Movies' \) -prune \
      -o -name 'SKILL.md' -type f -print 2>/dev/null
  done < <(scan_roots) | \
    sed 's|/SKILL.md$||' | while read -r d; do dirname "$d"; done | \
    sort | uniq -c | sort -rn > "$tmpraw"

  > "$cache"
  while read -r count parent; do
    local skip=0
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      case "$parent" in
        "$s"/*) skip=1; break ;;
      esac
    done < "$seen"
    [ "$skip" -eq 1 ] && continue
    echo "$parent" >> "$seen"
    echo "$(label "$(relative_for_label "$parent")"):${parent}:${count}" >> "$cache"
  done < "$tmpraw"
  rm -f "$tmpraw" "$seen"
  echo "$cache"
}

resolve() {
  local q="$1" c="$2"
  local explicit
  if looks_like_explicit_path "$q"; then
    explicit=$(expand_input_path "$q")
    if [ -d "$explicit" ]; then
      echo "$explicit"
      return 0
    fi
  fi
  if [ -d "$q" ]; then
    echo "$q"
  elif [[ "$q" =~ ^[0-9]+$ ]]; then
    sed -n "${q}p" "$c" | cut -d: -f2
  else
    local r
    r=$(awk -F: -v q="$q" 'tolower($1)==tolower(q){print $2; exit}' "$c")
    [ -z "$r" ] && r=$(grep -iF "$q" "$c" | head -1 | cut -d: -f2)
    echo "$r"
  fi
}
