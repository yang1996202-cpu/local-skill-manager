collect_env() {
  local host_id="${1:-generic}" host_label="${2:-通用}" target_dir="${3:-$TARGET}"
  echo "  🖥️ 本地环境快照（供 AI 判断技能兼容性）："
  echo "  - 目标宿主: ${host_label}"
  echo "  - 目标目录: ${target_dir}"
  local bins="ffmpeg jq op python3 node npm gh sqlite3 pandoc mcporter obsidian-cli memo brew"
  local installed="" missing=""
  for b in $bins; do
    if command -v "$b" &>/dev/null; then installed+="$b "; else missing+="$b "; fi
  done
  echo "  - 已装命令: ${installed:-无}"
  echo "  - 未装命令: ${missing:-无}"
  local ports="53699 8080 11434"
  local up="" down=""
  for p in $ports; do
    if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$p" 2>/dev/null; then up+="$p "; else down+="$p "; fi
  done
  echo "  - 可达端口: ${up:-无}"
  echo "  - 不可达端口: ${down:-无}"
  local vars="TAVILY_API_KEY SEEDREAM_API_KEY TRELLO_API_KEY TRELLO_TOKEN OPENAI_API_KEY SKILLSMP_API_KEY"
  local set_vars="" unset_vars=""
  for v in $vars; do
    if [ -n "${!v:-}" ]; then set_vars+="$v "; else unset_vars+="$v "; fi
  done
  echo "  - 已配密钥: ${set_vars:-无}"
  echo "  - 未配密钥: ${unset_vars:-无}"
  if [ "$host_id" = "claude" ]; then
    local settings="$HOME/.claude/settings.json"
    if [ -f "$settings" ] && command -v jq &>/dev/null; then
      local mcps
      mcps=$(jq -r '.mcpServers? // {} | keys[]?' "$settings" 2>/dev/null | head -20 | tr '\n' ' ' || true)
      if [ -n "$mcps" ]; then
        echo "  - MCP Servers: ${mcps}"
      fi
    fi
  fi
  return 0
}

path_in_list() {
  local needle="$1"
  shift || true
  [ "$#" -eq 0 ] && return 1
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

context_patterns_for_host() {
  case "$1" in
    claude)
      echo "CLAUDE.md claude.md CLAUDE.local.md .claude/CLAUDE.md .claude/claude.md AGENTS.md RULES.md rules.md members.md member.md"
      ;;
    openclaw)
      echo "AGENTS.md agents.md CLAUDE.md claude.md OPENCLAW.md openclaw.md OPENCODE.md opencode.md opencode.json .opencode/opencode.json RULES.md rules.md members.md member.md"
      ;;
    codex)
      echo "AGENTS.md CODEX.md codex.md CLAUDE.md claude.md RULES.md rules.md members.md member.md"
      ;;
    *)
      echo "AGENTS.md CLAUDE.md claude.md CODEX.md codex.md RULES.md rules.md members.md member.md"
      ;;
  esac
}

