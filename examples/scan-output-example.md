# Example: scan 命令输出参考

本示例展示了 `scan` 命令的标准输出结构，供 AI 在展示结果时参考。

## 使用场景

用户运行 `scan` 查看当前项目技能库缺什么。

## 标准输出结构

### 1. 整体总表（必须首先展示）

展示所有外部库的概览，让用户看到全局蓝图：

| 库 | 技能数 | 路径 |
|----|-------|------|
| CC-Switch | 70 | `~/.cc-switch/skills` |
| Amp | 61 | `~/.agents/skills` |
| OpenClaw | 53 | `~/.openclaw-autoclaw/workspace/.opencode/skills` |
| WorkBuddy | 45 | `~/.workbuddy/skills-marketplace/skills` |
| **项目级** 🎯 | **13** | **`~/xz/.claude/skills`** |
| ... | ... | ... |

**共计 370 个技能，22 个库**

---

### 2. 当前目标库结构

展示当前项目已安装的技能实体：

```
🧱 当前目标库结构:
- 实体  article-illustrator
- 实体  bm-md
- 实体  consult
- 实体  deep-retrospect
- 实体  writing-clone
- 实体  writing-team
- 实体  x-reader
- 实体  xuehui-video-ops
... (共 13 个)
```

---

### 3. 可偷取技能清单（完整展示）

按库分组，展示用户还没有的技能，**不要压缩或省略**：

#### ✅ 从 CC-Switch 偷到这里 — 70/70 个你还没有的

| 技能 | 说明 |
|------|------|
| 1password-1.0.1 | 1Password CLI 设置与使用 |
| a-stock-analysis-1.0.0 | A股实时行情与分时量能分析 |
| agent-browser | 浏览器自动化 CLI |
| ... | ... |
| x-reader | 读取国内链接内容（微信公众号、小红书、B站等） |
| xhs-browser | 小红书浏览器自动化 |

#### ✅ 从 Amp 偷到这里 — 63/63 个你还没有的
...

#### ✅ 从 WorkBuddy 偷到这里 — 44/45 个你还没有的
...

---

### 4. 下一步建议

给出明确的下一步操作：

```bash
steal CC-Switch agent-browser x-reader feishu-doc-1.2.7
```

或者运行 `act` 看完整战略建议。

---

## AI 展示要点

1. **先展示整体总表** —— 用户需要全局视图
2. **保留原始输出结构** —— 不要修改脚本输出的格式
3. **完整展示技能清单** —— 不要总结或压缩，用户需要看到所有选项
4. **给出明确的下一步** —— 推荐具体的 steal 命令或其他命令

## 关键规则

- **整体总表必须最先展示**（硬约束）
- **技能清单必须完整**（硬约束）
- **推荐命令必须具体**（硬约束）
