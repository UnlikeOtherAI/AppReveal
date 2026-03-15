# AppReveal

@./AGENTS.md

## Project

Debug-only in-app MCP framework for iOS (Android planned). Gives LLM agents native app control via standard MCP protocol.

## Key docs

- `docs/architecture.md` -- system design, modules, protocols, package structure
- `docs/brief.md` -- phased build plan with task checkboxes

## Stack

- Swift, iOS 16+, Swift Package Manager
- Network framework (NWListener) for HTTP server
- Bonjour/mDNS for discovery
- MCP Streamable HTTP transport
- No private APIs, no SwiftUI internals

## Structure

```
iOS/                    -- Swift package (iOS implementation)
docs/                   -- architecture and build brief
```

## Workflow

- Always commit and push to the repo after each turn. There should never be uncommitted code when you stop a task.
- Before every commit, and absolutely before any release/tag: build the example app, launch it on a simulator, and verify changes work end-to-end through the actual MCP protocol (curl against the running server). Do not rely on just compiling — test the real HTTP/JSON-RPC path.
- Keep documentation (README.md, docs/, example README) up to date on every turn. If tools, features, or APIs changed, update the docs in the same commit.

## Conventions

- All framework code behind `#if DEBUG`
- Screen keys: dot-separated hierarchy (e.g. `auth.login`)
- Element IDs: screen-prefixed accessibility identifiers (e.g. `login.email`)
- One public entry point: `AppReveal.start()`
- Protocols for app integration: `ScreenIdentifiable`, `StateProviding`, `NavigationProviding`, `FeatureFlagProviding`, `NetworkObservable`
