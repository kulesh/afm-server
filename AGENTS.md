# Repository Guidelines

## Project Structure & Module Organization
This repository is a Swift Package Manager menu bar app. Core code lives in `Sources/AFMServer/`:
- `App.swift`: app entry point and startup flow.
- `Server/`: HTTP transport (`HTTPServer`) and request orchestration (`ServerManager`).
- `LLM/`: Apple Foundation Models integration.
- `Models/`: OpenAI-compatible request/response payload types.
- `MenuBarView.swift`: SwiftUI status/control UI.

Build artifacts are generated under `.build/` and should not be edited or committed.

## Build, Test, and Development Commands
- `swift run`: build and launch the app (starts local API server via menu bar app).
- `swift build`: compile without launching UI.
- `swift test`: run unit tests (add tests first; no default test target exists yet).

Useful local checks:
- `curl http://127.0.0.1:11535/health`
- `curl -X POST http://127.0.0.1:11535/v1/chat/completions ...`

## Coding Style & Naming Conventions
- Use Swift 6.2 conventions and 4-space indentation.
- Types/protocols: `UpperCamelCase`; methods/properties: `lowerCamelCase`.
- Keep one primary type per file and name files after that type (for example, `ServerManager.swift`).
- Prefer structured concurrency patterns already in use (`actor`, `async/await`, `@MainActor`) for shared state and UI-bound logic.
- Use `// MARK:` sections to keep files navigable.

## Testing Guidelines
Use XCTest with SwiftPM under `Tests/AFMServerTests/`.
- Test file naming: `<Feature>NameTests.swift`.
- Test method naming: `testBehaviorExpectedResult`.
- Prioritize coverage for request parsing, `/health`, `/v1/models`, chat completion, and error responses.

Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit subjects (for example, `Simplify README`, `Fix server startup ...`).
- Keep subject lines concise and action-oriented.
- PRs should include: purpose, behavior changes, and manual verification steps.
- For API or UI changes, include a sample `curl` request/response or a menu bar screenshot.

## Security & Configuration Tips
- Runtime target is macOS 26+ on Apple Silicon with Apple Intelligence enabled.
- Keep the service bound to local workflows (`127.0.0.1`) unless there is an explicit requirement to expose it.
