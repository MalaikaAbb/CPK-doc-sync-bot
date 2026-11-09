
## mastra specifics

- Docs root: `https://docs.copilotkit.ai/mastra`. **There is no `backend/`.** The
  Mastra agents live in `frontend/src/mastra/` and run inside the Next app.
- **zod is pinned to exactly 3.25.76** for A2UI. `@mastra/memory` wants zod 4
  and gets its own nested copy, which is fine. Don't change the root pin, and
  don't switch imports to `zod/v3`.
- **`ai` is a direct dependency at ^7** because `@ai-sdk/openai` 4.x models need
  ai 7; on ai 6, code that calls `generateText` directly throws
  `UnsupportedModelVersionError`. Keep that pairing.
- `npm install <pkg>` here can also move `@mastra/core` within its `^` range.
  If a package was added, list any version drift in your final message.
