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

state_dir() {
  printf '%s/state' "$DATA_DIR"
}

state_path() {
  printf '%s/%s' "$(state_dir)" "$1"
}

ensure_state_dir() {
  mkdir -p "$(state_dir)"
}

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { RS=""; ORS="" }
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\r/,"\\r")
      gsub(/\n/,"\\n")
      gsub(/\t/,"\\t")
      print
    }
  '
}

json_quote() {
  printf '"%s"' "$(json_escape "$1")"
}

json_bool() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

csv_from_args() {
  local first=1 item
  for item in "$@"; do
    [ -n "$item" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '%s' "$item"
  done
}

json_array_from_csv() {
  local csv="$1"
  local first=1 item
  local items=()
  IFS=',' read -r -a items <<< "$csv" || true
  printf '['
  for item in "${items[@]+"${items[@]}"}"; do
    [ -n "$item" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    printf '%s' "$(json_quote "$item")"
  done
  printf ']'
}

scan_state_path() {
  state_path "latest-scan.json"
}

health_state_path() {
  state_path "latest-health.json"
}

history_state_path() {
  state_path "history.jsonl"
}

history_limit() {
  case "${SKILL_MANAGER_HISTORY_LIMIT:-200}" in
    ''|*[!0-9]*)
      printf '200'
      ;;
    *)
      printf '%s' "${SKILL_MANAGER_HISTORY_LIMIT:-200}"
      ;;
  esac
}

trim_history_file() {
  local file limit line_count tmp
  file=$(history_state_path)
  [ -f "$file" ] || return 0
  limit=$(history_limit)
  [ "$limit" -gt 0 ] || return 0
  line_count=$(wc -l < "$file" | tr -d ' ')
  [ "${line_count:-0}" -le "$limit" ] && return 0
  tmp=$(mktemp)
  tail -n "$limit" "$file" > "$tmp"
  mv "$tmp" "$file"
}

skill_source_metadata_path() {
  printf '%s/.skill-manager-source.env' "$1"
}

write_github_source_metadata() {
  local skill_dir="$1" repo="$2" ref="$3" subdir="$4" source_url="$5" installed_commit="$6"
  local meta
  meta=$(skill_source_metadata_path "$skill_dir")
  {
    printf 'provider=github\n'
    printf 'repo=%s\n' "$repo"
    printf 'ref=%s\n' "$ref"
    printf 'subdir=%s\n' "$subdir"
    printf 'source_url=%s\n' "$source_url"
    printf 'installed_commit=%s\n' "$installed_commit"
    printf 'installed_at=%s\n' "$(timestamp_utc)"
  } > "$meta"
}

clear_skill_source_metadata() {
  local skill_dir="$1" meta
  meta=$(skill_source_metadata_path "$skill_dir")
  rm -f "$meta"
}

read_skill_source_metadata() {
  local meta="$1" key value
  SKILL_SOURCE_PROVIDER=""
  SKILL_SOURCE_REPO=""
  SKILL_SOURCE_REF=""
  SKILL_SOURCE_SUBDIR=""
  SKILL_SOURCE_URL=""
  SKILL_SOURCE_INSTALLED_COMMIT=""
  SKILL_SOURCE_INSTALLED_AT=""
  [ -f "$meta" ] || return 1
  while IFS='=' read -r key value; do
    case "$key" in
      provider) SKILL_SOURCE_PROVIDER="$value" ;;
      repo) SKILL_SOURCE_REPO="$value" ;;
      ref) SKILL_SOURCE_REF="$value" ;;
      subdir) SKILL_SOURCE_SUBDIR="$value" ;;
      source_url) SKILL_SOURCE_URL="$value" ;;
      installed_commit) SKILL_SOURCE_INSTALLED_COMMIT="$value" ;;
      installed_at) SKILL_SOURCE_INSTALLED_AT="$value" ;;
    esac
  done < "$meta"
  return 0
}

is_github_url() {
  case "$1" in
    https://github.com/*|http://github.com/*) return 0 ;;
    *) return 1 ;;
  esac
}

parse_github_source() {
  local url="$1" clean path owner repo rest ref subdir
  clean="${url%%\?*}"
  clean="${clean%%#*}"
  clean="${clean%/}"
  case "$clean" in
    https://github.com/*) path="${clean#https://github.com/}" ;;
    http://github.com/*) path="${clean#http://github.com/}" ;;
    *) return 1 ;;
  esac
  owner="${path%%/*}"
  path="${path#*/}"
  repo="${path%%/*}"
  repo="${repo%.git}"
  rest="${path#*/}"
  ref=""
  subdir=""
  if [ "$rest" != "$path" ] && [ "${rest%%/*}" = "tree" ]; then
    rest="${rest#tree/}"
    ref="${rest%%/*}"
    if [ "$rest" != "$ref" ]; then
      subdir="${rest#*/}"
    fi
  fi
  [ -n "$owner" ] || return 1
  [ -n "$repo" ] || return 1
  printf '%s|%s|%s|%s|%s\n' "$owner" "$repo" "$ref" "$subdir" "$clean"
}

