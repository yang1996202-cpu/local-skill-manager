copy_skill_dir() {
  local src_dir="$1" dest_dir="$2"
  rm -rf "$dest_dir"
  mkdir -p "$(dirname "$dest_dir")"
  cp -R "$src_dir" "$dest_dir"
}

compare_skill_dirs() {
  local left_dir="$1" right_dir="$2"
  diff -qr --exclude '.skill-manager-source.env' "$left_dir" "$right_dir" >/dev/null 2>&1
}

resolve_local_skill_dir() {
  local query="$1" expanded
  if [ -z "$query" ]; then
    return 1
  fi
  if looks_like_explicit_path "$query"; then
    expanded=$(expand_input_path "$query")
    [ -d "$expanded" ] || return 1
    printf '%s' "$expanded"
    return 0
  fi
  if [ -d "${TARGET}/${query}" ]; then
    printf '%s' "${TARGET}/${query}"
    return 0
  fi
  return 1
}

select_github_skill_dir() {
  local clone_dir="$1" url_subdir="$2" preferred_name="${3:-}"
  local selected_dir="" d
  local candidates=()

  if [ -n "$url_subdir" ]; then
    selected_dir="${clone_dir}/${url_subdir}"
    [ -f "${selected_dir}/SKILL.md" ] || return 1
    printf '%s' "$selected_dir"
    return 0
  fi

  for d in "$clone_dir"/*; do
    [ -d "$d" ] || continue
    [ -f "${d}/SKILL.md" ] || continue
    candidates+=("$d")
  done

  if [ "${#candidates[@]}" -eq 0 ]; then
    return 1
  fi

  if [ "${#candidates[@]}" -eq 1 ]; then
    printf '%s' "${candidates[0]}"
    return 0
  fi

  if [ -n "$preferred_name" ]; then
    for d in "${candidates[@]}"; do
      [ "$(basename "$d")" = "$preferred_name" ] || continue
      printf '%s' "$d"
      return 0
    done
  fi

  return 2
}

steal_from_github() {
  local github_url="$1"
  local parsed owner repo url_ref url_subdir source_url
  parsed=$(parse_github_source "$github_url") || {
    echo -e "  ${R}✗${N} 不是可识别的 GitHub URL: $github_url"
    return 1
  }
  IFS='|' read -r owner repo url_ref url_subdir source_url <<< "$parsed"

  if ! command -v git >/dev/null 2>&1; then
    echo -e "  ${R}✗${N} 当前环境缺少 git，暂时不能直接从 GitHub 安装"
    return 1
  fi

  local clone_dir tmp_root selected_dir selected_name selected_rel repo_ref installed_commit
  tmp_root=$(mktemp -d)
  clone_dir="${tmp_root}/repo"
  if [ -n "$url_ref" ]; then
    git clone --depth 1 --branch "$url_ref" "https://github.com/${owner}/${repo}.git" "$clone_dir" >/dev/null 2>&1 || {
      rm -rf "$tmp_root"
      echo -e "  ${R}✗${N} 拉取 GitHub 仓库失败: ${owner}/${repo}@${url_ref}"
      return 1
    }
  else
    git clone --depth 1 "https://github.com/${owner}/${repo}.git" "$clone_dir" >/dev/null 2>&1 || {
      rm -rf "$tmp_root"
      echo -e "  ${R}✗${N} 拉取 GitHub 仓库失败: ${owner}/${repo}"
      return 1
    }
  fi

  repo_ref=$(git -C "$clone_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$repo_ref" ] && [ "$repo_ref" != "HEAD" ] || repo_ref="${url_ref:-main}"

  selected_dir=$(select_github_skill_dir "$clone_dir" "$url_subdir") || {
    local status=$?
    rm -rf "$tmp_root"
    case "$status" in
      1) echo -e "  ${R}✗${N} GitHub 路径里没找到可直接安装的 SKILL.md" ;;
      2)
        echo "  这个仓库有多个 skill，请指定 tree URL 或子目录："
        for d in "$clone_dir"/*; do
          [ -d "$d" ] && [ -f "${d}/SKILL.md" ] && printf '  - %s\n' "${d##*/}"
        done
        ;;
      *) echo -e "  ${R}✗${N} 无法从 GitHub URL 选出 skill 目录" ;;
    esac
    return 1
  }

  selected_rel="${selected_dir#$clone_dir/}"
  selected_name=$(basename "$selected_dir")
  installed_commit=$(git -C "$clone_dir" log -1 --format=%H -- "$selected_rel" 2>/dev/null || git -C "$clone_dir" rev-parse HEAD)
  if [ -e "${TARGET}/${selected_name}" ] || [ -L "${TARGET}/${selected_name}" ]; then
    local existing_dir meta_path
    existing_dir="${TARGET}/${selected_name}"
    meta_path=$(skill_source_metadata_path "$existing_dir")
    if [ -d "$existing_dir" ] && [ ! -L "$existing_dir" ] && [ ! -f "$meta_path" ]; then
      write_github_source_metadata "$existing_dir" "${owner}/${repo}" "$repo_ref" "$selected_rel" "$source_url" "$installed_commit"
      echo -e "  ${Y}•${N} ${selected_name} 已存在，已补登记 GitHub 上游信息"
      echo "  上游仓库: ${owner}/${repo}"
      echo "  跟踪分支: ${repo_ref}"
      echo "  跟踪子目录: ${selected_rel}"
      echo "  安装提交: ${installed_commit}"
      echo -e "  ${D}下次运行 check 时，就能一起看这个 skill 是否落后上游${N}"
    else
      echo -e "  ${Y}•${N} ${selected_name} 已存在，跳过安装"
      echo -e "  ${D}如果想判断是否落后，可直接运行 check${N}"
    fi
    rm -rf "$tmp_root"
    record_steal_event "GitHub ${owner}/${repo}" "$source_url" 0 1 1
    return 0
  fi

  copy_skill_dir "$selected_dir" "${TARGET}/${selected_name}"
  write_github_source_metadata "${TARGET}/${selected_name}" "${owner}/${repo}" "$repo_ref" "$selected_rel" "$source_url" "$installed_commit"
  record_steal_event "GitHub ${owner}/${repo}" "$source_url" 1 0 1

  echo -e "${C}🏴‍☠️ Do${N}  从 ${G}GitHub${N} 安装到 $(friendly_target)"
  echo "  目标目录: $(short_path "$TARGET")"
  echo ""
  echo -e "  ${G}+${N} ${selected_name} ${D}(copy from GitHub)${N}"
  echo "  上游仓库: ${owner}/${repo}"
  echo "  跟踪分支: ${repo_ref}"
  echo "  跟踪子目录: ${selected_rel}"
  echo "  安装提交: ${installed_commit}"
  echo ""
  echo "  下一步建议:"
  echo "  - 运行 check                看当前库健康度和 GitHub 上游状态"
  echo "  - 之后如果 GitHub 更新，再跑 check 就能知道自己是不是落后"
  echo ""
  echo -e "  ${D}🧩 生命周期事件已写入: $(short_path "$(history_state_path)")${N}"
  rm -rf "$tmp_root"
  return 0
}

