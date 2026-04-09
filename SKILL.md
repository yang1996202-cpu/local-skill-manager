---
name: skill-manager
description: >-
  PDCA 技能管家 — 发现推荐、偷取、诊断清理、演进方向。
  触发词："管理技能"、"看技能"、"偷技能"、"清理技能"、
  "skill manager"、"steal skills"、"check skills"。
---

运行方式：`bash <skill-dir>/scripts/skill-mgr.sh <command> [--to <target-lib>]`

| Step | Command | What |
|------|---------|------|
| Plan | `scan` | 在本地扫描所有技能库 |
| Do | `steal <来源> [技能]` | 从其他技能库迁移到这里，也可直接安装 GitHub URL |
| Check | `check [来源]` | 默认检查当前库健康度 |
| Act | `act [需求]` | 联网后推荐 skills；不写需求时按身份，有需求时再补排序 |

高级修复命令：`bind <技能名|路径> <GitHub URL>` = 给已手动装好的 GitHub skill 补来源登记，不重装

常用参数：`--to <目标库>` `--web` `--dry-run` `--copy` `--yes`
在线推荐可选环境变量：`SKILLSMP_API_KEY`
`--to` 友好别名：`here` `home-claude` `home-openclaw` `home-codex` `home-amp`

核心护栏文件在这里：

- `references/constitution.md`
- `references/gotchas.md`
- `references/checklists/check-current.md`
- `references/checklists/check-route.md`
- `references/output-contract.md`
- `references/memory.md`
- `docs/decisions.md`

如果行为边界不清楚，优先相信这些文件，不要现场自由发挥。

建议阅读顺序：

1. `references/constitution.md`
2. `references/output-contract.md`
3. `references/checklists/check-current.md` or `references/checklists/check-route.md`
4. `references/gotchas.md`
5. `references/memory.md`
6. `docs/decisions.md`

> **CRITICAL RULE FOR INITIALIZATION**:
> 当你在没有明确参数时被触发（例如 `/skill-manager`），第一条回复必须是：礼貌打招呼，然后只展示两个入口：
> - `一键体验` = 我来自动跑一轮 `scan / check / act`，再给一个 `steal preview`（默认只读）
> - `命令模式` = 继续用 `scan / steal / check / act`
> 这里不要先自动跑，也不要先丢四命令表格。先把选择交还给用户。
> 只有当用户明确选择 `命令模式` 时，才展示原来的 4 命令表格：
> - `scan` = 在本地扫描所有技能库
> - `steal` = 从其他技能库或 GitHub 迁移到这里
> - `check` = 默认检查当前库健康度
> - `act` = 联网后按当前身份推荐 skills
> 除非用户要求，否则不要展开成 `PDCA 哲学解释`、`典型用法`、`技能管家分身故事` 或长篇参数教程。

> **CRITICAL RULE FOR ONE-CLICK EXPERIENCE**:
> 当用户选择 `一键体验` 时，这不是第五个正式命令，而是一段只读优先的组合流程。顺序固定为：
> 1. `scan`
> 2. `check`
> 3. `act`
> 4. `steal preview`
> 实现时优先直接运行：`bash <skill-dir>/scripts/skill-mgr.sh experience [可选需求]`。
> 不要再手动串四个命令、自己播报阶段、自己重算数字；脚本已经有统一的一键体验收口。
> 这里的 `steal preview` 只能预演，不要直接安装 skill，也不要偷偷改库。
> 输出方式不要像四段工具日志，而要先给一句总判断，再自然讲：
> - 当前有什么
> - 当前缺什么
> - 现在最值得补什么
> - 如果现在只试 1 个，先看哪个来源 / 哪个 skill / 为什么
> 结尾再补一句短回执：`你刚刚体验到的是：scan / check / act / steal-preview`。