github_latest_path_commit() {
  local repo="$1" ref="$2" subdir="$3"
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  if [ -n "$subdir" ]; then
    gh api --method GET "repos/${repo}/commits" -f path="$subdir" -f sha="$ref" -F per_page=1 --jq '.[0].sha' 2>/dev/null
  else
    gh api --method GET "repos/${repo}/commits/${ref}" --jq '.sha' 2>/dev/null
  fi
}

write_scan_state() {
  local cache="$1"
  ensure_state_dir
  local outfile
  outfile=$(scan_state_path)

  local total=0 libs=0
  local entry name dir count display_name
  local target_total=0 target_entities=0 target_symlinks=0 target_broken=0
  local link_target kind

  for entry in "$TARGET"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    target_total=$((target_total + 1))
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      target_broken=$((target_broken + 1))
    elif [ -L "$entry" ]; then
      target_symlinks=$((target_symlinks + 1))
    else
      target_entities=$((target_entities + 1))
    fi
  done

  {
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_quote "$(timestamp_utc)")"
    printf '  "target": {\n'
    printf '    "label": %s,\n' "$(json_quote "$(target_label)")"
    printf '    "host": %s,\n' "$(json_quote "$(target_host_id)")"
    printf '    "scope": %s,\n' "$(json_quote "$(target_scope)")"
    printf '    "path": %s,\n' "$(json_quote "$(short_path "$TARGET")")"
    printf '    "total": %d,\n' "$target_total"
    printf '    "entities": %d,\n' "$target_entities"
    printf '    "symlinks": %d,\n' "$target_symlinks"
    printf '    "broken_symlinks": %d\n' "$target_broken"
    printf '  },\n'
    printf '  "sources": [\n'
  } > "$outfile"

  local first=1
  while IFS=: read -r name dir count; do
    libs=$((libs + 1))
    total=$((total + count))
    display_name=$(source_display_name "$name" "$dir" "$cache")
    [ "$first" -eq 1 ] || printf ',\n' >> "$outfile"
    first=0
    printf '    {"name": %s, "display_name": %s, "path": %s, "count": %d, "is_target": %s}' \
      "$(json_quote "$name")" \
      "$(json_quote "$display_name")" \
      "$(json_quote "$(short_path "$dir")")" \
      "$count" \
      "$(json_bool "$([ "$dir" = "$TARGET" ] && echo 1 || echo 0)")" >> "$outfile"
  done < "$cache"

  {
    printf '\n  ],\n'
    printf '  "totals": {\n'
    printf '    "skills": %d,\n' "$total"
    printf '    "libraries": %d\n' "$libs"
    printf '  },\n'
    printf '  "installed": [\n'
  } >> "$outfile"

  first=1
  for entry in "$TARGET"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=$(basename "$entry")
    link_target=""
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      kind="broken_symlink"
      link_target=$(readlink "$entry" 2>/dev/null || true)
    elif [ -L "$entry" ]; then
      kind="symlink"
      link_target=$(readlink "$entry" 2>/dev/null || true)
    else
      kind="entity"
    fi
    [ "$first" -eq 1 ] || printf ',\n' >> "$outfile"
    first=0
    if [ -n "$link_target" ]; then
      printf '    {"name": %s, "kind": %s, "path": %s, "link_target": %s}' \
        "$(json_quote "$name")" \
        "$(json_quote "$kind")" \
        "$(json_quote "$(short_path "$entry")")" \
        "$(json_quote "$(short_path "$link_target")")" >> "$outfile"
    else
      printf '    {"name": %s, "kind": %s, "path": %s}' \
        "$(json_quote "$name")" \
        "$(json_quote "$kind")" \
        "$(json_quote "$(short_path "$entry")")" >> "$outfile"
    fi
  done

  {
    printf '\n  ]\n'
    printf '}\n'
  } >> "$outfile"

  printf '%s' "$outfile"
}

