export const CLI_OVERVIEW = `AppReveal CLI

Purpose for LLMs:
This CLI gives an LLM a stable shell interface for AppReveal MCP servers on the local network.
Use it when the model needs to discover debug builds, identify devices, inspect available MCP tools,
and send either normal tool calls or raw MCP JSON-RPC requests without hand-building curl commands.
It is designed for fleets, not just one device. The same command can fan out across several iOS,
macOS, Android, Flutter, or React Native targets in parallel.

How an LLM should use it:
1. Run \`appreveal discover\` to find available AppReveal targets on the LAN.
2. If more than one target is visible, pick one by service name, bundle ID, hostname, IP address, or full URL.
3. Use \`--all\`, repeated \`--target\`, or \`--platform ios,macos,android,flutter,reactnative\` to control multiple devices at once.
4. Run \`appreveal snapshot\`, \`find\`, \`tap\`, and \`type\` for common UI-control flows.
5. Run \`appreveal inspect\`, \`call\`, or \`request\` when you need lower-level control.

What counts as a target:
- Full URL: \`http://192.168.1.24:49152/\`
- Service name: \`AppReveal-com.example.app\`
- Bundle ID: \`com.example.app\`
- Hostname: \`AppReveal-com.example.app.local\`
- IP address: \`192.168.1.24\`

Notes:
- Discovery is AppReveal-specific. It browses mDNS for \`_appreveal._tcp\`.
- The CLI prints all resolved IP addresses it can find.
- "codes" in discovery output means any code-like metadata the target exposes now, such as build numbers,
  version codes, or future TXT records like pairing codes, pins, or tokens.
- Any command that acts on targets can be narrowed with \`--platform\`.
- Use \`--json\` whenever another tool or model will parse the output.
`;

export const HELP_EXAMPLES = `Examples:
  appreveal discover
  appreveal discover --platform ios,macos
  appreveal discover --json
  appreveal inspect com.example.shop
  appreveal inspect --all --platform ios --device-info
  appreveal snapshot --all --platform android,flutter
  appreveal find "login" --all
  appreveal tap "login.submit" --all
  appreveal type "hello@example.com" --element login.email --target com.example.shop --target com.example.shop.android
  appreveal tools --target 192.168.1.24 --target 192.168.1.25
  appreveal call get_screen --all
  appreveal call com.example.shop get_screen
  appreveal call batch --target http://192.168.1.24:49152/ --args '{"actions":[{"tool":"get_screen"},{"tool":"get_elements"}]}'
  appreveal request tools/list --all
  appreveal request com.example.shop tools/call --params '{"name":"get_logs","arguments":{"limit":20}}'
`;
