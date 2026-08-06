const codexSubagentPolicy = `
## Codex 子 agent 路由

当 workflow 需要委派任务时：

- 优先选择 Codex 自定义 agent 配置（~/.codex/agents/*.toml）
- 必须显式使用 agent_type，例如 luna_high、luna_max、spark_xhigh
- 需要使用 agent 配置中的模型时，fork_turns 使用 none 或正整数
- task_name 只负责命名，不负责模型路由
`

module.exports = {
  tools: {
    codex: {
      instructions: {
        transform: content => `${content.trim()}\n\n${codexSubagentPolicy.trim()}\n`,
      },
    },
  },
}