cmd_bind() {
  local skill_query="${1:-}" github_url="${2:-}"
  local cache="$DATA_DIR/last_scan.txt"
  [ -f "$cache" ] || cache=$(do_scan)
  resolve_target "$cache"

  if [ -z "$skill_query" ] || [ -z "$github_url" ]; then
    echo -e "${C}🔗 Bind — 补溯源${N}"
    echo ""
    echo "  bind <技能名|路径> <GitHub URL>"
    echo "  作用：给已手动装好的 GitHub skill 补登记来源，不重装。"
    echo ""
    echo "  例子："
    echo "  bind glm-image https://github.com/ViffyGwaanl/glm-image/tree/main/glm-image"
    echo "  bind ~/.claude/skills/article-illustrator https://github.com/ViffyGwaanl/glm-image/tree/main/article-illustrator"
    return 0
  fi

  local skill_dir skill_name parsed owner repo url_ref url_subdir source_url
  local tmp_root clone_dir repo_ref selected_dir selected_rel installed_commit=""
  local latest_commit="" match_note="" meta_path

  skill_dir=$(resolve_local_skill_dir "$skill_query") || {
    echo -e "  ${R}✗${N} 找不到本地 skill: $skill_query"
    return 1
  }
  [ -f "${skill_dir}/SKILL.md" ] || {
    echo -e "  ${R}✗${N} 目标目录里没有 SKILL.md: $(short_path "$skill_dir")"
    return 1
  }
  skill_name=$(basename "$skill_dir")

  parsed=$(parse_github_source "$github_url") || {
    echo -e "  ${R}✗${N} 不是可识别的 GitHub URL: $github_url"
    return 1
  }
  IFS='|' read -r owner repo url_ref url_subdir source_url <<< "$parsed"

  if ! command -v git >/dev/null 2>&1; then
    echo -e "  ${R}✗${N} 当前环境缺少 git，暂时不能补 GitHub 溯源"
    return 1
  fi

  tmp_root=$(mktemp -d)
  clone_dir="${tmp_root}/repo"
  if [ -n "$url_ref" ]; then
    git clone --depth 1 --branch "$url_ref" "https://github.com/${owner}/${repo}.git" "$clone_dir" >/dev/null 2>&1 || {
      rm -rf "$tmp_root"
      echo -e "  ${R}✗${N} 拉取 GitHub 仓库失败: ${owner}/${repo}@${url_ref}"
      return 1
    }
  else
    git clone --depth 1 "https://github.com/${owner}/${repo}.git" "$clone_dir" >/dev/null 2>&1 || {
      rm -rf "$tmp_root"
      echo -e "  ${R}✗${N} 拉取 GitHub 仓库失败: ${owner}/${repo}"
      return 1
    }
  fi

  repo_ref=$(git -C "$clone_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$repo_ref" ] && [ "$repo_ref" != "HEAD" ] || repo_ref="${url_ref:-main}"

  selected_dir=$(select_github_skill_dir "$clone_dir" "$url_subdir" "$skill_name") || {
    local status=$?
    rm -rf "$tmp_root"
    case "$status" in
      1) echo -e "  ${R}✗${N} GitHub 路径里没找到可绑定的 SKILL.md" ;;
      2)
        echo "  这个仓库有多个 skill，请指定更具体的 tree URL："
        for d in "$clone_dir"/*; do
          [ -d "$d" ] && [ -f "${d}/SKILL.md" ] && printf '  - %s\n' "${d##*/}"
        done
        ;;
      *) echo -e "  ${R}✗${N} 无法从 GitHub URL 选出要绑定的 skill 目录" ;;
    esac
    return 1
  }

  selected_rel="${selected_dir#$clone_dir/}"
  latest_commit=$(git -C "$clone_dir" log -1 --format=%H -- "$selected_rel" 2>/dev/null || git -C "$clone_dir" rev-parse HEAD)
  if compare_skill_dirs "$skill_dir" "$selected_dir"; then
    installed_commit="$latest_commit"
    match_note="当前本地内容和上游当前版本一致，已按这个提交登记。"
  else
    installed_commit=""
    match_note="来源已登记，但当前本地内容和上游当前版本不完全一致，安装提交暂时未知。"
  fi

  write_github_source_metadata "$skill_dir" "${owner}/${repo}" "$repo_ref" "$selected_rel" "$source_url" "$installed_commit"
  record_bind_event "$skill_name" "$skill_dir" "$source_url" "${owner}/${repo}" "$repo_ref" "$selected_rel" "$installed_commit"
  meta_path=$(skill_source_metadata_path "$skill_dir")

  echo -e "${C}🔗 Bind${N}  给 ${G}${skill_name}${N} 补登记 GitHub 来源"
  echo "  本地目录: $(short_path "$skill_dir")"
  echo "  上游仓库: ${owner}/${repo}"
  echo "  跟踪分支: ${repo_ref}"
  echo "  跟踪子目录: ${selected_rel}"
  if [ -n "$installed_commit" ]; then
    echo "  安装提交: ${installed_commit}"
  else
    echo "  安装提交: 暂时未知"
  fi
  echo "  来源链接: ${source_url}"
  echo ""
  echo "  - ${match_note}"
  echo -e "  ${D}元信息已写入: $(short_path "$meta_path")${N}"
  echo ""
  echo "  下一步建议:"
  echo "  - 运行 check                看这个 skill 现在是否落后上游"
  rm -rf "$tmp_root"
  return 0
}

