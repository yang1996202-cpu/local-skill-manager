# reuse kit

这份文档说明两件事：

1. 我们从真实对话和两篇文章里提炼出的原则，已经如何落在 `skill-manager`
2. 以后别人想复用这套方法，最小需要带走什么

## 一、这套原则现在落在哪里

### 1. 总原则

放在 [constitution.md](../references/constitution.md)

这里定义了：

- 命令定义必须固定
- 先信脚本，再信总结
- 先信当前项目，再信主目录
- 用户给路径时，先信路径
- 状态必须和证据一致
- `check` 是主命令，`act` 是轻量在线视图

这部分对应的是“最高层规则”。

### 2. 真实踩坑

放在 [gotchas.md](../references/gotchas.md)

这里沉淀的是已经踩过的坑：

- 路径乱找
- 主目录和项目级混淆
- 软链误判
- 把失败说成成功
- 重算脚本数字

这部分对应的是“高语境知识比说明书更重要”。

### 3. 输出边界

放在 [output-contract.md](../references/output-contract.md)

这里把 `scan / steal / check / act` 的边界写死，避免模型二次发挥。

这部分对应的是：

- skill 不是随便写一段 prompt
- 要把“怎么说”也产品化

### 4. 执行清单

放在：

- [check-current.md](../references/checklists/check-current.md)
- [check-route.md](../references/checklists/check-route.md)

这部分对应的是：

- 好 skill 要有 checklist
- 要有门禁和固定检查项

### 5. 轻量记忆

放在 [memory.md](../references/memory.md)

这部分对应的是：

- skill 可以承接上下文
- 但不能让旧记忆盖过现场事实

### 6. 设计为什么这样定

放在 [decisions.md](decisions.md)

这部分对应的是：

- 以后迭代的人不需要重新猜“为什么当时这么改”

### 7. 标准样例

放在：

- [scan-output-example.md](../examples/scan-output-example.md)
- [check-output-example.md](../examples/check-output-example.md)
- [act-output-example.md](../examples/act-output-example.md)

这部分对应的是：

- 不光告诉 AI 原则，还告诉它“什么叫好输出”

## 二、这套方法和两篇文章的对应关系

我们提炼出来的主线是：

### 1. 好 skill 不是一段 prompt，而是一个工作环境

在 `skill-manager` 里的体现：

- `SKILL.md`
- `scripts/`
- `references/`
- `docs/`
- `examples/`

### 2. 高语境知识最值钱

在 `skill-manager` 里的体现：

- `gotchas.md`
- `decisions.md`

### 3. 好的 description / 入口定义会决定触发质量

在 `skill-manager` 里的体现：

- `SKILL.md` 开头固定 4 个命令定义

### 4. 好 skill 要有 checklist 和边界

在 `skill-manager` 里的体现：

- `checklists/`
- `output-contract.md`

### 5. skill 要能持续迭代，而不是一次性产物

在 `skill-manager` 里的体现：

- `memory.md`
- `gotchas.md`
- `decisions.md`
- `examples/`

## 三、以后怎么迭代

每次迭代都按这个落：

- 新坑：写进 `gotchas.md`
- 新边界：写进 `output-contract.md`
- 新流程：写进 checklist
- 新总原则：先看要不要改 `constitution.md`
- 新设计取舍：写进 `docs/decisions.md`
- 新好样例：写进 `examples/`

## 四、最小复用包

如果以后你要把这套方法复用到别的 skill，最小带走这 6 类文件就够了：

1. `SKILL.md`
2. `references/constitution.md`
3. `references/gotchas.md`
4. `references/output-contract.md`
5. `references/checklists/*.md`
6. `examples/*.md`

如果再完整一点，再带上：

7. `docs/decisions.md`
8. `references/memory.md`

## 五、现成模板

如果你不想自己重新拼，可以直接从这里复制：

- `templates/skill-governance/`

这份模板已经把目录骨架搭好了，适合新 skill 直接起步。