> **CRITICAL RULE FOR STATE-FIRST FOLLOW-UPS**:
> `skill-manager` 现在会把最近一次 `scan / check / steal` 的结果写到 `~/.skill-manager/state/`。当用户紧接着继续追问时，先读状态文件，再组织中文结论，不要第一反应就重新 `ls/find/grep`。
> - 刚跑完 `scan`，或用户在问“当前装了什么 / 一共有多少库 / 当前库结构” → 先读 `latest-scan.json`
> - 刚跑完 `check`，或用户在问“健康度 / 问题 / 要删什么 / 这条偷取路线怎样 / 某个来源大概有哪些可偷” → 先读 `latest-health.json`
> - 刚跑完 `steal`，或用户在问“刚刚到底新增了什么 / 最近做过什么动作” → 先读 `history.jsonl`
> 只有当状态文件缺失、明显过期，或者用户问的是状态里没有的细节时，才回退到新的目录扫描或额外 GitHub 探测。
> 如果这一步不得不离开 `skill-manager` 的托管路径（例如脚本还不支持直接安装某类 GitHub URL），要明确告诉用户：这是脚本外 fallback，不要伪装成 `skill-manager` 原生能力。

> **CRITICAL RULE FOR SCAN OUTPUT**: 
> 当用户运行 `scan` 时，必须先展示“整体总表”，列出每个外部库、技能总数和脚本给出的具体位置。要保留脚本里的“当前操作对象 / 当前项目上下文 / 当前目标库结构”这些部分，因为这些信息能让结果更确定。推荐部分遵循脚本的精简默认：只先展开最值得看的少数来源，剩下的用简短线索带过，不要把所有库一次性铺满。
> 1. **Do Not Use Fuzzy Equivalence Claims**: Do NOT summarize one library as `同上`, `几乎一样的技能池`, `差不多`, or similar unless you have explicit overlap evidence from the script. If you want to compare two libraries, state the concrete reason instead, for example: `来源不同，但当前缺失技能数量接近`, or `前几项候选高度重合`.
> 2. **Do Not Recompute Counts**: If the script says the current library has `14` skills, do not re-count and accidentally list 15+. Reuse the script's numbers and keep entity/softlink counts consistent with the emitted structure section.

> **CRITICAL RULE FOR CHECK / ACT**:
> 把 `check` 当成主命令。`act` 不是第二套完整体检系统，它只是基于当前身份和宿主的轻量在线推荐视图。
> 1. **Check First, In Simple Language**: 当用户运行 `check` 时，用简单中文解释：要么是在检查 `当前这里`，要么是在检查 `从 A 偷到这里`。不要过度强调参数或内部术语。
> 1.1. **Do Not Invent `check <skill-name>` Semantics**: `check` is for the current target library, or for a source-to-target route such as `check CC-Switch`. Do NOT suggest `check <单个技能名>` unless the script explicitly supports that mode.
> 2. **Honor Context Files (上下文优先级)**: 使用脚本产出的项目上下文文件、身份文件和规则文件清单，不要随意改写优先级。最近的项目级文件优先于主目录记忆。如果 `AGENTS.md`、`CLAUDE.md`、`CODEX.md`、`rules`、成员文件或宿主身份文件冲突，要明确说明你优先使用了最近的项目文件。
> 2.1. **If User Gives An Exact Path, Trust The Path First**: 当用户给了明确绝对路径（例如 `/Users/.../web-access`），就把这个路径当成权威输入。先检查这个路径是否存在、它属于项目级库还是用户级库，再清楚说明结果。除非用户要求扩大搜索，否则不要跳去 `scan`、`grep` 或别的库乱找。
> 2.2. **State Must Match Evidence**: 只有紧挨着的探针或命令真正成功了，才能说 `ready`、`connected`、`已启动`、`搞定`、`完全可用`。如果命令非零退出、超时或报缺文件，就保持保守，说明还卡在哪一步。
> 3. **Act Must Stay Lightweight**: 不要把 `act` 扩写成完整健康报告、场景聚类分析或巨大武器库巡检。`act` 只聚焦在线推荐和下一步指引。
> 3.1. **Question-First When Intent Is Missing**: 如果用户只是裸跑 `act`，但没有说自己想补什么，就先给 `当前身份判断 + 本地候选建议`，然后追问一句很短的人话问题，再进入下一轮问题驱动推荐。不要第一反应就丢 SkillsMP 热榜、GitHub 热榜和大表格。
> 4. **Local Candidates Are Mandatory**: 在 `act` 里，必须先给一个单独的小节叫 `本地候选建议`。这里优先推荐本机已经扫描到、但当前目标库还没装的 skill 来源。因为这些来源往往更接近“现在就能偷、现在就能试”的状态。
> 4.1. **Problem-Driven Re-Ranking Is Allowed**: 如果用户直接说了自己想找什么（例如“找记忆类”“找飞书知识库”“找图像生成”），那 `act` 继续保留“基于身份”的底座，但要把这句需求当成附加排序信号，优先重排本地候选、SkillsMP 和趋势雷达。
> 5. **Online Discovery Radar Is Mandatory**: 在 `act` 里，必须有一个单独的小节叫 `在线发现雷达`。这个小节里至少要包含：
> - `商店 / 官方入口建议`
> - `在线候选建议`（优先 `SkillsMP`，没有再退到网页来源）
> 如果用户给了明确需求，也可以补一层 GitHub 需求搜索；但这层是探索项，不替代本地候选和 `check / steal`。
> 如果本机装了 `github-trending-cn`，也要把它当成额外发现源自动接进去，但只能标成探索项，不要直接当强推荐。
> 5.1. **Do Not Over-Sell Weak Online Candidates**: 把 `SkillsMP` 结果先当搜索命中，不要直接当强推荐。如果脚本已经表明在线候选热度弱、星数低、或者只有一个明显强命中，就要明确说这是“探索项”，不是首选安装项。不要因为语义相关就把低星候选吹成最高优先级。
> 5.2. **If User Points At A Recommended Online Source, Stay On That Source**: 如果用户追问的是 `商店 / 官方入口建议` 或 `在线候选建议` 里已经点名的在线来源，比如 `OpenCode Skills`、`OpenClaw 生态技能榜`、`SkillsMP`，那就继续沿着这个在线来源往下讲。除非用户明确要求看本地库，否则不要悄悄切回本地 `scan/grep`。正确做法是：解释这个来源为什么相关、它是什么、下一步怎么评估或安装或借用。
> 6. **Next Step Is Mandatory**: 在 `act` 结尾，必须有一个简短小节叫 `下一步推荐`，明确告诉用户先看什么、下一条该跑什么命令（例如 `check <来源>` 或 `steal <来源> <技能>`）。
> 7. **Do Not Make Up Separate Command Semantics**: 解释 `act` 时，要把它说成“基于当前身份的在线推荐视图”，不要讲成另一份 `check` 报告。

