# skill-manager

让 Agent 管理本地 skill 库的工具。

现在有两个入口：

- `一键体验`：自动跑一轮 `scan / check / act`，再给一个 `steal preview`，默认只读
- `命令模式`：继续用 `scan / steal / check / act`

底层还是这 4 件事，只是入口不再逼人先理解命令：

- `scan`：在本地扫描所有技能库
- `steal`：从其他库或 GitHub 把 skill 装到这里
- `check`：检查当前库健康度，也会看已登记上游的 GitHub skill 是否落后上游
- `act`：联网后给轻量的下一步推荐；如果你没说需求，它会先追问一句，如果你直接说需求，它就按问题补排序

另外还有一个高级修复入口：

- `bind`：给已手动装好的 GitHub skill 补来源登记，不重装

## 它解决什么问题

只靠 Agent 临场处理，当然也能做。
但通常会遇到这几件事：

- 每次都从零开始，反复扫目录
- 迁移和检查的口径不稳定
- 装完 GitHub skill 之后，很快就忘了它来自哪里
- 下一次再问时，又要重新解释一遍上下文

`skill-manager` 不替代 Agent。
它只是把扫描、安装、检查、记账这些重复动作变成稳定命令和稳定结果。
Agent 继续负责判断、比较和收口。

## 装上以后有什么变化

- 空调用时先给你选：`一键体验` 或 `命令模式`
- 有固定命令：`scan / steal / check / act`
- 手动装好的 GitHub skill，也能用 `bind` 补溯源
- 有状态文件：`latest-scan.json`、`latest-health.json`、`history.jsonl`
- `check` 能顺手告诉你已登记上游的 GitHub skill 现在是不是落后上游

## 适合谁用

- 你手里已经有很多 Claude Code / Codex / OpenClaw / Amp skill
- 你不想手动翻目录、比对、复制、排兼容性
- 你希望 Agent 以后不是每次都从零开始管 skill

## Quick Start

```bash
git clone https://github.com/yang1996202-cpu/local-skill-manager.git ~/.claude/skills/skill-manager

# 直接进入双入口：一键体验 / 命令模式
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh

# 进入任意项目目录
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh scan

# 看某个来源值不值得偷
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh check CC-Switch

# 从别的库迁一个 skill 到这里
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal CC-Switch github

# 直接从 GitHub 安装一个 skill
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal https://github.com/KKKKhazix/Khazix-Skills

# 已经手动装好了，再补 GitHub 来源登记
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh bind glm-image https://github.com/ViffyGwaanl/glm-image/tree/main/glm-image

# 先看本地候选，再追问一句
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh act

# 直接按当前需求重排推荐
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh act 飞书知识库
```

`一键体验` 不是第五个正式命令，只是空调用时的一次组合流程。
它会把 `scan / check / act / steal preview` 串起来，让人先感受到价值，再决定要不要自己下命令。

`act` 默认就能跑，不要求用户先去配 API key。
如果 Agent 判断当前在线结果不够，再决定要不要接 `SKILLSMP_API_KEY` 这类增强来源。
而且 `act` 现在不只看在线结果，也会先看本地已扫描来源；如果你没说需求，它会先问一句“你现在更想补什么”，不再一上来就丢热榜。你如果直接给一句需求，它会继续保留“基于身份”的底座，再按这句需求把本地候选、SkillsMP、GitHub 需求搜索、趋势雷达一起重排。

## 状态记录

这不是另一套复杂系统，只是把最近一次跑出来的事实先记住。
这样你下一句再问时，Agent 不用每次都重新扫目录：

- `latest-scan.json` - 最新技能地图
- `latest-health.json` - 最新健康快照
- `history.jsonl` - 扫描 / 迁移 / 检查事件流

默认位置是 `~/.skill-manager/state/`。
`history.jsonl` 会自动裁剪，避免越跑越大。

如果是老早以前手动装进来的 GitHub skill，还没登记上游来源，
现在有两个补法：

- 重新跑一次 `steal <GitHub URL>`，如果同名 skill 已存在，会补登记而不重装
- 直接跑 `bind <技能名|路径> <GitHub URL>`，只补溯源，不动 skill 内容

## Rule System

这不只是一个 shell 脚本，也是一套给 Agent 用的轻规则：

- 空调用先给双入口，不强迫人类先学命令
- 先用 `scan / steal / check` 产出事实
- follow-up 优先读状态记录，再回答
- Agent 负责判断、比较、推荐，不重复手搓扫描

没有这层规则，脚本跑完之后，事实还是很容易在后续对话里丢掉。

## 补充

- 目标别名：`here`、`home-claude`、`home-openclaw`、`home-codex`、`home-amp`
- 可选环境变量：`SKILL_MANAGER_DATA_DIR`、`SKILL_MANAGER_TARGET`、`SKILL_MANAGER_HISTORY_LIMIT`
- `SKILLSMP_API_KEY`：只给 `act` 增强在线候选，不是必配项
- 标准输出样例： [scan-output-example.md](examples/scan-output-example.md)、[check-output-example.md](examples/check-output-example.md)、[act-output-example.md](examples/act-output-example.md)
- 核心说明： [SKILL.md](SKILL.md)、[output-contract.md](references/output-contract.md)、[decisions.md](docs/decisions.md)
- 更多内部文档在 `references/` 和 `docs/`

## License

MIT
