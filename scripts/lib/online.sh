SKILLSMP_LAST_RESULT_STATE="not_run"
SKILLSMP_TOP_STARS=0
SKILLSMP_SECOND_STARS=0
SKILLSMP_HIGH_CONFIDENCE_COUNT=0

emit_official_sources() {
  echo ""
  echo "  🌐 官方与生态来源（供 AI 给建议时优先参考）:"
  echo "  - Claude Code 概览: https://docs.anthropic.com/en/docs/claude-code/overview"
  echo "  - Claude Code 记忆: https://docs.anthropic.com/en/docs/claude-code/memory"
  echo "  - OpenCode Skills: https://opencode.ai/docs/skills"
  echo "  - OpenCode Rules: https://opencode.ai/docs/rules"
  echo "  - Codex CLI 入门: https://help.openai.com/en/articles/11096431"
  echo "  - OpenClaw 生态技能榜: https://github.com/sundial-org/awesome-openclaw-skills"
  return 0
}

emit_store_suggestions() {
  local thost="${1:-generic}"
  echo ""
  echo "  🛍️ 官方/生态入口建议（供 AI 给出确定性的下一步来源建议）:"
  case "$thost" in
    claude)
      echo "  - 首选入口: OpenCode Skills / Rules（跨宿主 skill 与规则设计最接近 Claude 项目工作流）"
      echo "  - 生态补充: OpenClaw 生态技能榜（适合找现成跨宿主技能，再做兼容性体检）"
      echo "  - 兼容性基线: Claude Code 官方概览 / 记忆文档（核对项目级 CLAUDE.md、记忆与规则行为）"
      ;;
    codex)
      echo "  - 首选入口: Codex CLI 官方指南（先确认宿主约束、项目级记忆与执行方式）"
      echo "  - 生态补充: OpenCode Skills / OpenClaw 生态技能榜（补现成 skill 思路与可迁移技能）"
      ;;
    openclaw)
      echo "  - 首选入口: OpenClaw 生态技能榜（直接找生态里可复用技能）"
      echo "  - 官方补充: OpenCode Skills / Rules（同类宿主，适合迁移规则与技能结构）"
      ;;
    *)
      echo "  - 首选入口: OpenCode Skills / Rules（通用型 skills/rules 资料最集中）"
      echo "  - 生态补充: OpenClaw 生态技能榜（适合找跨宿主可迁移技能）"
      ;;
  esac
  echo "  - 本地最高命中来源: 优先参考“外部储备库雷达”里已经扫描到的库，再决定从哪里 steal"
  return 0
}

web_sources_for_host() {
  case "$1" in
    claude)
      cat <<'EOF'
Claude Code 概览|https://code.claude.com/docs/en/overview
Claude Code 记忆|https://code.claude.com/docs/en/memory
OpenCode Skills|https://opencode.ai/docs/skills
OpenCode Rules|https://opencode.ai/docs/rules
OpenClaw 生态技能榜|https://raw.githubusercontent.com/sundial-org/awesome-openclaw-skills/main/README.md
EOF
      ;;
    codex)
      cat <<'EOF'
Codex CLI|https://developers.openai.com/codex/cli
OpenCode Skills|https://opencode.ai/docs/skills
OpenClaw 生态技能榜|https://raw.githubusercontent.com/sundial-org/awesome-openclaw-skills/main/README.md
EOF
      ;;
    openclaw)
      cat <<'EOF'
OpenCode Skills|https://opencode.ai/docs/skills
OpenCode Rules|https://opencode.ai/docs/rules
OpenClaw 生态技能榜|https://raw.githubusercontent.com/sundial-org/awesome-openclaw-skills/main/README.md
EOF
      ;;
    *)
      cat <<'EOF'
OpenCode Skills|https://opencode.ai/docs/skills
OpenCode Rules|https://opencode.ai/docs/rules
OpenClaw 生态技能榜|https://raw.githubusercontent.com/sundial-org/awesome-openclaw-skills/main/README.md
EOF
      ;;
  esac
}

fetch_web_excerpt() {
  local url="$1"
  curl -fsSL --max-time 8 "$url" 2>/dev/null | \
    sed -E 's/<(script|style)[^>]*>.*<\/(script|style)>/ /g' | \
    sed -E 's/<[^>]+>/ /g; s/&nbsp;/ /g; s/&amp;/\\&/g; s/&quot;/"/g; s/&#39;/'"'"'/g' | \
    tr '\r' '\n' | tr -s ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | \
    sed '/^[[:space:]]*$/d' | head -120 || true
}

urlencode() {
  local text="$1"
  if command -v python3 &>/dev/null; then
    python3 - <<'PY' "$text"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
    return 0
  fi
  printf '%s' "$text" | sed 's/ /%20/g'
}

