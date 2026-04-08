SKILLSMP_LAST_RESULT_STATE="not_run"
SKILLSMP_TOP_STARS=0
SKILLSMP_SECOND_STARS=0
SKILLSMP_HIGH_CONFIDENCE_COUNT=0
SKILLSMP_TOP_NAME=""
ACT_LOCAL_PRIMARY_SOURCE=""
ACT_LOCAL_PRIMARY_SOURCE_DISPLAY=""
ACT_LOCAL_PRIMARY_SKILL=""
ACT_LOCAL_PRIMARY_REASON=""
ACT_LOCAL_PRIMARY_MISSING=0
ACT_LOCAL_PRIMARY_PREVIEW=""
ACT_LOCAL_SOURCE_COUNT=0
ACT_LOCAL_SUMMARY_FILE=""
ACT_TRENDING_STATE="not_run"
ACT_TRENDING_SOURCE_PATH=""
ACT_TRENDING_PRIMARY_NAME=""
ACT_TRENDING_PRIMARY_URL=""
ACT_TRENDING_MATCH_MODE="trend"
ACT_GITHUB_SEARCH_STATE="not_run"
ACT_GITHUB_SEARCH_TOP_NAME=""
ACT_GITHUB_SEARCH_TOP_URL=""

unique_words() {
  printf '%s\n' "$1" | awk '{
    out=""
    for (i=1;i<=NF;i++) {
      if (!seen[$i]++) out=out (out?" ":"") $i
    }
    print out
  }'
}

intent_keyword_hints() {
  local text="$1" hints=""
  text=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  [ -n "$text" ] || return 0

  echo "$text" | grep -qE "飞书|feishu|lark|wiki|知识库|doc|docs|文档" && hints+=" feishu lark wiki doc docs knowledge"
  echo "$text" | grep -qE "记忆|memory|knowledge|知识|obsidian|para" && hints+=" memory knowledge"
  echo "$text" | grep -qE "邮件|邮箱|mail|email|imap|smtp" && hints+=" email mail"
  echo "$text" | grep -qE "浏览器|browser|网页|web|网站|search|搜索|爬" && hints+=" browser search web"
  echo "$text" | grep -qE "研究|research|论文|paper|学术|arxiv|citation" && hints+=" research academic arxiv"
  echo "$text" | grep -qE "图片|图像|image|绘图|插画|illustrator|design" && hints+=" image design illustration"
  echo "$text" | grep -qE "视频|audio|音频|whisper|语音|字幕|ffmpeg" && hints+=" video audio whisper"
  echo "$text" | grep -qE "写作|内容|content|blog|writer|copy|公众号|小红书" && hints+=" content writing copy"
  echo "$text" | grep -qE "自动化|automation|workflow|cron|agent" && hints+=" automation workflow agent"
  echo "$text" | grep -qE "github|git|代码|coding|code|开发|dev" && hints+=" github git code dev"

  unique_words "$hints"
}

combined_recommendation_hints() {
  local host_hints="$1" intent_query="$2" intent_hints
  intent_hints=$(intent_keyword_hints "$intent_query")
  unique_words "$host_hints $intent_hints"
}

