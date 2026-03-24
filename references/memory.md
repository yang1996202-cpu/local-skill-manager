# light memory

这是 `skill-manager` 的轻量记忆约定。不是长期事实库，只记录最近几次高价值状态。

## 记录范围

- 最近一次 `scan` 的当前目标库
- 最近一次 `steal` 的来源、目标、模式（软链/复制）
- 最近一次 `check` 的主要问题摘要
- 最近一次 `act` 的主推荐方向

## 记录原则

- 只记短摘要，不写长报告
- 只记脚本确认过的事实
- 不记敏感信息
- 新状态覆盖旧状态，不做无限增长

## 建议格式

```text
last_scan_target=项目级 [xz]
last_steal=from:CC-Switch to:项目级 [xz] mode:symlink
last_check=1 个结构问题；1 个需要 API key 的技能
last_act=在线候选热度一般；优先本地库
```

## 使用约束

- 如果当前脚本输出与记忆冲突，以当前脚本为准。
- 记忆只能帮助“承接上下文”，不能覆盖现场事实。
