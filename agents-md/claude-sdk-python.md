
## claude-sdk-python specifics

- Docs root: `https://docs.copilotkit.ai/claude-sdk-python`. Backend: Python with `uv`.
- **Interrupts (`/human-in-the-loop/governed-actions`):** `ag_ui_claude_sdk`
  emits a real AG-UI interrupt for tools in `ClaudeAgentAdapter(defer_tools=...)`,
  but it only resumes a deferred tool served by a **stdio MCP server**, not an
  in-process `create_sdk_mcp_server` tool. The resume payload is
  `{behavior: "allow" | "deny"}` (send a reason with deny), and interrupt
  metadata is `{source, toolName, input}`, not the doc's `metadata.action`.
  The route deliberately shows the doc version (broken) and the fixed version
  side by side. Keep both.
- `useInterrupt` writes to one global slot, so never put two interrupt demos on
  one page, and give each interrupt route its own agent.
