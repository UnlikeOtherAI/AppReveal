using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace AppReveal.Windows;

public static class AppReveal
{
    private static AppRevealSession? current;
    private static readonly object Gate = new();

    public static AppRevealSession? Current
    {
        get
        {
            lock (Gate)
            {
                return current;
            }
        }
    }

    public static AppRevealSession Start(AppRevealOptions? options = null)
    {
        lock (Gate)
        {
            current?.Stop();
            current = null;

            var next = new AppRevealSession(options ?? new AppRevealOptions());
            try
            {
                next.Start();
                current = next;
                return next;
            }
            catch
            {
                next.Dispose();
                throw;
            }
        }
    }

    public static void Stop()
    {
        lock (Gate)
        {
            current?.Stop();
            current = null;
        }
    }
}

public sealed class AppRevealSession : IDisposable
{
    private readonly AppRevealOptions options;
    private readonly McpRouter router;
    private readonly string sessionToken;
    private McpServer? server;

    internal AppRevealSession(AppRevealOptions options)
    {
        this.options = options;
        sessionToken = string.IsNullOrWhiteSpace(options.SessionToken)
            ? CreateSessionToken()
            : options.SessionToken.Trim();
        router = new McpRouter(options.ServerName, options.Version);
        BuiltInTools.Register(router, new AppRevealRuntime(options));
    }

    public int Port => server?.Port ?? 0;

    public string Url => server?.Url ?? "";

    public string SessionUrl => server?.SessionUrl ?? "";

    public string SessionToken => sessionToken;

    public IReadOnlyCollection<McpToolDefinition> Tools => router.Tools;

    public void Start()
    {
        if (server is not null)
        {
            return;
        }

        EnsureReleaseBuildAllowed();

        server = new McpServer(router, options.Port, sessionToken, options.AllowedCorsOrigins, options.AllowLoopbackCorsOrigins);
        try
        {
            server.Start();
            StartDiscoveryAdvertisement();
        }
        catch
        {
            Stop();
            throw;
        }
    }

    public void Stop()
    {
        options.DiscoveryAdvertiser?.Stop();
        server?.Stop();
        server = null;
    }

    public void Dispose()
    {
        Stop();
    }

    private void EnsureReleaseBuildAllowed()
    {
        if (options.IsHostReleaseBuild && !options.AllowReleaseBuild)
        {
            throw new InvalidOperationException("AppReveal.Windows starts a local diagnostics server. Starting it for a host app marked as Release requires AppRevealOptions.AllowReleaseBuild = true.");
        }
    }

    private void StartDiscoveryAdvertisement()
    {
        if (!options.EnableLoopbackDiscoveryAdvertisement || options.DiscoveryAdvertiser is null || server is null)
        {
            return;
        }

        options.DiscoveryAdvertiser.Start(new DiscoveryAdvertisement(
            options.DiscoveryName ?? $"AppReveal-{options.AppId}",
            "_appreveal._tcp",
            server.Port,
            new Dictionary<string, string>
            {
                ["bundleId"] = options.AppId,
                ["version"] = options.Version,
                ["transport"] = "streamable-http",
                ["platform"] = "Windows",
                ["host"] = "localhost",
                ["auth"] = "session-token"
            }));
    }

    private static string CreateSessionToken()
    {
        return Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
    }
}

public sealed class AppRevealOptions
{
    public const string IsHostReleaseBuildEnvironmentVariable = "APPREVEAL_HOST_RELEASE_BUILD";
    public const string AllowReleaseBuildEnvironmentVariable = "APPREVEAL_ALLOW_RELEASE_BUILD";

    public AppRevealOptions()
    {
        var nativeProvider = new CurrentProcessWindowProvider();
        WindowProvider = nativeProvider;
        DesktopProvider = nativeProvider;
        InteractionProvider = nativeProvider;
    }

