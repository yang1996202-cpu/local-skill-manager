copy_skill_dir() {
  local src_dir="$1" dest_dir="$2"
  rm -rf "$dest_dir"
  mkdir -p "$(dirname "$dest_dir")"
  cp -R "$src_dir" "$dest_dir"
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

  if [ -n "$url_subdir" ]; then
    selected_dir="${clone_dir}/${url_subdir}"
    if [ ! -f "${selected_dir}/SKILL.md" ]; then
      rm -rf "$tmp_root"
      echo -e "  ${R}✗${N} GitHub 路径里没找到 SKILL.md: ${url_subdir}"
      return 1
    fi
  else
    local candidates=() d
    for d in "$clone_dir"/*; do
      [ -d "$d" ] || continue
      [ -f "${d}/SKILL.md" ] || continue
      candidates+=("$d")
    done
    if [ "${#candidates[@]}" -eq 0 ]; then
      rm -rf "$tmp_root"
      echo -e "  ${R}✗${N} 仓库顶层没有发现可直接安装的 skill 目录"
      return 1
    fi
    if [ "${#candidates[@]}" -gt 1 ]; then
      echo "  这个仓库有多个 skill，请指定 tree URL 或子目录："
      printf '  - %s\n' "${candidates[@]##*/}"
      rm -rf "$tmp_root"
      return 1
    fi
    selected_dir="${candidates[0]}"
  fi

  selected_name=$(basename "$selected_dir")
  if [ -e "${TARGET}/${selected_name}" ] || [ -L "${TARGET}/${selected_name}" ]; then
    echo -e "  ${Y}•${N} ${selected_name} 已存在，跳过安装"
    echo -e "  ${D}如果想判断是否落后，可直接运行 check${N}"
    rm -rf "$tmp_root"
    record_steal_event "GitHub ${owner}/${repo}" "$source_url" 0 1 1
    return 0
  fi

  selected_rel="${selected_dir#$clone_dir/}"
  installed_commit=$(git -C "$clone_dir" log -1 --format=%H -- "$selected_rel" 2>/dev/null || git -C "$clone_dir" rev-parse HEAD)
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
  ACT_WEB=1
  echo -e "${C}🎯 Act — 身份驱动的在线推荐${N}"
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

  emit_store_suggestions "$thost"
  emit_skillsmp_candidates "$thost"
  if [ "${SKILLSMP_LAST_RESULT_STATE:-not_run}" != "ok" ]; then
    emit_web_source_snapshots "$thost"
  fi
  emit_external_radar "$cache"

  echo ""
  echo "  ✅ 下一步推荐（供 AI 收口）:"
  if [ "${SKILLSMP_LAST_RESULT_STATE:-not_run}" = "ok" ]; then
    if [ "${SKILLSMP_TOP_STARS:-0}" -ge 50 ] && [ "${SKILLSMP_SECOND_STARS:-0}" -lt 20 ]; then
      echo "  - 先把 SkillsMP 里那个唯一明显高热的候选当作重点参考，其余在线结果先只记成备选灵感"
      echo "  - 然后优先回看外部储备库雷达，找本地已有、能直接 steal 的同类能力"
      echo "  - 真要装之前，先用 check <来源> 看兼容性和值不值得"
      return 0
    fi
    if [ "${SKILLSMP_TOP_STARS:-0}" -lt 20 ] && [ "${SKILLSMP_HIGH_CONFIDENCE_COUNT:-0}" -eq 0 ]; then
      echo "  - 当前在线候选更适合拿来启发方向，不建议直接按它们下手安装"
      echo "  - 先优先看上面的官方/生态入口，再回到外部储备库雷达里挑本地已有来源"
      echo "  - 真要动手前，先用 check <来源> 看兼容性和值不值得"
      return 0
    fi
    echo "  - 先从 SkillsMP 在线候选里挑 1-2 个最贴近当前身份、且热度不弱的 skill"
  else
    echo "  - 先从上面的官方/生态入口里选 1 个最贴近当前身份的来源，再看它的对应分类"
  fi
  echo "  - 再回看外部储备库雷达，优先选择本地已经能直接 steal 的来源"
  echo "  - 如果要真正装入当前库，下一步用 check <来源> 或 steal <来源> <技能>"
  return 0
}
