---
name: skill-manager
description: >-
  PDCA 技能管家 — 发现推荐、偷取、诊断清理、使用报告。
  触发词："管理技能"、"看技能"、"偷技能"、"清理技能"、
  "skill manager"、"steal skills"、"check skills"。
---

Run `bash <skill-dir>/scripts/skill-mgr.sh <command> [--to <target-lib>]`.

| Step | Command | What |
|------|---------|------|
| Plan | `scan` | 看外面还有什么库、什么技能可以拿来用 |
| Do | `steal <来源> [技能]` | 从别处偷到这里 |
| Check | `check [来源]` | 看当前库稳不稳；也可看“从 A 偷到这里”值不值 |
| Act | `act` | 基于当前身份做在线推荐：看哪些官方入口和值得逛的 skill 来源 |

Flags: `--to <目标库>` `--web` `--dry-run` `--copy` `--yes`
Optional env for online recommendation: `SKILLSMP_API_KEY`
Friendly aliases for `--to`: `here` `home-claude` `home-openclaw` `home-codex` `home-amp`

> **CRITICAL RULE FOR INITIALIZATION**:
> When you are triggered without explicit parameters (e.g. `/skill-manager`), your FIRST response MUST be to politely greet the user and automatically display the 4-step PDCA command table (scan, steal, check, act) in a clean markdown table so the user knows exactly what functions you provide. DO NOT automatically run `scan` unless the user asks you to. Keep the wording simple and user-facing: `scan` = 看外面还有什么, `steal` = 从哪偷到这里, `check` = 看这里稳不稳, `act` = 联网增强版 check.

> **CRITICAL RULE FOR SCAN OUTPUT**: 
> When the user runs `scan`, you MUST FIRST render the overarching "Total Libraries Summary Table" (整体总表), showing each external library, its total skill counts, and concrete locations as provided by the script. The user explicitly needs this overarching "blue print" matrix. Then preserve the script's "当前操作对象 / 当前项目上下文 / 当前目标库结构" sections, because those make the behavior deterministic. Finally, when presenting the missing skills, DO NOT summarize or compress them—show the **FULL LIST** exactly as outputted.

> **CRITICAL RULE FOR CHECK / ACT**:
> Treat `check` as the primary command. `act` is not a second full diagnosis system; it is the lightweight online recommendation view built on the current identity and host.
> 1. **Check First, In Simple Language**: When the user runs `check`, explain it in plain terms: either they are checking `当前这里`, or checking `从 A 偷到这里`. Do not over-emphasize flags or internal terminology.
> 2. **Honor Context Files (上下文优先级)**: Use the emitted project context files and identity/rule file inventory deterministically. Prefer the nearest project-level file over home-level memory. If `AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `rules`, member files, or host identity files conflict, explicitly say you prioritized the nearest project file.
> 3. **Act Must Stay Lightweight**: Do NOT turn `act` into a full health report, scenario clustering, or giant arsenal review. `act` should stay focused on online recommendation and next-step guidance.
> 4. **Store / Official Sources Are Mandatory (商店/官网入口建议必出)**: In `act`, you MUST include a dedicated subsection named `商店 / 官方入口建议`. Cite at least TWO entries from the script's official/ecosystem/store output, and explain why each is relevant to the current project identity and host.
> 5. **Online Candidates Are Mandatory**: In `act`, you MUST include a dedicated subsection named `在线候选建议`. Prefer `SkillsMP 在线候选` when present; otherwise fall back to `在线来源快照`. The recommendation must be grounded in the current host, identity files, and installed skills.
> 5.1. **Do Not Over-Sell Weak Online Candidates**: Treat `SkillsMP` results as search hits first, not automatic endorsements. If the script indicates the online candidates have weak heat / low stars / only one strong hit, explicitly say they are exploratory options rather than primary recommendations. Do NOT present low-star candidates as top-priority installs just because they semantically match.
> 5.2. **If User Points At A Recommended Online Source, Stay On That Source**: If the user follows up with a named source from `商店 / 官方入口建议` or `在线候选建议` such as `OpenCode Skills`, `OpenClaw 生态技能榜`, or `SkillsMP`, treat it as a request to continue using that ONLINE source. Do NOT silently switch back to local-library scan/grep unless the user explicitly asks to inspect local libraries. The correct follow-up is: explain why that source is relevant, summarize what it is, and if helpful recommend how to evaluate/install/borrow from it next.
> 6. **Next Step Is Mandatory**: In `act`, always end with a concise subsection named `下一步推荐`, telling the user what to look at first and what command to run next (`check <来源>` or `steal <来源> <技能>`).
> 7. **Do Not Make Up Separate Command Semantics**: Explain `act` as the online recommendation view built on the current identity, not as a second check report.

> **CRITICAL RULE FOR RECOMMENDATION / ONBOARDING**:
> At the end of EVERY interaction (after presenting a scan, steal, check, or act result), you MUST proactively suggest/recommend ONE of the other 3 commands they haven't just used. For example, if they just ran `scan`, dynamically recommend them to run `steal <库> <技能>` or `act` to see their strategic review. Always provide a highly contextual, 1-2 sentence hook explaining what they will *get and feel* by running that next suggested command.