    public string AppId { get; set; } = Assembly.GetEntryAssembly()?.GetName().Name ?? "windows.app";
    public string AppName { get; set; } = Assembly.GetEntryAssembly()?.GetName().Name ?? "Windows App";
    public string Version { get; set; } = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.0.0";
    public string Build { get; set; } = Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0";
    public string ServerName { get; set; } = "AppReveal";
    public string? DiscoveryName { get; set; }
    public int Port { get; set; }
    public string? SessionToken { get; set; }
    public IAppRevealStateProvider? StateProvider { get; set; }
    public IAppRevealNavigationProvider? NavigationProvider { get; set; }
    public IAppRevealFeatureFlagProvider? FeatureFlagProvider { get; set; }
    public IAppRevealLogProvider? LogProvider { get; set; }
    public IAppRevealNetworkProvider? NetworkProvider { get; set; }
    public IAppRevealWindowProvider WindowProvider { get; set; }
    public IAppRevealDesktopProvider? DesktopProvider { get; set; }
    public IAppRevealInteractionProvider? InteractionProvider { get; set; }
    public IAppRevealWebViewProvider? WebViewProvider { get; set; }
    public IDiscoveryAdvertiser? DiscoveryAdvertiser { get; set; }
    public SynchronizationContext? ProviderSynchronizationContext { get; set; }
    public Func<Func<CancellationToken, ValueTask<JsonNode>>, CancellationToken, ValueTask<JsonNode>>? ProviderInvokeAsync { get; set; }
    public bool IsHostReleaseBuild { get; set; } = ReadEnvironmentFlag(IsHostReleaseBuildEnvironmentVariable);
    public bool AllowReleaseBuild { get; set; } = ReadEnvironmentFlag(AllowReleaseBuildEnvironmentVariable);
    public bool EnableLoopbackDiscoveryAdvertisement { get; set; }
    public bool AllowLoopbackCorsOrigins { get; set; } = true;
    public ISet<string> AllowedCorsOrigins { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    private static bool ReadEnvironmentFlag(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "yes", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "on", StringComparison.OrdinalIgnoreCase);
    }
}

internal sealed class AppRevealRuntime
{
    private const int DefaultLogLimit = 100;
    private const int MaxLogLimit = 1000;
    private const int DefaultNetworkLimit = 50;
    private const int MaxNetworkLimit = 500;
    private const int DefaultViewTreeDepth = 50;
    private const int MaxViewTreeDepth = 200;
    private const string RedactedHeaderValue = "[REDACTED]";

    private static readonly HashSet<string> SensitiveHeaders = new(StringComparer.OrdinalIgnoreCase)
    {
        "authorization",
        "cookie",
        "set-cookie",
        "proxy-authorization",
        "x-api-key",
        "api-key",
        "x-auth-token",
        "x-csrf-token",
        "x-xsrf-token"
    };

    private readonly AppRevealOptions options;

    public AppRevealRuntime(AppRevealOptions options)
    {
        this.options = options;
    }

    public bool HasDesktopProvider => options.DesktopProvider is not null;

    public bool HasInteractionProvider => options.InteractionProvider is not null;

    public bool HasWebViewProvider => options.WebViewProvider is not null;

    public JsonNode LaunchContext()
    {
        return Json.ToNode(new Dictionary<string, object?>
        {
            ["bundleId"] = options.AppId,
            ["appName"] = options.AppName,
            ["displayName"] = options.AppName,
            ["version"] = options.Version,
            ["build"] = options.Build,
            ["platform"] = "Windows",
            ["frameworkType"] = "windows-native",
            ["systemName"] = "Windows",
            ["systemVersion"] = Environment.OSVersion.VersionString,
            ["deviceModel"] = Environment.MachineName,
            ["deviceName"] = Environment.MachineName,
            ["processName"] = Process.GetCurrentProcess().ProcessName,
            ["processId"] = Environment.ProcessId
        });
    }

