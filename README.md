# skill-manager

一个给 AI 用的本地技能库管理器。

它解决 4 件事：

- `scan`：在本地扫描所有技能库
- `steal`：从其他技能库迁移到这里
- `check`：默认检查当前库健康度
- `act`：联网后按当前身份推荐 skills

适用场景：

- 你手里已经有很多 Claude Code / Codex / OpenClaw / Amp skill
- 你不想手动翻目录、比对、复制、排兼容性
- 你希望 AI 帮你做发现、迁移、诊断、推荐

## Quick Start

```bash
# 进入任意项目目录
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh scan

# 看某个来源值不值得偷
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh check CC-Switch

# 从别的库迁一个 skill 到这里
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal CC-Switch github

# 基于当前身份做在线推荐
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh act
```

## What It Does

### `scan`

在本地扫描所有技能库，先给你总表，再告诉你当前库结构和最值得看的来源。

### `steal`

把 skill 从别的库迁到当前目标库，支持软链和复制两种方式。

### `check`

默认检查当前库健康度；如果传来源，就检查“从 A 偷到这里”值不值。

### `act`

联网后，基于当前宿主、当前项目规则、当前已装 skill，给你轻量在线推荐。

## Install

```bash
git clone https://github.com/yang1996202-cpu/local-skill-manager.git ~/.claude/skills/skill-manager
```

## Common Commands

```bash
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh scan
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh steal <来源> <技能名>
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
- `SKILLSMP_API_KEY`

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
