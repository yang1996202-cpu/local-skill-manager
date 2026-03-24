# Example: `act`

这份样例定义 `act` 的标准展示方式。

## 目标

让任何 AI 都把 `act` 保持成轻量在线推荐，而不是第二份体检报告。

## 标准输出骨架

### 1. 当前身份

```text
目标宿主：Claude Code
已装技能：17 个
主题关键词：sales ai content knowledge
```

### 2. 商店 / 官方入口建议

| 入口 | 适合场景 |
|---|---|
| OpenCode Skills / Rules | 跨宿主技能与规则设计 |
| OpenClaw 生态技能榜 | 找现成跨宿主技能再做兼容性检查 |
| Claude Code 官方概览 | 核对项目规则与宿主行为 |

### 3. 在线候选建议

| 技能 | 作者 | 星数 | 说明 |
|---|---|---:|---|
| creating-sales-enablement | amogha-dalvi | 2 | 销售赋能内容 |
| write-sales-copy | sogadaiki | 0 | 销售文案 |

热度判断一句话就够：

`在线候选整体热度一般，建议当灵感清单，优先核对本地库和官方入口。`

### 4. 下一步推荐

只给一个最顺手的下一步：

```bash
check CC-Switch
```

## 禁止事项

- 不要再做一遍完整体检
- 不要把低星候选硬推成首选安装
- 不要一次给很多入口、很多候选、很多命令
