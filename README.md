# skill-manager

PDCA 技能管家 — 发现、偷取、诊断、推荐 Claude Code / OpenClaw / Codex 技能。

## 一句话描述

管理 AI 编辑器技能库的瑞士军刀：扫描（Plan）→ 偷取（Do）→ 诊断（Check）→ 推荐（Act）。

## 安装

```bash
# 克隆到 Claude Code 技能目录
git clone https://github.com/YOUR_USERNAME/skill-manager.git ~/.claude/skills/skill-manager
```

## 使用

```bash
# 进入任意项目目录，运行
bash ~/.claude/skills/skill-manager/scripts/skill-mgr.sh <命令>
```

## 命令

| 命令 | 作用 |
|------|------|
| `scan` | 扫描所有可用技能库，看看外面有什么 |
| `steal <来源> [技能名]` | 从别处偷技能到当前项目 |
| `check [来源]` | 诊断当前库健康度，或检查从某处偷取的兼容性 |
| `act` | 基于项目身份做在线推荐 |

## 示例

```bash
# 1. 扫描所有库
bash skill-mgr.sh scan

# 2. 检查从 CC-Switch 偷技能是否值得
bash skill-mgr.sh check CC-Switch

# 3. 偷取 github 技能
bash skill-mgr.sh steal CC-Switch github

# 4. 获取个性化推荐
bash skill-mgr.sh act
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `SKILL_MANAGER_DATA_DIR` | 数据目录，默认 `~/.skill-manager` |
| `SKILL_MANAGER_TARGET` | 目标技能库路径 |
| `SKILLSMP_API_KEY` | SkillsMP 在线推荐 API 密钥（可选） |

## 支持的目标库别名

- `here` - 当前目录的 `.claude/skills`
- `home-claude` - `~/.claude/skills`
- `home-openclaw` - `~/.opencode/skills`
- `home-codex` - `~/.codex/skills`
- `home-amp` - `~/.amp/skills`

## 原理

基于 PDCA 循环设计：

1. **Plan (scan)** - 收集信息，了解有哪些技能可用
2. **Do (steal)** - 执行偷取，将技能复制到目标库
3. **Check (check)** - 诊断健康度，检查依赖和兼容性
4. **Act (act)** - 基于项目身份和在线数据给出推荐

## 许可证

MIT
