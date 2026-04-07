# output contract

这份文件定义 `scan / steal / check / act` 的固定输出边界。

## state-first follow-ups

命令刚跑完时，后续追问先读状态文件，再做中文总结。

- `scan` 后优先读 `~/.skill-manager/state/latest-scan.json`
- `check` 后优先读 `~/.skill-manager/state/latest-health.json`
- `steal` 后优先读 `~/.skill-manager/state/history.jsonl`

只有状态文件缺失、明显过期，或者用户问的是状态里没有的细节，才回退到新的目录扫描、`ls`、`find`、`grep` 或额外联网探测。

## scan

只做三件事：

1. 整体总表
2. 当前目标库结构
3. 最值得看的少数来源

禁止：

- 把所有来源全部展开
- 重算脚本已经给出的数量
- 用模糊比较词替代事实

## steal

只做四件事：

1. 说明从哪里迁到哪里
2. 说明是软链还是复制
3. 如果来源是 GitHub，说明跟踪的是哪个 repo / 子目录 / 提交
4. 说明是否成功并给一个紧邻的下一步

禁止：

- 自动发明 `check <skill-name>`
- 失败后偷偷造依赖并伪装成原版
- 把“已复制文件”说成“已经稳定可用”

## check

只做四件事：

1. 当前库 / 路线是谁
2. 整体健康度
3. 发现的问题（包括 GitHub 上游是否落后）
4. 下一步建议

禁止：

- 扩写成冗长大报告
- 把静态问题说成实机问题
- 自己补不存在的命令模式

## act

只做四件事：

1. 当前身份
2. 商店 / 官方入口建议
3. 在线候选建议
4. 下一步推荐

禁止：

- 再做一遍完整体检
- 把低星结果硬推成首选
- 给太多并列下一步

## next step rule

每次只主推一个下一步。

- `scan` 后优先推 `check <来源>`
- `steal` 后优先推 `check`
- `check` 后优先推 `act` 或一个最相关来源
- `act` 后优先推一个最相关本地动作
