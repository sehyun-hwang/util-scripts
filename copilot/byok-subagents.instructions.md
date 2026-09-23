---
applyTo: "**"
---

# Machine-wide Copilot subagent model policy

For every subagent launch through task, Task, functions.task, or the VS Code Agent alias, the only allowed models are:

- `customendpoint/cliproxyapi customendpoint/chatgpt/gpt-6-sol`
- `customendpoint/cliproxyapi customendpoint/chatgpt/gpt-6-luna`

Always pass one of these exact identifiers in task.model. Never omit task.model and never select, substitute, or fall back to any other model. If neither model is available, do not launch a subagent. The parent chat model is unrestricted.