> **CRITICAL RULE FOR GITHUB SOURCES**:
> 当用户直接给出 GitHub skill 仓库或 tree URL，并且意图是“装进来 / 安装这个 skill”时，优先走 `skill-manager` 自己的 `steal <GitHub URL>` 路径，不要第一反应绕出去手动 `git clone + cp`。如果用户说的是“这个 skill 已经手动装好了，但我想补溯源 / 想知道它来自哪”，优先走 `bind <技能名|路径> <GitHub URL>`。如果像 `gstack` 这种 repo-root 的多 skill 包不适合整包 `steal`，允许先按仓库 README 安装，再用 `bind` 把整个包根目录纳入追踪。如果脚本已经把 GitHub 来源写入元信息，那么后续 `check` 应该把它当成可跟踪上游的 skill，而不是一次性拷贝后就失忆。

> **CRITICAL RULE FOR RECOMMENDATION / ONBOARDING**:
> 每次交互结束时（无论刚展示的是 `scan`、`steal`、`check` 还是 `act`），都要主动推荐另外 3 个命令里最合适的 1 个。比如用户刚跑完 `scan`，就可以推荐 `steal <库> <技能>`，或者推荐 `act` 去看更高层的下一步。这个推荐只要 1 到 2 句，但要结合上下文，说清用户跑了之后会得到什么。

> **USE THE REFERENCE FILES, NOT JUST MEMORY OF THIS PROMPT**:
> 1. 先读 `references/constitution.md`，确认固定命令模型和优先级规则。
> 2. 要总结坑点之前，先看 `references/gotchas.md`。
> 3. 要解释 `check` 之前，对齐 `references/checklists/check-current.md` 或 `references/checklists/check-route.md`。
> 4. 要把命令结果改写成自然语言之前，先遵守 `references/output-contract.md`。
> 5. 如果要跨轮承接上下文，只能用 `references/memory.md` 里定义的轻量方式。
> 6. 如果想知道这些规则为什么这样定，再看 `docs/decisions.md`。