write_check_state() {
  local src_query="$1" src_name="$2"
  local route_candidate_count="$3" route_new_count="$4" route_duplicate_count="$5"
  local route_risky_count="$6" route_source_issue_count="$7"
  local route_candidate_names="$8" route_new_names="$9"
  local route_duplicate_names="${10}" route_risky_names="${11}" route_source_issue_names="${12}"
  local ready_count="${13}" easy_count="${14}" hard_count="${15}"
  local issue_count="${16}" cleanup_count="${17}" cleanup_applied="${18}"
  local upstream_tracked="${19}" upstream_current="${20}" upstream_outdated="${21}" upstream_unknown="${22}"
  local struct_tmp="${23}" overlap_tmp="${24}" cleanup_tmp="${25}" upstream_tmp="${26}"
  ensure_state_dir
  local outfile
  outfile=$(health_state_path)

  {
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_quote "$(timestamp_utc)")"
    printf '  "target": {\n'
    printf '    "label": %s,\n' "$(json_quote "$(target_label)")"
    printf '    "host": %s,\n' "$(json_quote "$(target_host_id)")"
    printf '    "scope": %s,\n' "$(json_quote "$(target_scope)")"
    printf '    "path": %s\n' "$(json_quote "$(short_path "$TARGET")")"
    printf '  },\n'
    if [ -n "$src_query" ] || [ -n "$src_name" ]; then
      printf '  "route": {\n'
      printf '    "query": %s,\n' "$(json_quote "$src_query")"
      printf '    "name": %s,\n' "$(json_quote "${src_name:-$src_query}")"
      printf '    "candidate_skills": %d,\n' "$route_candidate_count"
      printf '    "new_skills": %d,\n' "$route_new_count"
      printf '    "duplicates_in_target": %d,\n' "$route_duplicate_count"
      printf '    "host_risks": %d,\n' "$route_risky_count"
      printf '    "source_issues": %d,\n' "$route_source_issue_count"
      printf '    "candidate_names": %s,\n' "$(json_array_from_csv "$route_candidate_names")"
      printf '    "new_names": %s,\n' "$(json_array_from_csv "$route_new_names")"
      printf '    "duplicate_names": %s,\n' "$(json_array_from_csv "$route_duplicate_names")"
      printf '    "risky_names": %s,\n' "$(json_array_from_csv "$route_risky_names")"
      printf '    "source_issue_names": %s\n' "$(json_array_from_csv "$route_source_issue_names")"
      printf '  },\n'
    else
      printf '  "route": null,\n'
    fi
    printf '  "summary": {\n'
    printf '    "structure_issues": %d,\n' "$issue_count"
    printf '    "runtime_ready": %d,\n' "$ready_count"
    printf '    "runtime_easy_fix": %d,\n' "$easy_count"
    printf '    "runtime_user_action": %d,\n' "$hard_count"
    printf '    "upstream_tracked": %d,\n' "$upstream_tracked"
    printf '    "upstream_current": %d,\n' "$upstream_current"
    printf '    "upstream_outdated": %d,\n' "$upstream_outdated"
    printf '    "upstream_unknown": %d,\n' "$upstream_unknown"
    printf '    "cleanup_candidates": %d,\n' "$cleanup_count"
    printf '    "cleanup_applied": %s\n' "$(json_bool "$cleanup_applied")"
    printf '  },\n'
    printf '  "structure_issues": [\n'
  } > "$outfile"

  local first=1 kind name note line category count skills csv
  while IFS='|' read -r kind name note; do
    [ -n "$kind" ] || continue
    [ "$first" -eq 1 ] || printf ',\n' >> "$outfile"
    first=0
    printf '    {"kind": %s, "name": %s, "note": %s}' \
      "$(json_quote "$kind")" \
      "$(json_quote "$name")" \
      "$(json_quote "$note")" >> "$outfile"
  done < "$struct_tmp"

  {
    printf '\n  ],\n'
    printf '  "overlap_groups": [\n'
  } >> "$outfile"

  first=1
  while IFS='|' read -r category count csv; do
    [ -n "$category" ] || continue
    [ "$first" -eq 1 ] || printf ',\n' >> "$outfile"
    first=0
    printf '    {"category": %s, "count": %d, "skills": [' \
      "$(json_quote "$category")" \
      "$count" >> "$outfile"
    local inner_first=1 skill
    IFS=',' read -r -a skills <<< "$csv"
    for skill in "${skills[@]}"; do
      [ -n "$skill" ] || continue
      [ "$inner_first" -eq 1 ] || printf ', ' >> "$outfile"
      inner_first=0
      printf '%s' "$(json_quote "$skill")" >> "$outfile"
    done
    printf ']}' >> "$outfile"
  done < "$overlap_tmp"

  {
    printf '\n  ],\n'
    printf '  "upstream_sources": [\n'
  } >> "$outfile"

  first=1
  while IFS='|' read -r name status repo ref subdir installed_commit latest_commit source_url; do
    [ -n "$name" ] || continue
    [ "$first" -eq 1 ] || printf ',\n' >> "$outfile"
    first=0
    printf '    {"name": %s, "status": %s, "repo": %s, "ref": %s, "subdir": %s, "installed_commit": %s, "latest_commit": %s, "source_url": %s}' \
      "$(json_quote "$name")" \
      "$(json_quote "$status")" \
      "$(json_quote "$repo")" \
      "$(json_quote "$ref")" \
      "$(json_quote "$subdir")" \
      "$(json_quote "$installed_commit")" \
      "$(json_quote "$latest_commit")" \
      "$(json_quote "$source_url")" >> "$outfile"
  done < "$upstream_tmp"

  {
    printf '\n  ],\n'
    printf '  "cleanup_candidates": [\n'
  } >> "$outfile"

  first=1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ "$first" -eq 1 ] || printf ',\n' >> "$outfile"
    first=0
    printf '    %s' "$(json_quote "$name")" >> "$outfile"
  done < "$cleanup_tmp"

  {
    printf '\n  ]\n'
    printf '}\n'
  } >> "$outfile"

  printf '%s' "$outfile"
}