skillsmp_query_for_host() {
  local host_id="$1"
  local query hints domain_terms=""
  hints=$(context_keyword_hints "$host_id")

  echo " $hints " | grep -q " sales " && domain_terms+=" sales"
  echo " $hints " | grep -q " content " && domain_terms+=" content"
  echo " $hints " | grep -q " feishu " && domain_terms+=" feishu"
  echo " $hints " | grep -q " knowledge " && domain_terms+=" knowledge"
  echo " $hints " | grep -q " browser " && domain_terms+=" research browser"
  echo " $hints " | grep -q " automation " && domain_terms+=" automation workflow"

  domain_terms=$(printf '%s\n' "$domain_terms" | awk '{seen[""]=1; out=""; for (i=1;i<=NF;i++) if (!seen[$i]++) out=out (out?" ":"") $i; print out}')

  if [ -n "$domain_terms" ]; then
    query="${domain_terms}"
  else
    case "$host_id" in
      claude)
        query="Claude Code workflow automation"
        ;;
      openclaw)
        query="OpenClaw OpenCode workflow automation"
        ;;
      codex)
        query="Codex CLI workflow automation"
        ;;
      *)
        query="agent workflow automation"
        ;;
    esac
  fi
  printf '%s' "$query"
}

fetch_skillsmp_candidates() {
  local host_id="$1"
  [ -n "${SKILLSMP_API_KEY:-}" ] || return 0
  command -v curl &>/dev/null || return 0
  local query encoded url payload ai_query
  query=$(skillsmp_query_for_host "$host_id")
  encoded=$(urlencode "$query")
  url="https://skillsmp.com/api/v1/skills/search?q=${encoded}&sortBy=stars&limit=30"
  payload=$(curl -fsSL --max-time 12 \
    -H "Authorization: Bearer ${SKILLSMP_API_KEY}" \
    "$url" 2>/dev/null || true)
  if printf '%s' "$payload" | grep -q '"skills":[[:space:]]*\[[^]]'; then
    printf '%s' "$payload"
    return 0
  fi

  ai_query="skills for ${query}"
  encoded=$(urlencode "$ai_query")
  url="https://skillsmp.com/api/v1/skills/ai-search?q=${encoded}"
  curl -fsSL --max-time 12 \
    -H "Authorization: Bearer ${SKILLSMP_API_KEY}" \
    "$url" 2>/dev/null || true
}