show_command_mode_help() {
  echo -e "skill-mgr v${VERSION} ${D}— skill manager${N}"
  echo ""
  echo "  命令模式："
  echo "  scan             在本地扫描所有技能库"
  echo "  steal <从> [技能] 从其他技能库迁移到这里，也可直接装 GitHub skill"
  echo "  check [从]       默认检查当前库健康度"
  echo "  act [需求]       联网后推荐 skills；不写需求时按身份，有需求时再补排序"
  echo ""
  echo "  高级修复："
  echo "  bind <技能> <GitHub URL>    给已手动装好的 GitHub skill 补来源登记"
  echo ""
  echo -e "  ${D}常用别名: here / home-claude / home-openclaw / home-codex / home-amp${N}"
  echo -e "  ${D}需要换目标时再用 --to；需要先预演偷取时可加 --dry-run${N}"
}

show_entry_menu() {
  echo -e "skill-mgr v${VERSION} ${D}— skill manager${N}"
  echo ""
  echo "  先选一种方式开始："
  echo "  1. 一键体验    自动跑一轮 scan / check / act，并给一个 steal 预览（只读）"
  echo "  2. 命令模式    继续用 scan / steal / check / act"
  echo ""

  if [ -t 0 ]; then
    echo -n "  选择 [1/2，回车默认 2]："
    local choice
    read -r choice
    echo ""
    case "$choice" in
      1|一键体验|体验|experience)
        cmd_experience
        return 0
        ;;
      2|命令模式|命令|command|"")
        show_command_mode_help
        return 0
        ;;
      *)
        echo "  输入未识别，先进入命令模式。"
        echo ""
        show_command_mode_help
        return 0
        ;;
    esac
  fi

  echo "  非交互环境下默认不自动执行。"
  echo "  - 人类用户：在终端里输入 1 或 2 选择"
  echo "  - Agent 用户：直接说“一键体验”或“命令模式”"
}

