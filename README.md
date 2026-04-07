# skill-manager

让 Agent 管理本地 skill 库的工具。

它不是另一个聊天 Agent。
它做的是 Agent 经常会重复做、但每次临时做都很散的几件事：

- 看看这台机器上到底有哪些 skill 库
- 把 skill 装进当前库
- 检查当前库现在是不是健康、哪些 skill 有问题
- 看 GitHub 装来的 skill 是不是已经落后于上游

## 为什么要有这个 skill

直接让 Agent 临时处理，当然也能做。

但通常会有 4 个问题：

- 每次都从零开始，反复扫目录
- 迁移和检查的口径不稳定
- 装完 GitHub skill 之后，很快就忘了它来自哪里
- 下一次再问时，又要重新解释一遍上下文

装了 `skill-manager` 之后，这些事情会变成固定命令和固定结果：

- `scan`：看全局 skill 盘子
- `steal`：把 skill 装进当前库，支持本地来源和 GitHub
- `check`：看当前库是否健康，也能看 GitHub skill 是否落后上游
- `act`：给一个轻量的下一步在线建议

## 它和 Agent 的分工

- Agent：理解你现在要做什么，帮你判断、比较、收口
- `skill-manager`：提供稳定的扫描、迁移、检查和状态记录

一句话说：

**Agent 负责智能判断，`skill-manager` 负责把这些重复动作变成稳定流程。**

## 适合谁用

- 你手里已经有很多 Claude Code / Codex / OpenClaw / Amp skill
- 你不想手动翻目录、比对、复制、排兼容性
- 你希望 Agent 以后不是每次都从零开始管 skill

## 4 个命令

- `scan`：在本地扫描所有技能库
- `steal`：从其他库或 GitHub 把 skill 装到这里
- `check`：默认检查当前库健康度，也会看 GitHub skill 是否落后上游
- `act`：联网后给轻量的下一步推荐

## Quick Start

```bash
# 进入任意项目目录
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh scan

# 看某个来源值不值得偷
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh check CC-Switch

# 从别的库迁一个 skill 到这里
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal CC-Switch github

# 直接从 GitHub 安装一个 skill
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal https://github.com/KKKKhazix/Khazix-Skills

# 基于当前身份做在线推荐
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh act
```

## 具体会得到什么

### `scan`

你会知道：

- 这台机器上有哪些 skill 库
- 当前目标库是什么结构
- 最值得看的来源是哪几个

### `steal`

你可以：

- 从本地别的 skill 库迁一个 skill 过来
- 直接从 GitHub 仓库或 tree URL 安装一个 skill

### `check`

你会看到：

- 当前库有没有坏链、缺文件、宿主兼容问题
- 某个来源值不值得偷
- GitHub 装来的 skill 现在是不是已经落后上游

### `act`

你会拿到：

- 一个轻量的在线补充方向
- 不是大报告，只是下一步该先看什么

## Install

```bash
git clone https://github.com/yang1996202-cpu/local-skill-manager.git ~/.claude/skills/skill-manager
```

## Common Commands

```bash
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh scan
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal <来源> <技能名>
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal <GitHub URL>
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh check
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh check <来源>
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh act
```

## Target Aliases

- `here`
- `home-claude`
- `home-openclaw`
- `home-codex`
- `home-amp`

## Optional Env

- `SKILL_MANAGER_DATA_DIR`
- `SKILL_MANAGER_TARGET`
- `SKILL_MANAGER_HISTORY_LIMIT`
- `SKILLSMP_API_KEY`

## MVP State Files

现在这版开始把“稳定事实”落盘，方便 Agent 读取：

- `latest-scan.json` - 最新技能地图
- `latest-health.json` - 最新健康快照
- `history.jsonl` - 扫描 / 迁移 / 检查事件流

默认会自动裁剪 `history.jsonl`，只保留最近一段事件，避免状态层越跑越大。

默认位置：

- `~/.skill-manager/state/`

这也是这版 MVP 最核心的变化：

- `skill-manager` 先负责产出事实
- Agent 再负责解释、比较、推荐

## Standard Examples

标准输出样例在这里：

- [scan-output-example.md](examples/scan-output-example.md)
- [check-output-example.md](examples/check-output-example.md)
- [act-output-example.md](examples/act-output-example.md)

## Rule System

这不是只有脚本的项目，它也是一套可迭代的规则系统：

- [SKILL.md](SKILL.md)
- [constitution.md](references/constitution.md)
- [gotchas.md](references/gotchas.md)
- [output-contract.md](references/output-contract.md)
- [check-current.md](references/checklists/check-current.md)
- [check-route.md](references/checklists/check-route.md)
- [memory.md](references/memory.md)
- [decisions.md](docs/decisions.md)

## Reuse

如果你想把这套方法复用到别的 skill：

- 说明文档看 [reuse-kit.md](docs/reuse-kit.md)
- 模板目录看 `templates/skill-governance/`

## License

MIT