    public JsonNode DeviceInfo()
    {
        var process = Process.GetCurrentProcess();
        return Json.ToNode(new Dictionary<string, object?>
        {
            ["platform"] = "Windows",
            ["frameworkType"] = "windows-native",
            ["bundleId"] = options.AppId,
            ["appName"] = options.AppName,
            ["displayName"] = options.AppName,
            ["version"] = options.Version,
            ["build"] = options.Build,
            ["executableName"] = process.MainModule?.ModuleName,
            ["deviceName"] = Environment.MachineName,
            ["systemName"] = "Windows",
            ["systemVersion"] = Environment.OSVersion.VersionString,
            ["osVersion"] = new Dictionary<string, object?>
            {
                ["major"] = Environment.OSVersion.Version.Major,
                ["minor"] = Environment.OSVersion.Version.Minor,
                ["patch"] = Environment.OSVersion.Version.Build
            },
            ["processName"] = process.ProcessName,
            ["processId"] = Environment.ProcessId,
            ["processorCount"] = Environment.ProcessorCount,
            ["physicalMemoryMB"] = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes / 1024 / 1024,
            ["currentDirectory"] = Environment.CurrentDirectory,
            ["userName"] = Environment.UserName,
            ["machineName"] = Environment.MachineName,
            ["is64BitProcess"] = Environment.Is64BitProcess,
            ["is64BitOperatingSystem"] = Environment.Is64BitOperatingSystem
        });
    }