emit_act_follow_up_question() {
  local hints="$1"
  echo ""
  echo "  💬 先问一句，让下一轮更准："
  if printf ' %s ' "$hints" | grep -q " feishu "; then
    echo "  - 你现在更想补哪类能力？直接回一句：飞书协作 / 记忆知识库 / 搜索浏览器 / 图像内容 / 还不确定"
  elif printf ' %s ' "$hints" | grep -q " knowledge "; then
    echo "  - 你现在更想补哪类能力？直接回一句：记忆知识库 / 飞书协作 / 搜索浏览器 / 图像内容 / 还不确定"
  else
    echo "  - 你现在更想补哪类能力？直接回一句：飞书协作 / 记忆知识库 / 搜索浏览器 / 图像内容 / 还不确定"
  fi
  echo "  - 你一回，我就按这句需求重排本地候选、SkillsMP、GitHub 需求雷达。"
}

read_experience_state_summary() {
  local scan_state="$1" health_state="$2"
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  python3 - <<'PY' "$scan_state" "$health_state"
import json, sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    scan = json.load(f)
with open(sys.argv[2], "r", encoding="utf-8") as f:
    health = json.load(f)

target = scan.get("target", {})
totals = scan.get("totals", {})
summary = health.get("summary", {})

print(
    "\t".join(
        str(x)
        for x in [
            totals.get("libraries", 0),
            target.get("total", 0),
            target.get("entities", 0),
            target.get("symlinks", 0),
            target.get("broken_symlinks", 0),
            summary.get("runtime_ready", 0),
            summary.get("runtime_easy_fix", 0),
            summary.get("runtime_user_action", 0),
            summary.get("structure_issues", 0),
            summary.get("upstream_outdated", 0),
        ]
    )
)
PY
}

