emit_route_check() {
  local src_dir="$1" src_name="$2" thost="$3" thost_label="$4"
  local candidate_count=0 duplicate_count=0 risky_count=0 source_issue_count=0
  local duplicate_names=() risky_notes="" source_notes=""
  local entry name content host_notes

  echo ""
  echo "  🧪 偷取路线体检：${src_name} -> $(friendly_target)"

  for entry in "$src_dir"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=$(basename "$entry")
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      source_issue_count=$((source_issue_count + 1))
      source_notes+="\n  ${R}🔴${N} ${name} — 来源里是坏链，偷过来也不稳"
      continue
    fi
    [ -d "$entry" ] || continue
    if [ ! -f "${entry}/SKILL.md" ]; then
      source_issue_count=$((source_issue_count + 1))
      source_notes+="\n  ${R}🔴${N} ${name} — 来源缺 SKILL.md，不建议直接偷"
      continue
    fi

    candidate_count=$((candidate_count + 1))
    if [ -e "${TARGET}/${name}" ] || [ -L "${TARGET}/${name}" ]; then
      duplicate_count=$((duplicate_count + 1))
      duplicate_names+=("$name")
      continue
    fi

    content=$(tr '[:upper:]' '[:lower:]' < "${entry}/SKILL.md" 2>/dev/null)
    host_notes=$(cross_host_notes "$content" "$thost" "$thost_label")
    if [ -n "$host_notes" ]; then
      risky_count=$((risky_count + 1))
      risky_notes+="\n  ${Y}🟡${N} ${name}${host_notes}"
    fi
  done

  echo "  - 来源可评估技能: ${candidate_count}"
  echo "  - 目标已存在同名: ${duplicate_count}"
  echo "  - 迁移后宿主适配风险: ${risky_count}"
  echo "  - 来源自身结构问题: ${source_issue_count}"

  if [ "$source_issue_count" -gt 0 ]; then
    echo ""
    echo "  来源问题（偷之前要知道）:"
    echo -e "$source_notes"
  fi

  if [ "$duplicate_count" -gt 0 ]; then
    echo ""
    echo "  同名占位（偷之后不会新增这些）:"
    printf '  - %s\n' "${duplicate_names[@]}" | head -12
  fi

  if [ "$risky_count" -gt 0 ]; then
    echo ""
    echo "  宿主兼容风险（偷过去后要留意）:"
    echo -e "$risky_notes"
  fi

  if [ "$candidate_count" -gt 0 ] && [ "$source_issue_count" -eq 0 ] && [ "$risky_count" -eq 0 ]; then
    echo ""
    echo -e "  ${G}✓ 这条偷取路线整体比较干净，可优先偷取${N}"
  fi
  return 0
}

emit_skill_inventory() {
  echo ""
  echo "  📚 当前已装技能清单（供升级建议参考）:"
  local d name sdesc count=0
  for d in "$TARGET"/*/; do
    [ -d "$d" ] && [ -f "${d}SKILL.md" ] || continue
    name=$(basename "$d")
    sdesc=$(desc "$d")
    [ -z "$sdesc" ] && sdesc="(无描述)"
    printf "  - %-30s : %s\n" "$name" "$sdesc"
    count=$((count + 1))
  done
  echo ""
  echo -e "  ✅ 共 ${B}${count}${N} 个有效技能。"
  return 0
}

installed_skill_count() {
  local count=0 d
  for d in "$TARGET"/*/; do
    [ -d "$d" ] && [ -f "${d}SKILL.md" ] || continue
    count=$((count + 1))
  done
  printf '%s' "$count"
}

install_hint() {
  local tool="$1" platform="$2"
  case "${tool}:${platform}" in
    ffmpeg:macos) echo "brew install ffmpeg" ;;
    ffmpeg:linux|ffmpeg:wsl) echo "sudo apt install ffmpeg" ;;
    ffmpeg:windows) echo "winget install Gyan.FFmpeg" ;;
    1password-cli:macos) echo "brew install 1password-cli" ;;
    1password-cli:linux|1password-cli:wsl) echo "sudo apt install 1password-cli" ;;
    1password-cli:windows) echo "winget install AgileBits.1Password.CLI" ;;
    pandoc:macos) echo "brew install pandoc" ;;
    pandoc:linux|pandoc:wsl) echo "sudo apt install pandoc" ;;
    pandoc:windows) echo "winget install JohnMacFarlane.Pandoc" ;;
    obsidian-cli:macos) echo "brew install obsidian-cli" ;;
    obsidian-cli:linux|obsidian-cli:wsl) echo "请按 obsidian-cli 官方说明安装" ;;
    obsidian-cli:windows) echo "请按 obsidian-cli 官方说明安装" ;;
    *) echo "请按官方说明安装" ;;
  esac
}