record_scan_event() {
  local total="$1" libs="$2"
  ensure_state_dir
  printf '{"ts":%s,"kind":"scan","target":%s,"host":%s,"skills":%d,"libraries":%d}\n' \
    "$(json_quote "$(timestamp_utc)")" \
    "$(json_quote "$(short_path "$TARGET")")" \
    "$(json_quote "$(target_host_id)")" \
    "$total" \
    "$libs" >> "$(history_state_path)"
  trim_history_file
}

record_check_event() {
  local src_query="$1" src_name="$2" issue_count="$3" ready_count="$4" easy_count="$5" hard_count="$6"
  ensure_state_dir
  if [ -n "$src_query" ] || [ -n "$src_name" ]; then
    printf '{"ts":%s,"kind":"check","target":%s,"host":%s,"route_query":%s,"route_name":%s,"structure_issues":%d,"runtime_ready":%d,"runtime_easy_fix":%d,"runtime_user_action":%d}\n' \
      "$(json_quote "$(timestamp_utc)")" \
      "$(json_quote "$(short_path "$TARGET")")" \
      "$(json_quote "$(target_host_id)")" \
      "$(json_quote "$src_query")" \
      "$(json_quote "${src_name:-$src_query}")" \
      "$issue_count" \
      "$ready_count" \
      "$easy_count" \
      "$hard_count" >> "$(history_state_path)"
  else
    printf '{"ts":%s,"kind":"check","target":%s,"host":%s,"structure_issues":%d,"runtime_ready":%d,"runtime_easy_fix":%d,"runtime_user_action":%d}\n' \
      "$(json_quote "$(timestamp_utc)")" \
      "$(json_quote "$(short_path "$TARGET")")" \
      "$(json_quote "$(target_host_id)")" \
      "$issue_count" \
      "$ready_count" \
      "$easy_count" \
      "$hard_count" >> "$(history_state_path)"
  fi
  trim_history_file
}

record_steal_event() {
  local src_name="$1" src_dir="$2" new_count="$3" skip_count="$4" copy_mode="$5"
  ensure_state_dir
  printf '{"ts":%s,"kind":"steal","source":%s,"source_path":%s,"target":%s,"host":%s,"mode":%s,"new":%d,"existing":%d}\n' \
    "$(json_quote "$(timestamp_utc)")" \
    "$(json_quote "$src_name")" \
    "$(json_quote "$(short_path "$src_dir")")" \
    "$(json_quote "$(short_path "$TARGET")")" \
    "$(json_quote "$(target_host_id)")" \
    "$(json_quote "$([ "$copy_mode" -eq 1 ] && echo copy || echo symlink)")" \
    "$new_count" \
    "$skip_count" >> "$(history_state_path)"
  trim_history_file
}

record_bind_event() {
  local skill_name="$1" skill_path="$2" source_url="$3" repo="$4" ref="$5" subdir="$6" installed_commit="$7"
  ensure_state_dir
  printf '{"ts":%s,"kind":"bind","skill":%s,"skill_path":%s,"target":%s,"host":%s,"source_url":%s,"repo":%s,"ref":%s,"subdir":%s,"installed_commit":%s}\n' \
    "$(json_quote "$(timestamp_utc)")" \
    "$(json_quote "$skill_name")" \
    "$(json_quote "$(short_path "$skill_path")")" \
    "$(json_quote "$(short_path "$TARGET")")" \
    "$(json_quote "$(target_host_id)")" \
    "$(json_quote "$source_url")" \
    "$(json_quote "$repo")" \
    "$(json_quote "$ref")" \
    "$(json_quote "$subdir")" \
    "$(json_quote "$installed_commit")" >> "$(history_state_path)"
  trim_history_file
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
