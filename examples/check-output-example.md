# Example: `check`

这份样例定义 `check` 的标准展示方式。

## 目标

让任何 AI 都把 `check` 讲清楚，但不讲长。

## 标准输出骨架

### 1. 当前在检查谁

```text
当前检查对象：项目级 [xz] 的 Claude Code 技能库
```

如果是路线模式：

```text
当前检查对象：从 CC-Switch 偷到项目级 [xz]
```

### 2. 整体状态

| 状态 | 数量 | 说明 |
|---|---:|---|
| 🟢 当前看起来可用 | 8 | 依赖检查通过 |
| 🟡 需配置 | 8 | 有宿主适配或配置问题 |
| 🔴 需操作 | 1 | 缺关键密钥 |

### 3. 发现的问题

只列关键项：

1. `deep-retrospect-workspace` 缺 `SKILL.md`
2. `seedream-image` 缺 API key
3. 部分从其他宿主迁来的 skill 有路径适配警告
4. 如果已有登记上游的 GitHub skill，也要顺手说清它们现在是否落后上游
5. 最好直接带一行 `来源: <GitHub URL>`，让人能一眼看懂自己这些 skill 从哪来的
6. 如果是整包 repo 落后，最好补 1 段短摘要：
   - `变更技能: office-hours`
   - `共享模块: bin`
   - `发布文件: VERSION, CHANGELOG.md`

### 4. 下一步

只给一个主动作：

```bash
act
```

或者：

```bash
check CC-Switch
```

## 禁止事项

- 不要把 `check` 讲成检查单个 skill
- 不要把静态通过说成实机验证通过
- 不要用“废技能”这类武断措辞