emit_skillsmp_candidates() {
  local host_id="$1"
  SKILLSMP_LAST_RESULT_STATE="not_run"
  SKILLSMP_TOP_STARS=0
  SKILLSMP_SECOND_STARS=0
  SKILLSMP_HIGH_CONFIDENCE_COUNT=0
  echo ""
  echo "  🧠 SkillsMP 在线候选（优先按当前身份做推荐）:"
  if [ -z "${SKILLSMP_API_KEY:-}" ]; then
    SKILLSMP_LAST_RESULT_STATE="missing_key"
    echo "  - 未检测到 SKILLSMP_API_KEY，跳过 API 推荐，继续使用网页入口。"
    return 0
  fi
  if ! command -v curl &>/dev/null; then
    SKILLSMP_LAST_RESULT_STATE="no_curl"
    echo "  - 当前环境没有 curl，无法请求 SkillsMP API。"
    return 0
  fi

  local payload
  payload=$(fetch_skillsmp_candidates "$host_id")
  if [ -z "$payload" ]; then
    SKILLSMP_LAST_RESULT_STATE="no_result"
    echo "  - SkillsMP API 当前未返回结果，继续参考网页入口。"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    local rendered marker count meta_line
    rendered=$(PAYLOAD="$payload" python3 - <<'PY'
import json, os, re, sys

raw = os.environ.get("PAYLOAD", "")
try:
    data = json.loads(raw)
except Exception:
    print("__COUNT__=0")
    print("  - SkillsMP 返回了无法解析的内容，建议稍后再试。")
    sys.exit(0)

def find_items(obj):
    if isinstance(obj, list):
        if obj and isinstance(obj[0], dict):
            return obj
        return []
    if isinstance(obj, dict):
        for key in ("data", "skills", "results", "items"):
            value = obj.get(key)
            if isinstance(value, list):
                return value
            if isinstance(value, dict):
                nested = find_items(value)
                if nested:
                    return nested
    return []

items = find_items(data)
if not items:
    print("__COUNT__=0")
    print("__META__=0|0|0")
    print("  - SkillsMP 暂时没有返回可用候选，继续参考网页入口。")
    sys.exit(0)

lines = []
printed = 0
seen = set()
star_values = []
for item in items[:25]:
    if not isinstance(item, dict):
        continue
    primary = item.get("skill") if isinstance(item.get("skill"), dict) else item
    filename = item.get("filename") or ""
    filename_hint = filename.rsplit("/", 1)[-1]
    filename_hint = re.sub(r"-skill-md\.md$", "", filename_hint)
    filename_hint = re.sub(r"\.md$", "", filename_hint)
    filename_hint = re.sub(r"^.*-skills-data-", "", filename_hint)
    name = (
        primary.get("name")
        or primary.get("title")
        or primary.get("slug")
        or item.get("name")
        or item.get("title")
        or item.get("slug")
        or filename_hint
        or "未命名技能"
    )
    desc = (
        primary.get("description")
        or primary.get("summary")
        or primary.get("excerpt")
        or item.get("description")
        or item.get("summary")
        or item.get("excerpt")
        or ""
    )
    category = (
        primary.get("category")
        or primary.get("primaryCategory")
        or item.get("category")
        or item.get("primaryCategory")
        or ""
    )
    stars = primary.get("stars")
    try:
        stars_num = int(stars) if stars is not None else 0
    except Exception:
        stars_num = 0
    author = primary.get("author") or item.get("author")
    note = []
    if category:
        note.append(str(category))
    if author:
        note.append(f"by {author}")
    if stars is not None:
        note.append(f"stars {stars}")
    suffix = f" ({', '.join(note)})" if note else ""
    norm = name.strip().lower()
    if norm in seen:
        continue
    seen.add(norm)
    star_values.append(stars_num)
    lines.append(f"  - {name}{suffix}")
    if desc:
        lines.append(f"    {str(desc)[:100]}")
    printed += 1
star_values.sort(reverse=True)
top = star_values[0] if len(star_values) > 0 else 0
second = star_values[1] if len(star_values) > 1 else 0
high = sum(1 for value in star_values if value >= 20)
print(f"__COUNT__={printed}")
print(f"__META__={top}|{second}|{high}")
if printed == 0:
    print("  - SkillsMP 暂时没有返回可读的候选条目，继续参考网页入口。")
else:
    for line in lines:
        print(line)
PY
)
    marker=$(printf '%s\n' "$rendered" | sed -n '1p')
    meta_line=$(printf '%s\n' "$rendered" | sed -n '2p')
    count="${marker#__COUNT__=}"
    rendered=$(printf '%s\n' "$rendered" | sed '1,2d')
    if [[ "$meta_line" == __META__=* ]]; then
      local meta top second high
      meta="${meta_line#__META__=}"
      IFS='|' read -r top second high <<< "$meta"
      [[ "$top" =~ ^[0-9]+$ ]] && SKILLSMP_TOP_STARS="$top"
      [[ "$second" =~ ^[0-9]+$ ]] && SKILLSMP_SECOND_STARS="$second"
      [[ "$high" =~ ^[0-9]+$ ]] && SKILLSMP_HIGH_CONFIDENCE_COUNT="$high"
    fi
    if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ]; then
      SKILLSMP_LAST_RESULT_STATE="ok"
    else
      SKILLSMP_LAST_RESULT_STATE="no_result"
    fi
    printf '%s\n' "$rendered"
    if [ "${SKILLSMP_LAST_RESULT_STATE}" = "ok" ]; then
      if [ "${SKILLSMP_TOP_STARS:-0}" -ge 50 ] && [ "${SKILLSMP_SECOND_STARS:-0}" -lt 20 ]; then
        echo "  - 热度判断: 目前只有 1 个明显高热候选，其余更像探索项；在线结果适合拿来启发，不适合一股脑优先安装。"
      elif [ "${SKILLSMP_HIGH_CONFIDENCE_COUNT:-0}" -ge 2 ]; then
        echo "  - 热度判断: 当前至少有 2 个中高热候选，在线结果可作为优先参考。"
      else
        echo "  - 热度判断: 当前在线候选整体热度一般，建议把它们当灵感清单，再优先核对本地库和官方入口。"
      fi
    fi
  else
    SKILLSMP_LAST_RESULT_STATE="no_parser"
    echo "  - 当前环境缺少 python3，无法解析 SkillsMP 返回结果。"
  fi
  return 0
}

emit_web_source_snapshots() {
  local host_id="$1"
  echo ""
  echo "  🌍 在线来源快照（act --web，供 AI 做站外候选推荐）:"
  if ! command -v curl &>/dev/null; then
    echo "  - 当前环境没有 curl，无法抓取在线来源。"
    return 0
  fi

  local label url excerpt
  while IFS='|' read -r label url; do
    [ -n "$label" ] || continue
    excerpt=$(fetch_web_excerpt "$url")
    if [ -n "$excerpt" ]; then
      echo "  --- ${label} (${url}) ---"
      printf '%s\n' "$excerpt" | sed 's/^/    /'
    else
      echo "  - ${label} (${url}) — 当前环境抓取失败，可由 AI 仅把它当作候选入口。"
    fi
    echo ""
  done < <(web_sources_for_host "$host_id")
  return 0
}

emit_external_radar() {
  local cache="$1"
  echo ""
  echo "  🔭 外部储备库雷达（供补强建议参考）:"
  local radar_count=0 name dir lib_count
  while IFS=: read -r name dir lib_count; do
    [ "$dir" = "$TARGET" ] && continue
    [ "$lib_count" -lt 2 ] && continue
    echo "  - ${name} ($(short_path "$dir"), 约有 ${lib_count} 个技能待发掘)"
    radar_count=$((radar_count + 1))
    [ "$radar_count" -ge 8 ] && break
  done < "$cache"
  return 0
}
