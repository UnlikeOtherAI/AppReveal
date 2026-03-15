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

## Conventions

- All framework code behind `#if DEBUG`
- Screen keys: dot-separated hierarchy (e.g. `auth.login`)
- Element IDs: screen-prefixed accessibility identifiers (e.g. `login.email`)
- One public entry point: `AppReveal.start()`
- Protocols for app integration: `ScreenIdentifiable`, `StateProviding`, `NavigationProviding`, `FeatureFlagProviding`, `NetworkObservable`