    public ValueTask<JsonNode> GetState(CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () => Json.ToNode(options.StateProvider?.Snapshot() ?? new Dictionary<string, object?>()),
            cancellationToken);
    }

    public ValueTask<JsonNode> GetNavigationStack(CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () => Json.ToNode(options.NavigationProvider?.Snapshot() ?? AppRevealNavigationSnapshot.Empty),
            cancellationToken);
    }

    public ValueTask<JsonNode> GetFeatureFlags(CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () => Json.ToNode(options.FeatureFlagProvider?.AllFlags() ?? new Dictionary<string, object?>()),
            cancellationToken);
    }

    public ValueTask<JsonNode> GetLogs(JsonObject? args, CancellationToken cancellationToken)
    {
        var limit = Clamp(Json.ReadInt(args, "limit") ?? DefaultLogLimit, 0, MaxLogLimit);
        return InvokeProviderAsync(
            () => Json.ToNode(new Dictionary<string, object?>
            {
                ["logs"] = options.LogProvider?.RecentLogs(limit) ?? Array.Empty<AppRevealLogEntry>()
            }),
            cancellationToken);
    }

    public ValueTask<JsonNode> GetNetworkCalls(JsonObject? args, CancellationToken cancellationToken)
    {
        var limit = Clamp(Json.ReadInt(args, "limit") ?? DefaultNetworkLimit, 0, MaxNetworkLimit);
        return InvokeProviderAsync(
            () =>
            {
                var calls = options.NetworkProvider?.RecentCalls(limit) ?? Array.Empty<AppRevealNetworkCall>();
                return Json.ToNode(new Dictionary<string, object?>
                {
                    ["calls"] = RedactNetworkCalls(calls)
                });
            },
            cancellationToken);
    }

    public ValueTask<JsonNode> GetRecentErrors(CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () => Json.ToNode(new Dictionary<string, object?>
            {
                ["errors"] = options.LogProvider?.RecentErrors() ?? Array.Empty<AppRevealErrorEntry>()
            }),
            cancellationToken);
    }

    public ValueTask<JsonNode> ListWindows(CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () => Json.ToNode(new Dictionary<string, object?>
            {
                ["windows"] = options.WindowProvider.ListWindows()
            }),
            cancellationToken);
    }

    public ValueTask<JsonNode> GetMenuBar(CancellationToken cancellationToken)
    {
        if (options.DesktopProvider is null)
        {
            return ValueTask.FromResult(ProviderUnavailable("get_menu_bar", "No Windows desktop provider is registered."));
        }

        return InvokeProviderAsync(
            () =>
            {
                var menuBar = options.DesktopProvider.GetMenuBar();
                return menuBar is not null ? Json.ToNode(menuBar) : ProviderUnavailable(
                    "get_menu_bar",
                    "No Windows menu bar is available for the selected window.");
            },
            cancellationToken);
    }

    public ValueTask<JsonNode> ClickMenuItem(JsonObject? args, CancellationToken cancellationToken)
    {
        var titlePath = Json.ReadString(args, "title_path");
        if (string.IsNullOrWhiteSpace(titlePath))
        {
            return ValueTask.FromResult(Json.ToNode(new Dictionary<string, object?>
            {
                ["success"] = false,
                ["error"] = "missing_argument",
                ["message"] = "title_path is required"
            }));
        }

        if (options.DesktopProvider is null)
        {
            return ValueTask.FromResult(ProviderUnavailable("click_menu_item", "No Windows desktop provider is registered."));
        }

        return InvokeProviderAsync(
            () => Json.ToNode(new Dictionary<string, object?>
            {
                ["success"] = options.DesktopProvider.ClickMenuItem(titlePath)
            }),
            cancellationToken);
    }

    public ValueTask<JsonNode> FocusWindow(JsonObject? args, CancellationToken cancellationToken)
    {
        var windowId = Json.ReadString(args, "window_id");
        if (string.IsNullOrWhiteSpace(windowId))
        {
            return ValueTask.FromResult(Json.ToNode(new Dictionary<string, object?>
            {
                ["success"] = false,
                ["error"] = "missing_argument",
                ["message"] = "window_id is required"
            }));
        }

        return InvokeProviderAsync(
            () => Json.ToNode(new Dictionary<string, object?>
            {
                ["success"] = options.WindowProvider.FocusWindow(windowId)
            }),
            cancellationToken);
    }

    public ValueTask<JsonNode> GetScreen(CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () =>
            {
                var navigation = options.NavigationProvider?.Snapshot();
                return Json.ToNode(new Dictionary<string, object?>
                {
                    ["screenKey"] = navigation?.CurrentRoute ?? "windows.unknown",
                    ["screenTitle"] = navigation?.CurrentRoute ?? options.AppName,
                    ["frameworkType"] = "windows-native",
                    ["controllerChain"] = Array.Empty<string>(),
                    ["activeTab"] = null,
                    ["navigationDepth"] = navigation?.NavigationStack.Count ?? 0,
                    ["presentedModals"] = navigation?.PresentedModals ?? Array.Empty<string>(),
                    ["confidence"] = navigation is null ? 0.25 : 1.0,
                    ["source"] = navigation is null ? "derived" : "explicit",
                    ["appBarTitle"] = navigation?.CurrentRoute ?? options.AppName
                });
            },
            cancellationToken);
    }

    public ValueTask<JsonNode> GetElements(JsonObject? args, CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(
            () =>
            {
                var elements = options.WindowProvider.GetElements(Json.ReadString(args, "window_id"));
                return elements is not null ? Json.ToNode(elements) : ProviderUnavailable(
                    "get_elements",
                    "No UI Automation element inventory is available for the selected window.");
            },
            cancellationToken);
    }

    public ValueTask<JsonNode> GetViewTree(JsonObject? args, CancellationToken cancellationToken)
    {
        var maxDepth = Clamp(Json.ReadInt(args, "max_depth") ?? DefaultViewTreeDepth, 0, MaxViewTreeDepth);
        return InvokeProviderAsync(
            () =>
            {
                var tree = options.WindowProvider.GetViewTree(Json.ReadString(args, "window_id"), maxDepth);
                return tree is not null ? Json.ToNode(tree) : ProviderUnavailable(
                    "get_view_tree",
                    "No UI Automation view tree is available for the selected window.");
            },
            cancellationToken);
    }

    public ValueTask<JsonNode> Screenshot(JsonObject? args, CancellationToken cancellationToken)
    {
        var format = Json.ReadString(args, "format")?.Trim().ToLowerInvariant() ?? "png";
        if (format is not "png" and not "jpeg")
        {
            return ValueTask.FromResult(Json.ToNode(new Dictionary<string, object?>
            {
                ["success"] = false,
                ["error"] = "invalid_argument",
                ["message"] = "format must be png or jpeg"
            }));
        }

        return InvokeProviderAsync(
            () =>
            {
                var result = options.WindowProvider.CaptureScreenshot(
                    Json.ReadString(args, "window_id"),
                    Json.ReadString(args, "element_id"),
                    format);
                return result is not null
                    ? Json.ToNode(result)
                    : ProviderUnavailable("screenshot", "No screenshot target is available for the selected window or element.");
            },
            cancellationToken);
    }

    public ValueTask<JsonNode> Interaction(string tool, JsonObject? args, CancellationToken cancellationToken)
    {
        if (options.InteractionProvider is null)
        {
            return ValueTask.FromResult(ProviderUnavailable(tool, "No Windows interaction provider is registered."));
        }

        return InvokeProviderAsync(_ => options.InteractionProvider.InvokeAsync(tool, args), cancellationToken);
    }

    public ValueTask<JsonNode> WebView(string tool, JsonObject? args, CancellationToken cancellationToken)
    {
        if (options.WebViewProvider is null)
        {
            return ValueTask.FromResult(ProviderUnavailable(tool, "No Windows WebView provider is registered."));
        }

        return InvokeProviderAsync(_ => options.WebViewProvider.InvokeAsync(tool, args), cancellationToken);
    }

    private ValueTask<JsonNode> InvokeProviderAsync(Func<JsonNode> callback, CancellationToken cancellationToken)
    {
        return InvokeProviderAsync(_ => ValueTask.FromResult(callback()), cancellationToken);
    }

    private ValueTask<JsonNode> InvokeProviderAsync(Func<CancellationToken, ValueTask<JsonNode>> callback, CancellationToken cancellationToken)
    {
        if (options.ProviderInvokeAsync is not null)
        {
            return options.ProviderInvokeAsync(callback, cancellationToken);
        }

        if (options.ProviderSynchronizationContext is { } context && !ReferenceEquals(SynchronizationContext.Current, context))
        {
            return InvokeOnSynchronizationContextAsync(context, callback, cancellationToken);
        }

        return callback(cancellationToken);
    }

    private static ValueTask<JsonNode> InvokeOnSynchronizationContextAsync(
        SynchronizationContext context,
        Func<CancellationToken, ValueTask<JsonNode>> callback,
        CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested)
        {
            return ValueTask.FromCanceled<JsonNode>(cancellationToken);
        }

        var completion = new TaskCompletionSource<JsonNode>(TaskCreationOptions.RunContinuationsAsynchronously);
        CancellationTokenRegistration? registration = null;
        if (cancellationToken.CanBeCanceled)
        {
            registration = cancellationToken.Register(() => completion.TrySetCanceled(cancellationToken));
        }

        try
        {
            context.Post(async _ =>
            {
                try
                {
                    if (cancellationToken.IsCancellationRequested)
                    {
                        completion.TrySetCanceled(cancellationToken);
                        return;
                    }

                    var result = await callback(cancellationToken);
                    completion.TrySetResult(result);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    completion.TrySetCanceled(cancellationToken);
                }
                catch (Exception ex)
                {
                    completion.TrySetException(ex);
                }
                finally
                {
                    registration?.Dispose();
                }
            }, null);
        }
        catch (Exception ex)
        {
            registration?.Dispose();
            completion.TrySetException(ex);
        }

        return new ValueTask<JsonNode>(completion.Task);
    }

    public static JsonNode ProviderUnavailable(string tool, string message)
    {
        return Json.ToNode(new Dictionary<string, object?>
        {
            ["success"] = false,
            ["error"] = "provider_unavailable",
            ["tool"] = tool,
            ["message"] = message
        });
    }

    private static IReadOnlyList<AppRevealNetworkCall> RedactNetworkCalls(IReadOnlyList<AppRevealNetworkCall> calls)
    {
        if (calls.Count == 0)
        {
            return Array.Empty<AppRevealNetworkCall>();
        }

        return calls.Select(call => call with
        {
            RequestHeaders = RedactHeaders(call.RequestHeaders),
            ResponseHeaders = RedactHeaders(call.ResponseHeaders)
        }).ToArray();
    }

    private static IReadOnlyDictionary<string, string>? RedactHeaders(IReadOnlyDictionary<string, string>? headers)
    {
        if (headers is null)
        {
            return null;
        }

        var redacted = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (name, value) in headers)
        {
            redacted[name] = IsSensitiveHeader(name) ? RedactedHeaderValue : value;
        }

        return redacted;
    }

    private static bool IsSensitiveHeader(string name)
    {
        if (SensitiveHeaders.Contains(name))
        {
            return true;
        }

        return name.Contains("token", StringComparison.OrdinalIgnoreCase)
            || name.Contains("secret", StringComparison.OrdinalIgnoreCase)
            || name.Contains("session", StringComparison.OrdinalIgnoreCase)
            || name.EndsWith("-key", StringComparison.OrdinalIgnoreCase);
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
