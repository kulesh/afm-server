# ADR 0001: OpenAI-Compatible Tool Calling via Apple Foundation Models

## Status
Accepted

## Date
2026-02-25

## Context
`afm-server` exposes an OpenAI-compatible chat API on top of Apple Foundation Models. It currently supports plain chat completions and streaming text, but it does not accept or return tool-calling fields (`tools`, `tool_choice`, `tool_calls`).

Clients that depend on OpenAI function/tool calling cannot use this server as a drop-in replacement for agent workflows.

## Decision
Add first-class tool-calling support to `/v1/chat/completions` by mapping OpenAI-style tool definitions to Foundation Models tools and returning OpenAI-compatible tool call objects.

Implemented scope:
- Extend request decoding in `ChatCompletionRequest` to accept:
  - `tools` (function tools with JSON schema parameters)
  - `tool_choice` (`auto`, `none`, or specific function)
- Extend response encoding to include assistant `tool_calls` and corresponding finish reasons.
- Add a tool-aware generation loop in `FoundationModelsClient`:
  - Provide registered Swift tools to `LanguageModelSession`.
  - Return OpenAI-compatible `tool_calls` on first tool turn.
  - Accept follow-up tool result messages (`role=tool`) and continue completion.
- Preserve backward compatibility for clients that do not send tools.

## Design Notes
- Use a curated in-process tool registry (explicitly coded tools), not arbitrary runtime code execution.
- Restrict tool JSON schema support to a safe subset initially (object, string/number/boolean/integer, required).
- Keep streaming behavior unchanged for non-tool responses; streaming tool-call deltas remain deferred.

## Consequences
Positive:
- Enables agentic workflows and improves OpenAI API compatibility.
- Keeps on-device inference while supporting structured actions.

Negative:
- Adds protocol and state-machine complexity.
- Requires careful validation, error mapping, and deterministic tool execution behavior.

## Security and Safety
- Do not allow dynamic shell/file/network tools by default.
- Require explicit registration for each tool and input validation before execution.
- Cap tool execution time and payload size; return structured tool errors.

## Rollout Status
1. Completed: request/response model fields and compatibility tests.
2. Completed: curated built-in tool registry and non-streaming tool-call flow.
3. Completed: tests for `tool_choice=auto/none/forced`, unknown tools, malformed args, and timeout guardrails.
4. Pending follow-up: optional streaming tool-call deltas.

## Alternatives Considered
- **No tool calling support**: simplest, but limits compatibility with modern OpenAI clients.
- **Custom non-OpenAI tool API**: easier internally, but reduces drop-in interoperability.