cmd_experience() {
  local intent_query="${*:-}"
  echo -e "${C}✨ 一键体验 — 先感受，再决定${N}"
  echo ""

  local cache="$DATA_DIR/last_scan.txt"
  [ -f "$cache" ] || cache=$(do_scan)
  resolve_target "$cache"

  local tlabel thost sink old_dry_run old_act_web
  tlabel=$(target_label)
  thost=$(target_host_id)
  [ -d "$TARGET" ] || { echo -e "  ${R}✗${N} 目标库不存在: ${TARGET}"; return 1; }

  sink=$(mktemp)
  old_dry_run="$DRY_RUN"
  old_act_web="$ACT_WEB"
  cmd_scan >"$sink" 2>&1 || true
  DRY_RUN=1
  ACT_WEB=0
  cmd_check >"$sink" 2>&1 || true
  DRY_RUN="$old_dry_run"
  ACT_WEB="$old_act_web"

  local scan_state health_state
  scan_state=$(scan_state_path)
  health_state=$(health_state_path)
  cache="$DATA_DIR/last_scan.txt"

  local libs=0 target_total=0 entities=0 symlinks=0 broken=0 ready=0 easy=0 hard=0 structure_issues=0 upstream_outdated=0
  if [ -f "$scan_state" ] && [ -f "$health_state" ]; then
    IFS=$'\t' read -r libs target_total entities symlinks broken ready easy hard structure_issues upstream_outdated < <(
      read_experience_state_summary "$scan_state" "$health_state" 2>/dev/null || true
    )
  fi

  collect_local_candidates "$cache" "$thost" "$intent_query"
  local trending_tmp
  trending_tmp=$(mktemp)
  collect_github_trending_radar "$cache" "$intent_query" >"$trending_tmp" || true
  if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ] && [ -n "$ACT_LOCAL_PRIMARY_SKILL" ]; then
    DRY_RUN=1
    cmd_steal "$ACT_LOCAL_PRIMARY_SOURCE" "$ACT_LOCAL_PRIMARY_SKILL" >"$sink" 2>&1 || true
    DRY_RUN="$old_dry_run"
  fi
  [ -n "${ACT_LOCAL_SUMMARY_FILE:-}" ] && rm -f "$ACT_LOCAL_SUMMARY_FILE"
  ACT_LOCAL_SUMMARY_FILE=""

  echo "  当前操作对象: $(friendly_target)"
  echo "  目标目录: $(short_path "$TARGET")"
  echo ""
  if [ -n "$intent_query" ]; then
    echo "  当前问题/需求: ${intent_query}"
    echo ""
  fi
  echo "  先说结论："
  if [ "${structure_issues:-0}" -gt 0 ] || [ "${broken:-0}" -gt 0 ]; then
    echo "  - 当前库能继续用，但先把结构问题收干净，再补新 skill 会更稳。"
  elif [ "${easy:-0}" -gt "${ready:-0}" ]; then
    echo "  - 当前库底子不差，但很多能力还停在“装了未配”的状态，先整理再补能力更划算。"
  else
    echo "  - 当前库底子不错；真要补能力，优先偷本机已验证来源，比直接去大榜翻 repo 更省力。"
  fi
  if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
    echo "  - 本地最值得先看的来源是 ${ACT_LOCAL_PRIMARY_SOURCE_DISPLAY}，因为它现在就能评估，动手成本最低。"
  else
    echo "  - 这轮没挑出明显的本地首选，下一步更适合先看在线雷达找线索。"
  fi
  if [ "${upstream_outdated:-0}" -gt 0 ]; then
    echo "  - 另外，当前库里还有 ${upstream_outdated} 个 GitHub skill 落后上游，补新之前顺手看一眼会更稳。"
  fi

  echo ""
  echo "  这轮体验看到了什么："
  echo "  - scan：扫到 ${libs:-0} 个技能库；当前这里有 ${target_total:-0} 个技能（${entities:-0} 实体 / ${symlinks:-0} 软链）。"
  echo "  - check：当前可用 ${ready:-0} 个，需简单配置 ${easy:-0} 个，需用户操作 ${hard:-0} 个。"
  if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
    echo "  - act：我同时看了本地候选和在线雷达；现在更值得先从本地来源下手。"
  else
    echo "  - act：这轮更像是在帮你收集方向，本地和在线都看过了，但还没有明显首选。"
  fi
  if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ] && [ -n "$ACT_LOCAL_PRIMARY_SKILL" ]; then
    echo "  - steal preview：如果现在只试 1 个，先看 ${ACT_LOCAL_PRIMARY_SOURCE_DISPLAY} -> ${ACT_LOCAL_PRIMARY_SKILL}；${ACT_LOCAL_PRIMARY_REASON}。"
  elif [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
    echo "  - steal preview：如果现在要动手，先跑 check ${ACT_LOCAL_PRIMARY_SOURCE}，再决定要不要偷。"
  else
    echo "  - steal preview：当前没有明显本地首选，先保持只读体验更划算。"
  fi
  case "$ACT_TRENDING_STATE" in
    ok)
      if [ "$ACT_TRENDING_MATCH_MODE" = "intent" ] && [ -n "$intent_query" ]; then
        echo "  - 在线发现：我还自动接上了 github-trending-cn，并按你当前需求重排了热门仓库。"
      else
        echo "  - 在线发现：我还自动接上了 github-trending-cn，当作补充新线索的雷达。"
      fi
      ;;
    limited)
      echo "  - 在线发现：本机有 github-trending-cn，但当前 GitHub API 限额或鉴权不足，所以这轮没把它当强信号。"
      ;;
  esac

  echo ""
  echo "  你刚刚体验到的是：scan / check / act / steal-preview"
  if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
    echo "  想继续自己控制，就选命令模式；想直接往前推进，下一步先跑 check ${ACT_LOCAL_PRIMARY_SOURCE}。"
  else
    echo "  想继续自己控制，就选命令模式；想继续探索，就单独跑 act 看在线发现雷达。"
  fi

  rm -f "$sink" "$trending_tmp"
}