score_candidate_hint_match() {
  local name="$1" desc_text="$2" hints="$3" raw_query="${4:-}"
  local text score=0 hint compact_query
  text=$(printf '%s %s' "$name" "$desc_text" | tr '[:upper:]' '[:lower:]')
  for hint in $hints; do
    [ -n "$hint" ] || continue
    if printf '%s' "$text" | grep -qi "$hint"; then
      score=$((score + 4))
    fi
  done
  compact_query=$(printf '%s' "$raw_query" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //; s/ $//')
  if [ -n "$compact_query" ] && [ "${#compact_query}" -ge 3 ]; then
    if printf '%s' "$text" | grep -Fqi "$compact_query"; then
      score=$((score + 8))
    fi
  fi
  printf '%s' "$score"
}

candidate_fit_reason() {
  local hint_score="$1" candidate_risk="$2" intent_query="${3:-}"
  if [ "$hint_score" -gt 0 ] && [ -n "$intent_query" ] && [ "$candidate_risk" -eq 0 ]; then
    echo "和你刚提的需求更贴近，而且看起来更容易直接落地"
  elif [ "$hint_score" -gt 0 ] && [ -n "$intent_query" ]; then
    echo "和你刚提的需求更贴近，但偷过来前建议先做路线体检"
  elif [ "$hint_score" -gt 0 ] && [ "$candidate_risk" -eq 0 ]; then
    echo "和当前主题更贴近，而且看起来更容易直接落地"
  elif [ "$hint_score" -gt 0 ]; then
    echo "和当前主题更贴近，但偷过来前建议先做路线体检"
  elif [ "$candidate_risk" -eq 0 ]; then
    echo "本地已存在、现在就能评估，动手成本最低"
  else
    echo "本地能拿来试，但要先确认宿主兼容"
  fi
}

find_scanned_skill_dir() {
  local cache="$1" skill_name="$2"
  local source_name source_dir source_count
  while IFS=: read -r source_name source_dir source_count; do
    [ -d "${source_dir}/${skill_name}" ] || continue
    [ -f "${source_dir}/${skill_name}/SKILL.md" ] || continue
    printf '%s' "${source_dir}/${skill_name}"
    return 0
  done < "$cache"
  return 1
}

collect_local_candidates() {
  local cache="$1" thost="$2" intent_query="${3:-}"
  local hints query_hints installed summary_file
  local source_name source_dir source_count display_name
  local entry name desc_text candidate_risk hint_score candidate_score
  local missing_count capped_missing source_score best_skill best_reason best_score
  local preview_names=() preview_csv=""
  ACT_LOCAL_PRIMARY_SOURCE=""
  ACT_LOCAL_PRIMARY_SOURCE_DISPLAY=""
  ACT_LOCAL_PRIMARY_SKILL=""
  ACT_LOCAL_PRIMARY_REASON=""
  ACT_LOCAL_PRIMARY_MISSING=0
  ACT_LOCAL_PRIMARY_PREVIEW=""
  ACT_LOCAL_SOURCE_COUNT=0
  [ -n "${ACT_LOCAL_SUMMARY_FILE:-}" ] && rm -f "$ACT_LOCAL_SUMMARY_FILE"
  ACT_LOCAL_SUMMARY_FILE=""

  hints=$(context_keyword_hints "$thost")
  query_hints=$(intent_keyword_hints "$intent_query")
  installed=$(mktemp)
  summary_file=$(mktemp)
  ACT_LOCAL_SUMMARY_FILE="$summary_file"
  for entry in "$TARGET"/*; do
    [ -d "$entry" ] && [ -f "${entry}/SKILL.md" ] && basename "$entry"
  done | sort > "$installed"

  while IFS=: read -r source_name source_dir source_count; do
    [ "$source_dir" = "$TARGET" ] && continue
    [ -d "$source_dir" ] || continue
    missing_count=0
    best_skill=""
    best_reason=""
    best_score=-999
    preview_names=()

    for entry in "$source_dir"/*; do
      [ -d "$entry" ] && [ -f "${entry}/SKILL.md" ] || continue
      name=$(basename "$entry")
      grep -qx "$name" "$installed" && continue

      missing_count=$((missing_count + 1))
      [ "${#preview_names[@]}" -lt 3 ] && preview_names+=("$name")

      desc_text=$(desc "$entry")
      candidate_risk=0

      hint_score=$(score_candidate_hint_match "$name" "$desc_text" "$hints")
      if [ -n "$query_hints" ]; then
        local query_score
        query_score=$(score_candidate_hint_match "$name" "$desc_text" "$query_hints" "$intent_query")
        hint_score=$((hint_score + query_score * 2))
      fi
      candidate_score="$hint_score"
      [ "$candidate_risk" -eq 0 ] && candidate_score=$((candidate_score + 2))

      if [ "$candidate_score" -gt "$best_score" ]; then
        best_score="$candidate_score"
        best_skill="$name"
        best_reason=$(candidate_fit_reason "$hint_score" "$candidate_risk" "$intent_query")
      fi
    done

    [ "$missing_count" -gt 0 ] || continue
    ACT_LOCAL_SOURCE_COUNT=$((ACT_LOCAL_SOURCE_COUNT + 1))
    capped_missing=$missing_count
    [ "$capped_missing" -gt 20 ] && capped_missing=20
    source_score=$((best_score * 10 + capped_missing))
    display_name=$(source_display_name "$source_name" "$source_dir" "$cache")
    if [ -n "$best_skill" ]; then
      local ordered_preview=("$best_skill") preview_name
      for preview_name in "${preview_names[@]+"${preview_names[@]}"}"; do
        [ "$preview_name" = "$best_skill" ] && continue
        ordered_preview+=("$preview_name")
      done
      preview_csv=$(csv_from_args "${ordered_preview[@]+"${ordered_preview[@]}"}")
    else
      preview_csv=$(csv_from_args "${preview_names[@]+"${preview_names[@]}"}")
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$source_score" "$missing_count" "$source_name" "$display_name" \
      "$best_skill" "$best_reason" "$preview_csv" >> "$summary_file"
  done < "$cache"

  if [ ! -s "$summary_file" ]; then
    rm -f "$installed" "$summary_file"
    ACT_LOCAL_SUMMARY_FILE=""
    return 0
  fi

  IFS=$'\t' read -r source_score missing_count source_name display_name best_skill best_reason preview_csv < <(
    sort -t$'\t' -k1,1rn -k2,2rn "$summary_file" | head -1
  )
  ACT_LOCAL_PRIMARY_SOURCE="$source_name"
  ACT_LOCAL_PRIMARY_SOURCE_DISPLAY="$display_name"
  ACT_LOCAL_PRIMARY_SKILL="$best_skill"
  ACT_LOCAL_PRIMARY_REASON="$best_reason"
  ACT_LOCAL_PRIMARY_MISSING="$missing_count"
  ACT_LOCAL_PRIMARY_PREVIEW="$preview_csv"

  rm -f "$installed"
}

emit_local_candidates() {
  local cache="$1" thost="$2" intent_query="${3:-}"
  local source_score missing_count source_name display_name best_skill best_reason preview_csv
  echo ""
  echo "  🏠 本地候选建议（优先偷本机已验证来源）:"
  collect_local_candidates "$cache" "$thost" "$intent_query"
  if [ -z "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
    echo "  - 当前本地库里暂时没有明显没装的新候选，下一步更适合看在线雷达。"
    return 0
  fi

  local shown=0
  while IFS=$'\t' read -r source_score missing_count source_name display_name best_skill best_reason preview_csv; do
    shown=$((shown + 1))
    echo "  - ${display_name} — ${missing_count} 个你还没有；先看 ${preview_csv}"
    if [ -n "$best_skill" ]; then
      echo "    优先预览: ${best_skill}（${best_reason}）"
    fi
    [ "$shown" -ge 3 ] && break
  done < <(sort -t$'\t' -k1,1rn -k2,2rn "$ACT_LOCAL_SUMMARY_FILE")

  rm -f "$ACT_LOCAL_SUMMARY_FILE"
  ACT_LOCAL_SUMMARY_FILE=""
}

collect_github_trending_radar() {
  local cache="$1" intent_query="${2:-}"
  local skill_dir script_path payload rendered query_hints
  ACT_TRENDING_STATE="missing"
  ACT_TRENDING_SOURCE_PATH=""
  ACT_TRENDING_PRIMARY_NAME=""
  ACT_TRENDING_PRIMARY_URL=""
  ACT_TRENDING_MATCH_MODE="trend"

  skill_dir=$(find_scanned_skill_dir "$cache" "github-trending-cn" || true)
  [ -n "$skill_dir" ] || return 0
  ACT_TRENDING_SOURCE_PATH="$skill_dir"

  script_path="${skill_dir}/scripts/github_trending.py"
  if [ ! -f "$script_path" ] || ! command -v python3 >/dev/null 2>&1; then
    ACT_TRENDING_STATE="unavailable"
    return 0
  fi

  query_hints=$(intent_keyword_hints "$intent_query")
  payload=$(python3 "$script_path" --period weekly --limit 5 --json 2>/dev/null || true)
  if [ -z "$payload" ]; then
    ACT_TRENDING_STATE="limited"
    return 0
  fi

  rendered=$(PAYLOAD="$payload" QUERY_HINTS="$query_hints" QUERY_TEXT="$intent_query" python3 - <<'PY'
import json, os, sys

raw = os.environ.get("PAYLOAD", "")
query_hints = [item for item in os.environ.get("QUERY_HINTS", "").split() if item]
query_text = os.environ.get("QUERY_TEXT", "").strip().lower()
try:
    data = json.loads(raw)
except Exception:
    print("__STATE__=limited")
    sys.exit(0)

if not isinstance(data, list) or not data:
    print("__STATE__=limited")
    sys.exit(0)

def score(item):
    text = " ".join(
        str(part or "")
        for part in [
            item.get("name", ""),
            item.get("description", ""),
            item.get("language", ""),
            " ".join(item.get("topics") or []),
        ]
    ).lower()
    total = 0
    for hint in query_hints:
        if hint and hint in text:
            total += 4
    if query_text and len(query_text) >= 3 and query_text in text:
        total += 8
    return total

mode = "trend"
items = list(data)
if query_hints or query_text:
    scored = []
    for idx, item in enumerate(items):
        score_value = score(item)
        stars = int(item.get("stars", 0) or 0)
        scored.append((score_value, stars, -idx, item))
    matched = [row for row in scored if row[0] > 0]
    if matched:
        mode = "intent"
        items = [row[3] for row in sorted(matched, reverse=True)]

first = items[0]
print("__STATE__=ok")
print(f"__MODE__={mode}")
print(first.get("name", ""))
print(first.get("url", ""))
for item in items[:3]:
    name = item.get("name", "")
    url = item.get("url", "")
    lang = item.get("language") or "N/A"
    stars = item.get("stars", 0)
    desc = item.get("description") or ""
    if len(desc) > 70:
        desc = desc[:67] + "..."
    print(f"{name}|{lang}|{stars}|{url}|{desc}")
PY
)

  case "$(printf '%s\n' "$rendered" | sed -n '1p')" in
    "__STATE__=ok")
      ACT_TRENDING_STATE="ok"
      ACT_TRENDING_MATCH_MODE=$(printf '%s\n' "$rendered" | sed -n '2p')
      ACT_TRENDING_MATCH_MODE="${ACT_TRENDING_MATCH_MODE#__MODE__=}"
      ACT_TRENDING_PRIMARY_NAME=$(printf '%s\n' "$rendered" | sed -n '3p')
      ACT_TRENDING_PRIMARY_URL=$(printf '%s\n' "$rendered" | sed -n '4p')
      printf '%s\n' "$rendered" | sed '1,4d'
      ;;
    *)
      ACT_TRENDING_STATE="limited"
      ;;
  esac
}

emit_github_trending_radar() {
  local cache="$1" intent_query="${2:-}"
  local tmp_file name lang stars url desc
  tmp_file=$(mktemp)
  collect_github_trending_radar "$cache" "$intent_query" > "$tmp_file"
  echo ""
  if [ -n "$intent_query" ]; then
    echo "  🛰️ 趋势雷达（自动接入 github-trending-cn，并按当前需求重排）:"
  else
    echo "  🛰️ 趋势雷达（自动接入 github-trending-cn）:"
  fi
  case "$ACT_TRENDING_STATE" in
    missing)
      echo "  - 当前没检测到 github-trending-cn，先只用本地库和官方入口做发现。"
      ;;
    unavailable)
      echo "  - 已检测到 github-trending-cn，但当前环境缺少可执行条件，先只把它当备用发现源。"
      ;;
    limited)
      echo "  - 已检测到 github-trending-cn，但当前 GitHub API 限额或鉴权不足，先把它当备用雷达。"
      ;;
    ok)
      local shown=0
      while IFS='|' read -r name lang stars url desc; do
        [ -n "$name" ] || continue
        shown=$((shown + 1))
        echo "  - ${name} (${lang}, stars ${stars})"
        [ -n "$desc" ] && echo "    ${desc}"
        [ "$shown" -ge 3 ] && break
      done < "$tmp_file"
      if [ "$ACT_TRENDING_MATCH_MODE" = "intent" ]; then
        echo "  - 这些是按你当前需求从热门仓库里筛出来的探索项；真要装，仍回到 check / steal 做判断。"
      else
        echo "  - 这些线索只当探索项；真要装，仍回到 check / steal 做判断。"
      fi
      ;;
  esac
  rm -f "$tmp_file"
}

github_search_query_for_intent() {
  local intent_query="$1" query_hints
  query_hints=$(intent_keyword_hints "$intent_query")
  if [ -n "$query_hints" ]; then
    unique_words "$intent_query $query_hints"
  else
    printf '%s' "$intent_query"
  fi
}

collect_github_search_radar() {
  local intent_query="${1:-}"
  local query encoded url payload
  local curl_args=(
    -fsSL
    --max-time 12
    -H "Accept: application/vnd.github+json"
    -H "User-Agent: skill-manager"
  )
  ACT_GITHUB_SEARCH_STATE="missing_query"
  ACT_GITHUB_SEARCH_TOP_NAME=""
  ACT_GITHUB_SEARCH_TOP_URL=""
  [ -n "$intent_query" ] || return 0

  if ! command -v curl >/dev/null 2>&1; then
    ACT_GITHUB_SEARCH_STATE="no_curl"
    return 0
  fi

  query=$(github_search_query_for_intent "$intent_query")
  [ -n "$query" ] || return 0
  encoded=$(urlencode "$query")
  url="https://api.github.com/search/repositories?q=${encoded}&sort=stars&order=desc&per_page=5"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  payload=$(curl "${curl_args[@]}" "$url" 2>/dev/null || true)

  if [ -z "$payload" ]; then
    ACT_GITHUB_SEARCH_STATE="no_result"
    return 0
  fi

  PAYLOAD="$payload" python3 - <<'PY'
import json, os, sys

raw = os.environ.get("PAYLOAD", "")
try:
    data = json.loads(raw)
except Exception:
    print("__STATE__=no_result")
    sys.exit(0)

items = data.get("items") if isinstance(data, dict) else None
if not isinstance(items, list) or not items:
    message = data.get("message", "") if isinstance(data, dict) else ""
    if "rate limit" in message.lower():
        print("__STATE__=limited")
    else:
        print("__STATE__=no_result")
    sys.exit(0)

first = items[0]
print("__STATE__=ok")
print(first.get("full_name", ""))
print(first.get("html_url", ""))
for item in items[:3]:
    name = item.get("full_name", "")
    url = item.get("html_url", "")
    lang = item.get("language") or "N/A"
    stars = item.get("stargazers_count", 0)
    desc = item.get("description") or ""
    if len(desc) > 70:
        desc = desc[:67] + "..."
    print(f"{name}|{lang}|{stars}|{url}|{desc}")
PY
}

emit_github_search_radar() {
  local intent_query="${1:-}"
  local tmp_file name lang stars url desc
  [ -n "$intent_query" ] || return 0
  tmp_file=$(mktemp)
  collect_github_search_radar "$intent_query" > "$tmp_file"
  ACT_GITHUB_SEARCH_STATE=$(sed -n '1p' "$tmp_file")
  ACT_GITHUB_SEARCH_TOP_NAME=$(sed -n '2p' "$tmp_file")
  ACT_GITHUB_SEARCH_TOP_URL=$(sed -n '3p' "$tmp_file")
  ACT_GITHUB_SEARCH_STATE="${ACT_GITHUB_SEARCH_STATE#__STATE__=}"
  echo ""
  echo "  🔎 GitHub 需求雷达（按当前需求搜仓库）:"
  case "$ACT_GITHUB_SEARCH_STATE" in
    missing_query)
      echo "  - 当前没有显式需求，先不启用 GitHub 需求搜索。"
      ;;
    no_curl)
      echo "  - 当前环境没有 curl，跳过 GitHub 需求搜索。"
      ;;
    limited)
      echo "  - GitHub 搜索当前遇到限额，先把它当备用来源。"
      ;;
    ok)
      while IFS='|' read -r name lang stars url desc; do
        [ -n "$name" ] || continue
        echo "  - ${name} (${lang}, stars ${stars})"
        [ -n "$desc" ] && echo "    ${desc}"
      done < <(sed '1,3d' "$tmp_file")
      echo "  - 这些是按你当前需求搜出来的仓库线索；真要装，仍回到 check / steal 做判断。"
      ;;
    *)
      echo "  - 这轮没有搜到明显相关的 GitHub 仓库，先以本地候选和 SkillsMP 为主。"
      ;;
  esac
  rm -f "$tmp_file"
}

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
  echo "  - 本地优先: 先看上面的本地候选建议，再决定下一步从哪里 check / steal"
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
  local host_id="$1" intent_query="${2:-}"
  local query hints domain_terms="" query_hints
  hints=$(context_keyword_hints "$host_id")
  query_hints=$(intent_keyword_hints "$intent_query")

  echo " $hints " | grep -q " sales " && domain_terms+=" sales"
  echo " $hints " | grep -q " content " && domain_terms+=" content"
  echo " $hints " | grep -q " feishu " && domain_terms+=" feishu"
  echo " $hints " | grep -q " knowledge " && domain_terms+=" knowledge"
  echo " $hints " | grep -q " browser " && domain_terms+=" research browser"
  echo " $hints " | grep -q " automation " && domain_terms+=" automation workflow"

  domain_terms=$(printf '%s\n' "$domain_terms" | awk '{seen[""]=1; out=""; for (i=1;i<=NF;i++) if (!seen[$i]++) out=out (out?" ":"") $i; print out}')

  if [ -n "$intent_query" ]; then
    query=$(unique_words "$intent_query $query_hints $domain_terms")
  elif [ -n "$domain_terms" ]; then
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
  local host_id="$1" intent_query="${2:-}"
  [ -n "${SKILLSMP_API_KEY:-}" ] || return 0
  command -v curl &>/dev/null || return 0
  local query encoded url payload ai_query
  query=$(skillsmp_query_for_host "$host_id" "$intent_query")
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
  local host_id="$1" intent_query="${2:-}"
  SKILLSMP_LAST_RESULT_STATE="not_run"
  SKILLSMP_TOP_STARS=0
  SKILLSMP_SECOND_STARS=0
  SKILLSMP_HIGH_CONFIDENCE_COUNT=0
  SKILLSMP_TOP_NAME=""
  echo ""
  if [ -n "$intent_query" ]; then
    echo "  🧠 SkillsMP 在线候选（身份打底，再按当前需求补排序）:"
  else
    echo "  🧠 SkillsMP 在线候选（优先按当前身份做推荐）:"
  fi
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
  payload=$(fetch_skillsmp_candidates "$host_id" "$intent_query")
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
    print("__META__=0|0|0")
    print("")
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
    print("")
    print("  - SkillsMP 暂时没有返回可用候选，继续参考网页入口。")
    sys.exit(0)

lines = []
printed = 0
seen = set()
star_values = []
top_name = ""
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
    if not top_name:
        top_name = name
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
print(top_name)
if printed == 0:
    print("  - SkillsMP 暂时没有返回可读的候选条目，继续参考网页入口。")
else:
    for line in lines:
        print(line)
PY
)
    marker=$(printf '%s\n' "$rendered" | sed -n '1p')
    meta_line=$(printf '%s\n' "$rendered" | sed -n '2p')
    SKILLSMP_TOP_NAME=$(printf '%s\n' "$rendered" | sed -n '3p')
    count="${marker#__COUNT__=}"
    rendered=$(printf '%s\n' "$rendered" | sed '1,3d')
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
  echo "  🌍 在线来源快照（无强 API 命中时的备用雷达）:"
  local label url
  while IFS='|' read -r label url; do
    [ -n "$label" ] || continue
    echo "  - ${label} (${url}) — 先把它当候选入口，需要时再深挖。"
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
