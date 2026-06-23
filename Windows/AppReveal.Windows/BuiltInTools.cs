using System.Text.Json.Nodes;

namespace AppReveal.Windows;

internal static class BuiltInTools
{
    private const int MaxBatchActions = 100;
    private const int MaxBatchDelayMs = 30000;

    private static JsonObject NoArgs() => new() { ["type"] = "object", ["properties"] = new JsonObject() };

    private static JsonObject ObjectSchema(params (string Name, JsonNode Schema)[] properties)
    {
        return ObjectSchema(Array.Empty<string>(), properties);
    }

    private static JsonObject ObjectSchema(string[] required, params (string Name, JsonNode Schema)[] properties)
    {
        var props = new JsonObject();
        foreach (var (name, schema) in properties)
        {
            props[name] = schema;
        }

        var schemaObject = new JsonObject { ["type"] = "object", ["properties"] = props };
        if (required.Length > 0)
        {
            schemaObject["required"] = new JsonArray(required.Select(name => (JsonNode?)name).ToArray());
        }

        return schemaObject;
    }

    public static void Register(McpRouter router, AppRevealRuntime runtime)
    {
        Register(router, "list_windows", "List visible app windows and their IDs.", NoArgs(), (_, cancellationToken) => runtime.ListWindows(cancellationToken));
        if (runtime.HasDesktopProvider)
        {
            Register(router, "get_menu_bar", "Read the app menu bar hierarchy.", NoArgs(), (_, cancellationToken) => runtime.GetMenuBar(cancellationToken));
            Register(router, "click_menu_item", "Invoke a menu item by title path.", ObjectSchema(["title_path"], ("title_path", new JsonObject { ["type"] = "string" })), (args, cancellationToken) => runtime.ClickMenuItem(args, cancellationToken));
        }

        Register(router, "focus_window", "Bring a specific window to the front and make it key.", ObjectSchema(["window_id"], ("window_id", new JsonObject { ["type"] = "string" })), (args, cancellationToken) => runtime.FocusWindow(args, cancellationToken));
        Register(router, "get_screen", "Get the currently active screen identity and metadata.", NoArgs(), (_, cancellationToken) => runtime.GetScreen(cancellationToken));
        Register(router, "get_elements", "List all visible interactive elements on the current screen.", ObjectSchema(("window_id", new JsonObject { ["type"] = "string" })), (args, cancellationToken) => runtime.GetElements(args, cancellationToken));
        Register(router, "get_view_tree", "Dump the view hierarchy with class, frame, properties, and accessibility info.", ObjectSchema(("window_id", new JsonObject { ["type"] = "string" }), ("max_depth", new JsonObject { ["type"] = "integer", ["minimum"] = 0, ["maximum"] = 200 })), (args, cancellationToken) => runtime.GetViewTree(args, cancellationToken));
        Register(router, "screenshot", "Capture the screen or a single element as a base64 image.", ObjectSchema(("window_id", new JsonObject { ["type"] = "string" }), ("element_id", new JsonObject { ["type"] = "string" }), ("format", new JsonObject { ["type"] = "string", ["enum"] = new JsonArray("png", "jpeg") })), runtime.Screenshot);

        if (runtime.HasInteractionProvider)
        {
            foreach (var tool in new[] { "tap_element", "tap_text", "tap_point", "type_text", "clear_text", "scroll", "scroll_to_element", "select_tab", "navigate_back", "dismiss_modal", "open_deeplink" })
            {
                Register(router, tool, $"Windows interaction tool `{tool}`.", new JsonObject { ["type"] = "object", ["properties"] = new JsonObject(), ["additionalProperties"] = true }, (args, cancellationToken) => runtime.Interaction(tool, args, cancellationToken));
            }
        }

        Register(router, "get_state", "App state snapshot.", NoArgs(), (_, cancellationToken) => runtime.GetState(cancellationToken));
        Register(router, "get_navigation_stack", "Current route, navigation stack, and presented modals.", NoArgs(), (_, cancellationToken) => runtime.GetNavigationStack(cancellationToken));
        Register(router, "get_feature_flags", "All active feature flags.", NoArgs(), (_, cancellationToken) => runtime.GetFeatureFlags(cancellationToken));
        Register(router, "get_network_calls", "Recent HTTP traffic captured by the app.", ObjectSchema(("limit", new JsonObject { ["type"] = "integer", ["minimum"] = 0, ["maximum"] = 500 })), (args, cancellationToken) => runtime.GetNetworkCalls(args, cancellationToken));
        Register(router, "get_logs", "Recent app log output.", ObjectSchema(("limit", new JsonObject { ["type"] = "integer", ["minimum"] = 0, ["maximum"] = 1000 }), ("subsystem", new JsonObject { ["type"] = "string" })), (args, cancellationToken) => runtime.GetLogs(args, cancellationToken));
        Register(router, "get_recent_errors", "Recent errors captured by the app.", NoArgs(), (_, cancellationToken) => runtime.GetRecentErrors(cancellationToken));
        Register(router, "launch_context", "App launch environment info.", NoArgs(), (_, _) => runtime.LaunchContext());
        Register(router, "device_info", "Comprehensive Windows device and app snapshot.", NoArgs(), (_, _) => runtime.DeviceInfo());

        if (runtime.HasWebViewProvider)
        {
            foreach (var tool in new[]
            {
                "get_webviews", "get_dom_tree", "get_dom_interactive", "query_dom", "find_dom_text",
                "web_click", "web_type", "web_select", "web_toggle", "web_scroll_to", "web_evaluate",
                "web_navigate", "web_back", "web_forward", "get_dom_summary", "get_dom_text",
                "get_dom_links", "get_dom_forms", "get_dom_headings", "get_dom_images", "get_dom_tables"
            })
            {
                Register(router, tool, $"Windows WebView tool `{tool}`.", new JsonObject { ["type"] = "object", ["properties"] = new JsonObject(), ["additionalProperties"] = true }, (args, cancellationToken) => runtime.WebView(tool, args, cancellationToken));
            }
        }

        Register(router, "batch", "Execute multiple tool calls in a single request.", new JsonObject
        {
            ["type"] = "object",
            ["properties"] = new JsonObject
            {
                ["actions"] = new JsonObject { ["type"] = "array" },
                ["stop_on_error"] = new JsonObject { ["type"] = "boolean" }
            },
            ["required"] = new JsonArray("actions")
        }, async (args, cancellationToken) =>
        {
            var actions = args?["actions"] as JsonArray ?? throw new McpInvalidParamsException("actions array required");
            var stopOnError = Json.ReadBool(args, "stop_on_error") ?? false;
            var results = new JsonArray();
            var actionCount = Math.Min(actions.Count, MaxBatchActions);

            for (var i = 0; i < actionCount; i++)
            {
                string? name = null;
                try
                {
                    if (actions[i] is not JsonObject action)
                    {
                        throw new McpInvalidParamsException("action must be an object");
                    }

                    name = Json.ReadString(action, "tool");
                    if (string.IsNullOrWhiteSpace(name))
                    {
                        throw new McpInvalidParamsException("tool is required");
                    }

                    if (string.Equals(name, "batch", StringComparison.Ordinal))
                    {
                        throw new McpInvalidParamsException("batch cannot call batch");
                    }

                    if (action.TryGetPropertyValue("arguments", out var argumentNode)
                        && argumentNode is not null
                        && argumentNode is not JsonObject)
                    {
                        throw new McpInvalidParamsException("arguments must be an object");
                    }

                    var delayMs = Clamp(Json.ReadInt(action, "delay_ms") ?? 0, 0, MaxBatchDelayMs);
                    if (delayMs > 0)
                    {
                        await Task.Delay(delayMs, cancellationToken);
                    }

                    var actionArgs = argumentNode as JsonObject;
                    var result = await router.CallToolAsync(name, actionArgs, cancellationToken);
                    results.Add(new JsonObject
                    {
                        ["index"] = i,
                        ["tool"] = name,
                        ["success"] = true,
                        ["result"] = result?.DeepClone()
                    });
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    results.Add(new JsonObject
                    {
                        ["index"] = i,
                        ["tool"] = name,
                        ["success"] = false,
                        ["error"] = BatchErrorCode(ex),
                        ["message"] = BatchErrorMessage(ex)
                    });
                    if (stopOnError)
                    {
                        break;
                    }
                }
            }

            return new JsonObject
            {
                ["results"] = results,
                ["truncated"] = actions.Count > MaxBatchActions,
                ["maxActions"] = MaxBatchActions
            };
        });
    }

    private static void Register(McpRouter router, string name, string description, JsonObject schema, Func<JsonObject?, CancellationToken, ValueTask<JsonNode>> handler)
    {
        router.Register(new McpTool(name, description, schema, handler));
    }

    private static void Register(McpRouter router, string name, string description, JsonObject schema, Func<JsonObject?, CancellationToken, JsonNode> handler)
    {
        router.Register(new McpTool(name, description, schema, (args, cancellationToken) => ValueTask.FromResult(handler(args, cancellationToken))));
    }

    private static string BatchErrorCode(Exception exception)
    {
        return exception switch
        {
            McpUnknownToolException => "unknown_tool",
            McpInvalidParamsException => "invalid_action",
            InvalidOperationException => "invalid_action",
            _ => "tool_error"
        };
    }

    private static string BatchErrorMessage(Exception exception)
    {
        return exception is McpUnknownToolException unknownTool
            ? $"Unknown tool: {unknownTool.ToolName}"
            : exception.Message;
    }

    private static int Clamp(int value, int min, int max)
    {
        if (value < min)
        {
            return min;
        }

        return value > max ? max : value;
    }
}
