# AppReveal Mac Example

Example AppKit app demonstrating AppReveal on macOS.

## Setup

```bash
brew install xcodegen  # if needed
cd example/macOS/AppRevealMacExample
xcodegen generate
xcodebuild -project AppRevealMacExample.xcodeproj \
  -scheme AppRevealMacExample \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
open AppRevealMacExample.xcodeproj
```

Run the `AppRevealMacExample` scheme from Xcode. The app starts AppReveal in `#if DEBUG` from `App/AppDelegate.swift`.

## Verify with curl

Once the app is running:

```bash
# Discover the advertised service
dns-sd -B _appreveal._tcp local.

# Initialize MCP
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# List windows
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_windows","arguments":{}}}'

# Read the menu bar
curl -X POST http://localhost:<port>/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_menu_bar","arguments":{}}}'
```

Expected results:

- `initialize` returns the server capabilities
- `list_windows` returns at least one window ID
- `get_menu_bar` returns the app menu hierarchy