collect_context_files() {
  local host_id="$1" dir="$PWD" parent candidate
  local files=() patterns=()
  read -r -a patterns <<< "$(context_patterns_for_host "$host_id")"

  while :; do
    for candidate_rel in "${patterns[@]}"; do
      if [ "$candidate_rel" = "claude.md" ] && [ -f "$dir/CLAUDE.md" ]; then continue; fi
      if [ "$candidate_rel" = "codex.md" ] && [ -f "$dir/CODEX.md" ]; then continue; fi
      if [ "$candidate_rel" = ".claude/claude.md" ] && [ -f "$dir/.claude/CLAUDE.md" ]; then continue; fi
      candidate="$dir/$candidate_rel"
      if [ -f "$candidate" ] && ! path_in_list "$candidate" "${files[@]-}"; then
        files+=("$candidate")
      fi
    done
    for rules_dir in "$dir/.cursor/rules" "$dir/.claude/rules" "$dir/rules"; do
      if [ -d "$rules_dir" ]; then
        for candidate in "$rules_dir"/*; do
          [ -f "$candidate" ] || continue
          path_in_list "$candidate" "${files[@]-}" || files+=("$candidate")
        done
      fi
    done
    for identity_dir in \
      "$dir/agents" \
      "$dir/members" \
      "$dir/.claude/agents" \
      "$dir/.opencode/agents" \
      "$dir/.openclaw/agents"
    do
      if [ -d "$identity_dir" ]; then
        for candidate in "$identity_dir"/*; do
          [ -f "$candidate" ] || continue
          case "$candidate" in
            *.md|*.mdx|*.json|*.yaml|*.yml)
              path_in_list "$candidate" "${files[@]-}" || files+=("$candidate")
              ;;
          esac
        done
      fi
    done
    for candidate in "$dir"/member*.md "$dir"/members*.md; do
      [ -f "$candidate" ] || continue
      path_in_list "$candidate" "${files[@]-}" || files+=("$candidate")
    done
    [ "$dir" = "/" ] && break
    [ "$dir" = "$HOME" ] && break
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done

  for candidate in \
    "$HOME/.claude/CLAUDE.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.config/opencode/opencode.json" \
    "$HOME/.codex/AGENTS.md" \
    "$HOME/.codex/CODEX.md"
  do
    [ -f "$candidate" ] || continue
    path_in_list "$candidate" "${files[@]-}" || files+=("$candidate")
  done

  printf '%s\n' "${files[@]}"
}

emit_context_bundle() {
  local host_id="$1" max_items="${2:-4}"
  local files count=0 file
  files=$(collect_context_files "$host_id")
  [ -n "$files" ] || return 0

  echo ""
  echo "  🧭 当前项目上下文（供 AI 给建议，按距离近到远）:"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    [ "$count" -gt "$max_items" ] && break
    echo "  --- $(basename "$file") ($(short_path "$file")) ---"
    sed -n '1,12p' "$file" | sed 's/^/    /'
    echo ""
  done <<< "$files"
}

emit_context_inventory() {
  local host_id="$1"
  local files file
  files=$(collect_context_files "$host_id")
  [ -n "$files" ] || return 0

  echo ""
  echo "  🧬 当前主体身份/规则文件清单（战略分析的确定性输入）:"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    echo "  - $(basename "$file") ($(short_path "$file"))"
  done <<< "$files"
  return 0
}

show_target_structure() {
  echo ""
  echo "  🧱 当前目标库结构："
  local entry shown=0 name link_target
  for entry in "$TARGET"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=$(basename "$entry")
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      echo "  - 坏链  $name"
    elif [ -L "$entry" ]; then
      link_target=$(readlink "$entry" 2>/dev/null || true)
      echo "  - 软链  $name -> $(short_path "$link_target")"
    else
      echo "  - 实体  $name"
    fi
    shown=$((shown + 1))
  done
  [ "$shown" -eq 0 ] && echo "  - (空)"
  return 0
}

context_keyword_hints() {
  local host_id="$1"
  local files text hints="" line
  files=$(collect_context_files "$host_id")
  text=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    text+=$'\n'
    text+="$(sed -n '1,20p' "$line" 2>/dev/null)"
  done <<< "$files"
  text=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')

  echo "$text" | grep -qE "销售|sale|crm|客户" && hints+=" sales"
  echo "$text" | grep -qE "ai|人工智能|agent" && hints+=" ai"
  echo "$text" | grep -qE "内容|写作|content|公众号|小红书" && hints+=" content"
  echo "$text" | grep -qE "飞书|feishu|lark" && hints+=" feishu"
  echo "$text" | grep -qE "知识|obsidian|memory|记忆" && hints+=" knowledge"
  echo "$text" | grep -qE "浏览器|browser|搜索|search" && hints+=" browser"
  echo "$text" | grep -qE "自动化|automation|workflow" && hints+=" automation"

  printf '%s' "$hints" | awk '{for (i=1;i<=NF && i<=4;i++) printf("%s%s",$i,(i<NF && i<4?" ":""))}'
}
