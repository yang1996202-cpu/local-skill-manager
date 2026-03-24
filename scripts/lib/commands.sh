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

  local total=0 idx=0 name dir count mark
  while IFS=: read -r name dir count; do
    idx=$((idx + 1))
    mark=""
    [ "$dir" = "$TARGET" ] && mark=" 🎯"
    printf "  ${G}%2d${N}  %-16s ${B}%3d${N} skills  ${D}%s${N}%s\n" "$idx" "$name" "$count" "$dir" "$mark"
    total=$((total + count))
  done < "$cache"
  echo ""
  echo -e "  共 ${B}${total}${N} 个技能，${B}${idx}${N} 个库"

  local my rec_count=0 d sname sdesc missing total_s
  my=$(mktemp)
  for d in "$TARGET"/*/; do
    [ -d "$d" ] && [ -f "${d}SKILL.md" ] && basename "$d"
  done | sort > "$my"

  echo ""
  echo -e "  ${Y}💡 推荐${N}"
  echo ""

  while IFS=: read -r name dir count; do
    [ "$dir" = "$TARGET" ] && continue
    missing=0
    total_s=0
    for d in "$dir"/*/; do
      [ -d "$d" ] && [ -f "${d}SKILL.md" ] || continue
      total_s=$((total_s + 1))
      grep -qx "$(basename "$d")" "$my" || missing=$((missing + 1))
    done
    if [ "$missing" -gt 0 ]; then
      echo -e "  ✅ 从 ${G}${name}${N} 偷到这里 — ${B}${missing}${N}/${total_s} 个你还没有的"
      for d in "$dir"/*/; do
        [ -d "$d" ] && [ -f "${d}SKILL.md" ] || continue
        sname=$(basename "$d")
        grep -qx "$sname" "$my" && continue
        sdesc=$(desc "$d")
        [ -z "$sdesc" ] && sdesc="(无描述)"
        printf "     ${D}-${N} %-30s ${D}%s${N}\n" "$sname" "$sdesc"
      done
      echo ""
      rec_count=$((rec_count + 1))
    else
      echo -e "  ${D}⊘ ${name} — 这里已经齐了${N}"
    fi
  done < "$cache"

  [ "$rec_count" -eq 0 ] && echo -e "  ${G}✓ 所有技能已同步${N}"
  rm -f "$my"
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

  if [ -z "$src_query" ]; then
    echo -e "${C}🏴‍☠️ Do — 偷技能${N}"
    echo ""
    echo "  现在默认是: $(friendly_target)"
    echo "  steal <来源>                从别处整库偷到这里"
    echo "  steal <来源> <技能名>       从别处偷一个到这里"
    echo "  steal <来源> a b c          从别处挑几个偷到这里"
    echo "  --to here                   强制偷到当前项目"
    echo "  --to home-openclaw          偷到主目录 OpenClaw"
    echo -e "  ${D}平时直接 scan / steal 就行，只有换目标时才用 --to${N}"
    return 0
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
  [ "$new" -gt 0 ] && [ "$DRY_RUN" -eq 0 ] && echo -e "  ${D}下一步: check${N}"

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
