---
applyTo: "**"
---

# Machine-wide BYOK subagent policy

For every subagent launch through task, Task, functions.task, or the VS Code Agent alias, the only allowed model is exactly:

`customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol`

Always pass that exact identifier in task.model. Never omit task.model and never select, substitute, or fall back to any other model. If the exact model is unavailable, do not launch a subagent. The parent chat model is unrestricted.