cmd_scan() {
  echo -e "${C}📋 Plan — 全盘扫描${N}"
  echo ""
  local cache
  cache=$(do_scan)
  resolve_target "$cache"
  local tlabel thost
  tlabel=$(target_label)
  thost=$(target_host_id)
  echo "  当前操作对象: $(friendly_target)"
  echo "  目标目录: $(short_path "$TARGET")"
  emit_context_bundle "$thost"
  show_target_structure
  echo ""

  local total=0 idx=0 name dir count mark display_name
  while IFS=: read -r name dir count; do
    idx=$((idx + 1))
    mark=""
    [ "$dir" = "$TARGET" ] && mark=" 🎯"
    display_name=$(source_display_name "$name" "$dir" "$cache")
    printf "  ${G}%2d${N}  %-16s ${B}%3d${N} skills  ${D}%s${N}%s\n" "$idx" "$display_name" "$count" "$dir" "$mark"
    total=$((total + count))
  done < "$cache"
  echo ""
  echo -e "  共 ${B}${total}${N} 个技能，${B}${idx}${N} 个库"

  local my rec_count=0 d sname sdesc missing total_s summary expanded=0 expanded_labels="|"
  local display_limit=12
  local compact_count=0 compact_hidden=0
  my=$(mktemp)
  summary=$(mktemp)
  for d in "$TARGET"/*; do
    [ -d "$d" ] && [ -f "${d}/SKILL.md" ] && basename "$d"
  done | sort > "$my"

  echo ""
  echo -e "  ${Y}💡 推荐（默认只展开最值得看的几个来源）${N}"
  echo ""

  while IFS=: read -r name dir count; do
    [ "$dir" = "$TARGET" ] && continue
    missing=0
    total_s=0
    for d in "$dir"/*; do
      [ -d "$d" ] && [ -f "${d}/SKILL.md" ] || continue
      total_s=$((total_s + 1))
      grep -qx "$(basename "$d")" "$my" || missing=$((missing + 1))
    done
    if [ "$missing" -gt 0 ]; then
      printf '%s:%s:%s:%s\n' "$missing" "$name" "$dir" "$total_s" >> "$summary"
      rec_count=$((rec_count + 1))
    fi
  done < "$cache"

  if [ "$rec_count" -eq 0 ]; then
    echo -e "  ${G}✓ 所有技能已同步${N}"
  else
    while IFS=: read -r missing name dir total_s; do
      display_name=$(source_display_name "$name" "$dir" "$cache")
      if [ "$name" = "$tlabel" ]; then
        echo -e "  ${D}•${N} ${display_name} — ${missing}/${total_s} 个你还没有；这是同宿主全局库，想展开可运行 ${B}check ${name}${N}"
        continue
      fi
      if [ "$expanded" -lt 3 ] && [[ "$expanded_labels" != *"|$name|"* ]]; then
        expanded=$((expanded + 1))
        expanded_labels="${expanded_labels}${name}|"
        echo -e "  ✅ 从 ${G}${display_name}${N} 偷到这里 — ${B}${missing}${N}/${total_s} 个你还没有的"
        local shown=0
        for d in "$dir"/*; do
          [ -d "$d" ] && [ -f "${d}/SKILL.md" ] || continue
          sname=$(basename "$d")
          grep -qx "$sname" "$my" && continue
          shown=$((shown + 1))
          if [ "$shown" -gt "$display_limit" ]; then
            continue
          fi
          sdesc=$(desc "$d")
          [ -z "$sdesc" ] && sdesc="(无描述)"
          printf "     ${D}-${N} %-30s ${D}%s${N}\n" "$sname" "$sdesc"
        done
        if [ "$missing" -gt "$display_limit" ]; then
          echo -e "     ${D}... 还有 $((missing - display_limit)) 个，想展开可运行 check ${name}${N}"
        fi
        echo ""
      else
        compact_count=$((compact_count + 1))
        if [ "$compact_count" -le 8 ]; then
          echo -e "  ${D}•${N} ${display_name} — ${missing}/${total_s} 个你还没有；想展开可运行 ${B}check ${name}${N}"
        else
          compact_hidden=$((compact_hidden + 1))
        fi
      fi
    done < <(sort -t: -k1,1rn "$summary")
    if [ "$compact_hidden" -gt 0 ]; then
      echo -e "  ${D}... 还有 ${compact_hidden} 个来源可展开，用 check <来源> 查看${N}"
    fi
  fi

  local scan_state
  scan_state=$(write_scan_state "$cache")
  record_scan_event "$total" "$idx"
  rm -f "$my" "$summary"
  echo ""
  echo -e "  ${D}🧩 状态已刷新: $(short_path "$scan_state")${N}"
  echo -e "  ${D}🤖 后续跟进优先读: $(short_path "$scan_state")${N}"
  return 0
}

cmd_steal() {
  local src_query="${1:-}"
  shift 2>/dev/null || true
  local skills=("$@")
  local cache="$DATA_DIR/last_scan.txt"
  [ -f "$cache" ] || cache=$(do_scan)
  resolve_target "$cache"
  local tlabel thost
  tlabel=$(target_label)
  thost=$(target_host_id)

  if [ "$(platform_id)" = "windows" ] && [ "$USE_COPY" -eq 0 ]; then
    USE_COPY=1
  fi

  if [ -z "$src_query" ]; then
    echo -e "${C}🏴‍☠️ Do — 偷技能${N}"
    echo ""
    echo "  现在默认是: $(friendly_target)"
    echo "  steal <来源>                从别处整库偷到这里"
    echo "  steal <来源> <技能名>       从别处偷一个到这里"
    echo "  steal <来源> a b c          从别处挑几个偷到这里"
    echo "  steal <GitHub URL>          直接从 GitHub 仓库安装 skill"
    echo "  --to here                   强制偷到当前项目"
    echo "  --to home-openclaw          偷到主目录 OpenClaw"
    if [ "$(platform_id)" = "windows" ]; then
      echo -e "  ${D}当前是 Windows：默认用复制，避免软链权限坑；显式传 --copy 也可以${N}"
    fi
    echo -e "  ${D}平时直接 scan / steal 就行，只有换目标时才用 --to${N}"
    return 0
  fi

  if is_github_url "$src_query"; then
    steal_from_github "$src_query"
    return $?
  fi

  local src_dir src_name d name new=0 skip=0
  src_dir=$(resolve "$src_query" "$cache")
  src_name=$(grep -F "$src_dir" "$cache" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -z "$src_dir" ] || [ ! -d "$src_dir" ]; then
    echo -e "  ${R}✗${N} 找不到: $src_query"
    return 1
  fi

  echo -e "${C}🏴‍☠️ Do${N}  从 ${G}${src_name}${N} 偷到 $(friendly_target)"
  echo "  目标目录: $(short_path "$TARGET")"
  echo ""
  mkdir -p "$TARGET"

  for d in "$src_dir"/*/; do
    [ -d "$d" ] && [ -f "${d}SKILL.md" ] || continue
    name=$(basename "$d")
    if [ ${#skills[@]} -gt 0 ]; then
      local match=0 s
      for s in "${skills[@]}"; do
        [ "$s" = "$name" ] && match=1 && break
      done
      [ "$match" -eq 0 ] && continue
    fi

    if [ -e "${TARGET}/${name}" ]; then
      skip=$((skip + 1))
    else
      new=$((new + 1))
      if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "  ${Y}+${N} $name ${D}(预览)${N}"
      elif [ "$USE_COPY" -eq 1 ]; then
        cp -r "$d" "${TARGET}/${name}"
        echo -e "  ${G}+${N} $name"
      else
        ln -sf "$d" "${TARGET}/${name}"
        echo -e "  ${G}+${N} $name ${D}→ linked${N}"
      fi
    fi
  done

  echo ""
  echo -e "  新增 ${G}${new}${N} | 已有 ${skip}"
  if [ "$DRY_RUN" -eq 0 ]; then
    record_steal_event "${src_name:-$src_query}" "$src_dir" "$new" "$skip" "$USE_COPY"
  fi
  if [ "$new" -gt 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo ""
    echo "  下一步建议:"
    echo "  - 直接试用刚偷进来的技能"
    echo "  - check                看当前项目技能库整体是否稳定"
    if [ -n "$src_name" ]; then
      echo "  - check ${src_name}     看从 ${src_name} 偷到这里这条路线值不值"
    fi
  fi

  if [ "$new" -gt 0 ]; then
    echo ""
    collect_env "$thost" "$tlabel" "$TARGET"
    echo ""
    echo "  📋 新增技能 SKILL.md 摘要（供 AI 判断兼容性风险）："
    for d in "$src_dir"/*/; do
      [ -d "$d" ] && [ -f "${d}SKILL.md" ] || continue
      name=$(basename "$d")
      if [ ${#skills[@]} -gt 0 ]; then
        local match=0 s
        for s in "${skills[@]}"; do
          [ "$s" = "$name" ] && match=1 && break
        done
        [ "$match" -eq 0 ] && continue
      fi
      [ -e "${TARGET}/${name}" ] || continue
      echo "  --- $name ---"
      local host_notes
      host_notes=$(cross_host_notes "$(tr '[:upper:]' '[:lower:]' < "${d}SKILL.md" 2>/dev/null)" "$thost" "$tlabel")
      [ -n "$host_notes" ] && echo -e "$host_notes"
      head -30 "${d}SKILL.md" 2>/dev/null | sed 's/^/  /'
      echo ""
    done
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    echo ""
    echo -e "  ${D}🧩 生命周期事件已写入: $(short_path "$(history_state_path)")${N}"
    echo -e "  ${D}🤖 如果用户追问“刚新增了什么 / 最近做过什么”，优先读: $(short_path "$(history_state_path)")${N}"
  fi
}

cmd_act() {
  local intent_query="${*:-}"
  ACT_WEB=1
  if [ -n "$intent_query" ]; then
    echo -e "${C}🎯 Act — 身份打底，按问题补排序${N}"
  else
    echo -e "${C}🎯 Act — 先看本地，再问一句${N}"
  fi
  echo ""
  local cache="$DATA_DIR/last_scan.txt"
  [ -f "$cache" ] || cache=$(do_scan)
  resolve_target "$cache"
  local tlabel thost hints skill_count blocker_count=0 d
  tlabel=$(target_label)
  thost=$(target_host_id)
  [ -d "$TARGET" ] || { echo -e "  ${R}✗${N} 目标库不存在: ${TARGET}"; return 1; }

  echo "  当前操作对象: $(friendly_target)"
  echo "  目标目录: $(short_path "$TARGET")"
  emit_context_inventory "$thost"
  emit_context_bundle "$thost" 3

  hints=$(context_keyword_hints "$thost")
  skill_count=$(installed_skill_count)
  echo "  🧭 当前身份判断（供在线推荐定调）:"
  echo "  - 目标宿主: ${tlabel}"
  echo "  - 当前已装技能: ${skill_count} 个"
  if [ -n "$hints" ]; then
    echo "  - 主题关键词: ${hints}"
  else
    echo "  - 主题关键词: 未从上下文里提取到明显方向"
  fi
  if [ -n "$intent_query" ]; then
    echo "  - 当前问题/需求: ${intent_query}"
  fi

  for d in "$TARGET"/*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    if [ -L "$d" ] && [ ! -e "$d" ]; then
      blocker_count=$((blocker_count + 1))
    elif [ -d "$d" ] && [ ! -f "${d}/SKILL.md" ]; then
      blocker_count=$((blocker_count + 1))
    fi
  done
  if [ "$blocker_count" -gt 0 ]; then
    echo "  - 前置提醒: 当前库还有 ${blocker_count} 个底层问题，真要动手前建议先跑 check"
  fi

  emit_local_candidates "$cache" "$thost" "$intent_query"

  if [ -z "$intent_query" ]; then
    echo ""
    echo "  🌐 在线发现先不展开："
    echo "  - 这一步我先不直接丢 SkillsMP / GitHub 热榜，避免推荐看起来没人感。"
    echo "  - 你先告诉我现在更想补什么，我再按那个方向去外面补线索。"
    emit_act_follow_up_question "$hints"
    echo ""
    echo "  ✅ 下一步推荐（供 AI 收口）:"
    echo "  - 直接回一句你现在更想补的能力方向；我下一轮会按这句需求重排推荐"
    if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
      echo "  - 如果你现在就想动手，也可以先跑 check ${ACT_LOCAL_PRIMARY_SOURCE}"
    fi
    return 0
  fi

  echo ""
  echo "  🌐 在线发现雷达（找新线索，不直接替代本地候选）:"
  emit_store_suggestions "$thost"
  emit_skillsmp_candidates "$thost" "$intent_query"
  if [ "${SKILLSMP_LAST_RESULT_STATE:-not_run}" != "ok" ]; then
    emit_web_source_snapshots "$thost"
  fi
  emit_github_search_radar "$intent_query"
  emit_github_trending_radar "$cache" "$intent_query"

  echo ""
  echo "  ✅ 下一步推荐（供 AI 收口）:"
  if [ -n "$ACT_LOCAL_PRIMARY_SOURCE" ]; then
    echo "  - 先从本地候选里选 1 个最贴近当前主题、又明显没装过的来源"
    echo "  - 下一步先跑 check ${ACT_LOCAL_PRIMARY_SOURCE}，确认这条偷取路线值不值"
    if [ -n "$ACT_LOCAL_PRIMARY_SKILL" ]; then
      echo "  - 如果 check 结果干净，再考虑 steal ${ACT_LOCAL_PRIMARY_SOURCE} ${ACT_LOCAL_PRIMARY_SKILL}"
    fi
    return 0
  fi

  if [ "${SKILLSMP_LAST_RESULT_STATE:-not_run}" = "ok" ]; then
    if [ "${SKILLSMP_TOP_STARS:-0}" -ge 50 ] && [ "${SKILLSMP_SECOND_STARS:-0}" -lt 20 ]; then
      echo "  - 先把 SkillsMP 里那个唯一明显高热的候选当作重点参考，其余在线结果先只记成备选灵感"
      echo "  - 然后优先回看本地候选来源，找能直接 steal 的同类能力"
      echo "  - 真要装之前，先用 check <来源> 看兼容性和值不值得"
      return 0
    fi
    if [ "${SKILLSMP_TOP_STARS:-0}" -lt 20 ] && [ "${SKILLSMP_HIGH_CONFIDENCE_COUNT:-0}" -eq 0 ]; then
      echo "  - 当前在线候选更适合拿来启发方向，不建议直接按它们下手安装"
      echo "  - 先优先看上面的官方/生态入口，再回到本地候选里挑能直接试的来源"
      echo "  - 真要动手前，先用 check <来源> 看兼容性和值不值得"
      return 0
    fi
    echo "  - 先从 SkillsMP 在线候选里挑 1-2 个最贴近当前身份、且热度不弱的 skill"
  else
    echo "  - 先从上面的官方/生态入口里选 1 个最贴近当前身份的来源，再看它的对应分类"
  fi
  echo "  - 再回看本地候选来源，优先选择已经能直接 steal 的来源"
  echo "  - 如果要真正装入当前库，下一步用 check <来源> 或 steal <来源> <技能>"
  return 0
}