cmd_check() {
  local src_query="${1:-}"
  echo -e "${C}🔍 Check — 诊断${N}"
  echo ""
  local cache="$DATA_DIR/last_scan.txt"
  [ -f "$cache" ] || cache=$(do_scan)
  resolve_target "$cache"
  local tlabel=$(target_label)
  local thost=$(target_host_id)
  local thost_label=$(host_label_from_id "$thost")
  local src_dir="" src_name=""
  [ -d "$TARGET" ] || { echo -e "  ${R}✗${N} 目标库不存在: ${TARGET}"; return 1; }
  if [ -n "$src_query" ]; then
    src_dir=$(resolve_target_alias "$src_query" 2>/dev/null || true)
    [ -n "$src_dir" ] || src_dir=$(resolve "$src_query" "$cache")
    src_name=$(grep -F "$src_dir" "$cache" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -z "$src_name" ] && [ -n "$src_dir" ]; then
      case "$src_dir" in
        "$HOME"/*) src_name=$(label "${src_dir#$HOME/}") ;;
        /*) src_name=$(label "${src_dir#/}") ;;
        *) src_name="$src_dir" ;;
      esac
    fi
    if [ -z "$src_dir" ] || [ ! -d "$src_dir" ]; then
      echo -e "  ${R}✗${N} 找不到来源库: $src_query"
      return 1
    fi
    echo "  当前动作: 检查偷取路线 ${src_name} -> $(friendly_target)"
  else
    echo "  当前操作对象: $(friendly_target)"
  fi
  echo "  目标目录: $(short_path "$TARGET")"
  if [ -z "$src_query" ] && [ "$ACT_WEB" -eq 0 ]; then
    echo -e "  ${D}提示: check 看当前这里；check home-claude 看从全局偷到这里；check --web 会顺带去网上找候选${N}"
  fi
  emit_context_bundle "$thost" 4
  echo ""

  if [ -n "$src_dir" ]; then
    emit_route_check "$src_dir" "${src_name:-$src_query}" "$thost" "$thost_label"
    echo ""
  fi

  local to_delete=() issue_count=0
  local d name
  for d in "$TARGET"/*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    name=$(basename "$d")
    if [ -L "$d" ] && [ ! -e "$d" ]; then
      echo -e "  ${R}💀${N} $name ${D}(坏链接)${N}"
      to_delete+=("$name")
      issue_count=$((issue_count + 1))
      continue
    fi
    [ -d "$d" ] || continue
    if [ ! -f "${d}/SKILL.md" ]; then
      echo -e "  ${R}✗${N} $name ${D}(缺 SKILL.md)${N}"
      to_delete+=("$name")
      issue_count=$((issue_count + 1))
      continue
    fi
    if ! head -1 "${d}/SKILL.md" | grep -q '^---'; then
      echo -e "  ${Y}⚠${N} $name ${D}(缺 frontmatter)${N}"
      issue_count=$((issue_count + 1))
    fi
  done
  [ "$issue_count" -eq 0 ] && echo -e "  ${G}✓ 物理结构全部健康${N}"

  echo ""
  local tmpfile found=0
  tmpfile=$(mktemp)
  local cats="web-search:web.search,websearch,搜索引擎|browser:browser.auto,agent.browser,浏览器代理|screenshot:screenshot,截图,截屏|feishu:feishu,飞书|frontend:frontend,前端,ui.design|seo:seo|content:blog.writer,content.writer,copywriting,内容创作|video:video,ffmpeg,视频|image:image.gen,文生图,生成图片|research:research,调研"
  for d in "$TARGET"/*/; do
    [ -f "${d}SKILL.md" ] || continue
    name=$(basename "$d")
    local text
    text=$(echo "${name} $(desc "$d")" | tr '[:upper:]' '[:lower:]')
    IFS='|' read -ra catlist <<< "$cats"
    local cat cn kws kwl kw
    for cat in "${catlist[@]}"; do
      cn=${cat%%:*}
      kws=${cat##*:}
      IFS=',' read -ra kwl <<< "$kws"
      for kw in "${kwl[@]}"; do
        echo "$text" | grep -qi "${kw//./ }" && echo "${cn}|${name}" >> "$tmpfile" && break
      done
    done
  done
  local cn m cnt s
  for cn in $(cut -d'|' -f1 "$tmpfile" 2>/dev/null | sort -u); do
    m=$(grep "^${cn}|" "$tmpfile" | cut -d'|' -f2 | sort -u)
    cnt=$(echo "$m" | wc -l | tr -d ' ')
    if [ "$cnt" -gt 1 ]; then
      echo -e "  ${Y}⚠ ${cn}${N} ${D}(疑似存在 ${cnt} 个功能重叠)${N}"
      while read -r s; do
        [ -n "$s" ] && echo -e "    ${D}-${N} $s"
      done <<< "$m"
      found=1
    fi
  done
  [ "$found" -eq 0 ] && echo -e "  ${G}✓ 无分类冲突${N}"
  rm -f "$tmpfile"

  echo ""
  echo -e "${C}⚡ 运行时依赖检查${N}"
  echo ""

  local current_platform="unknown"
  current_platform=$(platform_id)

  local ready_skills=() easy_fix_skills="" hard_fix_skills=""
  local ready_count=0 easy_count=0 hard_count=0
  local skill_name skill_file skill_content risk_level risk_notes host_notes

  for d in "$TARGET"/*/; do
    [ -f "${d}SKILL.md" ] || continue
    skill_name=$(basename "$d")
    skill_file="${d}SKILL.md"
    skill_content=$(cat "$skill_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    risk_level=0
    risk_notes=""

    if echo "$skill_content" | grep -qE "ffmpeg"; then
      if ! command -v ffmpeg &>/dev/null; then
        risk_notes+="\n    ${Y}•${N} 需: ffmpeg (未安装)"
        risk_notes+="\n      ${D}└─ 修复: $(install_hint ffmpeg "$current_platform")${N}"
        risk_level=$((risk_level > 1 ? risk_level : 1))
      fi
    fi
    if echo "$skill_content" | grep -qE "1password|\"op\"| \"op "; then
      if ! command -v op &>/dev/null; then
        risk_notes+="\n    ${Y}•${N} 需: 1Password CLI (未安装)"
        risk_notes+="\n      ${D}└─ 修复: $(install_hint 1password-cli "$current_platform")${N}"
        risk_level=$((risk_level > 1 ? risk_level : 1))
      fi
    fi
    if echo "$skill_content" | grep -qE "pandoc"; then
      if ! command -v pandoc &>/dev/null; then
        risk_notes+="\n    ${Y}•${N} 需: pandoc (未安装)"
        risk_notes+="\n      ${D}└─ 修复: $(install_hint pandoc "$current_platform")${N}"
        risk_level=$((risk_level > 1 ? risk_level : 1))
      fi
    fi
    if echo "$skill_content" | grep -qE "obsidian-cli"; then
      if ! command -v obsidian-cli &>/dev/null; then
        risk_notes+="\n    ${Y}•${N} 需: obsidian-cli (未安装)"
        risk_notes+="\n      ${D}└─ 修复: $(install_hint obsidian-cli "$current_platform")${N}"
        risk_level=$((risk_level > 1 ? risk_level : 1))
      fi
    fi
    if echo "$skill_content" | grep -qiE "openai.*key|openai_api_key"; then
      if [ -z "${OPENAI_API_KEY:-}" ]; then
        risk_notes+="\n    ${R}•${N} 需: OpenAI API 密钥 (未设置)"
        risk_notes+="\n      ${D}└─ 获取: 访问 platform.openai.com 注册获取${N}"
        risk_level=$((risk_level > 2 ? risk_level : 2))
      fi
    fi
    if echo "$skill_content" | grep -qiE "seedream.*key|seedream_api_key"; then
      if [ -z "${SEEDREAM_API_KEY:-}" ]; then
        risk_notes+="\n    ${R}•${N} 需: 豆包 Seedream API 密钥 (未设置)"
        risk_notes+="\n      ${D}└─ 获取: 访问 doubao.com 获取${N}"
        risk_level=$((risk_level > 2 ? risk_level : 2))
      fi
    fi
    if echo "$skill_content" | grep -qiE "trello.*key|trello_api_key"; then
      if [ -z "${TRELLO_API_KEY:-}" ]; then
        risk_notes+="\n    ${R}•${N} 需: Trello API Key (未设置)"
        risk_notes+="\n      ${D}└─ 获取: 访问 trello.com/app-key${N}"
        risk_level=$((risk_level > 2 ? risk_level : 2))
      fi
    fi
    if echo "$skill_content" | grep -qE "53699|autoglm"; then
      if ! curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:53699" 2>/dev/null; then
        risk_notes+="\n    ${R}•${N} 需: AutoGLM 本地服务 (端口 53699 不可达)"
        risk_notes+="\n      ${D}└─ 修复: 运行 AutoGLM 客户端启动服务${N}"
        risk_level=$((risk_level > 2 ? risk_level : 2))
      fi
    fi
    if echo "$skill_content" | grep -qE "11434|ollama"; then
      if ! curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:11434" 2>/dev/null; then
        risk_notes+="\n    ${Y}•${N} 需: Ollama 本地服务 (端口 11434 不可达)"
        risk_notes+="\n      ${D}└─ 修复: 运行 ollama serve 启动${N}"
        risk_level=$((risk_level > 1 ? risk_level : 1))
      fi
    fi
    if echo "$skill_content" | grep -qiE "macos|darwin|apple|仅.*mac|mac.*only"; then
      if [ "$current_platform" != "macos" ]; then
        risk_notes+="\n    ${R}•${N} 平台限制: 仅支持 macOS (当前: $current_platform)"
        risk_notes+="\n      ${D}└─ 建议: 移除此技能或在 macOS 环境使用${N}"
        risk_level=2
      fi
    fi
    if echo "$skill_content" | grep -qiE "(微信|wechat).*解密|微信.*hook"; then
      risk_notes+="\n    ${R}•${N} 注意: 涉及微信数据解密，可能需要额外权限"
      risk_level=$((risk_level > 1 ? risk_level : 1))
    fi

    host_notes=$(cross_host_notes "$skill_content" "$thost" "$thost_label")
    if [ -n "$host_notes" ]; then
      risk_notes+="$host_notes"
      risk_level=$((risk_level > 1 ? risk_level : 1))
    fi

    if [ "$risk_level" -eq 0 ]; then
      ready_skills+=("$skill_name")
      ready_count=$((ready_count + 1))
    elif [ "$risk_level" -eq 1 ]; then
      easy_fix_skills+="\n  ${Y}🟡${N} $skill_name"
      easy_fix_skills+="$risk_notes"
      easy_count=$((easy_count + 1))
    else
      hard_fix_skills+="\n  ${R}🔴${N} $skill_name"
      hard_fix_skills+="$risk_notes"
      hard_count=$((hard_count + 1))
    fi
  done

  echo -e "  ${G}🟢 当前看起来可用${N} (${ready_count}个) — 依赖检查未发现明显阻塞"
  echo -n "     "
  if [ ${#ready_skills[@]} -gt 0 ]; then
    printf '%s\n' "${ready_skills[@]}" | head -10 | tr '\n' ' '
  fi
  [ "$ready_count" -gt 10 ] && echo -n "...等${ready_count}个"
  echo ""

  if [ "$easy_count" -gt 0 ]; then
    echo ""
    echo -e "  ${Y}🟡 需简单配置${N} (${easy_count}个) — ${Y}运行 check --yes 可清理结构问题${N}"
    echo -e "$easy_fix_skills"
  fi

  if [ "$hard_count" -gt 0 ]; then
    echo ""
    echo -e "  ${R}🔴 需用户操作${N} (${hard_count}个) — ${R}需要手动配置或受平台限制${N}"
    echo -e "$hard_fix_skills"
  fi

  echo ""
  echo -e "  ${D}💡 提示: 这里是静态体检结果。标记为可用并不等于已经实机验证通过；标记为 🔴 也不等于完全不能用，只是相关功能可能受限${N}"

  if [ "$ACT_WEB" -eq 1 ]; then
    emit_context_inventory "$thost"
    emit_skill_inventory
    collect_env "$thost" "$tlabel" "$TARGET"
    emit_official_sources
    emit_store_suggestions "$thost"
    emit_skillsmp_candidates "$thost"
    emit_web_source_snapshots "$thost"
    emit_external_radar "$cache"
  fi

  if [ ${#to_delete[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${Y}💡 建议删除 ${issue_count} 个问题技能${N}"
    if [ "$AUTO_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
      for name in "${to_delete[@]}"; do
        if [ "$DRY_RUN" -eq 1 ]; then
          echo -e "  ${D}rm ${name} (预览)${N}"
        else
          rm -rf "${TARGET}/${name}"
          echo -e "  ${R}✗${N} 已删除 $name"
        fi
      done
    elif [ -t 0 ]; then
      echo -n "  确认删除？[y/N] "
      read -r c
      if [[ "$c" =~ ^[Yy]$ ]]; then
        for name in "${to_delete[@]}"; do
          rm -rf "${TARGET}/${name}"
          echo -e "  ${R}✗${N} 已删除 $name"
        done
      fi
    else
      echo -e "  ${D}加 --yes 自动删除${N}"
    fi
  fi
  return 0
}
