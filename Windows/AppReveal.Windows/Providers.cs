using System.Globalization;
using System.Text.Json.Nodes;

namespace AppReveal.Windows;

public interface IAppRevealStateProvider
{
    object? Snapshot();
}

public interface IAppRevealNavigationProvider
{
    AppRevealNavigationSnapshot Snapshot();
}

public interface IAppRevealFeatureFlagProvider
{
    IReadOnlyDictionary<string, object?> AllFlags();
}

public interface IAppRevealLogProvider
{
    IReadOnlyList<AppRevealLogEntry> RecentLogs(int limit);
    IReadOnlyList<AppRevealErrorEntry> RecentErrors();
}

public interface IAppRevealNetworkProvider
{
    IReadOnlyList<AppRevealNetworkCall> RecentCalls(int limit);
}

public interface IAppRevealWindowProvider
{
    IReadOnlyList<AppRevealWindowInfo> ListWindows();
    AppRevealElementSnapshot? GetElements(string? windowId);
    object? GetViewTree(string? windowId, int? maxDepth);
    AppRevealScreenshot? CaptureScreenshot(string? windowId, string? elementId, string format);
    bool FocusWindow(string windowId);
}

public interface IAppRevealDesktopProvider
{
    object? GetMenuBar();
    bool ClickMenuItem(string titlePath);
}

public interface IAppRevealInteractionProvider
{
    ValueTask<JsonNode> InvokeAsync(string tool, JsonObject? args);
}

public interface IAppRevealWebViewProvider
{
    ValueTask<JsonNode> InvokeAsync(string tool, JsonObject? args);
}

public interface IDiscoveryAdvertiser
{
    void Start(DiscoveryAdvertisement advertisement);
    void Stop();
}

public sealed record DiscoveryAdvertisement(
    string Name,
    string ServiceType,
    int Port,
    IReadOnlyDictionary<string, string> Txt);

public sealed record AppRevealNavigationSnapshot(
    string CurrentRoute,
    IReadOnlyList<string> NavigationStack,
    IReadOnlyList<string> PresentedModals)
{
    public static AppRevealNavigationSnapshot Empty { get; } = new("", Array.Empty<string>(), Array.Empty<string>());
}

public sealed record AppRevealWindowInfo(
    string Id,
    string Title,
    AppRevealFrame Frame,
    bool IsKey)
{
    public AppRevealWindowInfo(string id, string title, string frame, bool isKey)
        : this(id, title, AppRevealFrame.Parse(frame), isKey)
    {
    }
}

public sealed record AppRevealElementSnapshot(
    string ScreenKey,
    IReadOnlyList<AppRevealElementInfo> Elements);

public sealed record AppRevealElementInfo(
    string Id,
    string Type,
    string? Label,
    string? Value,
    bool Enabled,
    bool Visible,
    bool Tappable,
    AppRevealFrame Frame,
    IReadOnlyList<string> Actions,
    string IdSource)
{
    public AppRevealElementInfo(
        string id,
        string type,
        string? label,
        string? value,
        bool enabled,
        bool visible,
        bool tappable,
        string frame,
        IReadOnlyList<string> actions,
        string idSource)
        : this(id, type, label, value, enabled, visible, tappable, AppRevealFrame.Parse(frame), actions, idSource)
    {
    }

    public AppRevealSafeAreaInsets SafeAreaInsets { get; init; } = AppRevealSafeAreaInsets.Zero;
    public AppRevealFrame SafeAreaLayoutGuideFrame { get; init; } = AppRevealFrame.Zero;
    public string? ContainerId { get; init; }
}

public sealed record AppRevealSafeAreaInsets(
    double Top,
    double Leading,
    double Bottom,
    double Trailing)
{
    public static AppRevealSafeAreaInsets Zero { get; } = new(0, 0, 0, 0);
}

public sealed record AppRevealFrame(
    double X,
    double Y,
    double Width,
    double Height)
{
    public static AppRevealFrame Zero { get; } = new(0, 0, 0, 0);

    public static AppRevealFrame Parse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return Zero;
        }

        var parts = value.Split(',', StringSplitOptions.TrimEntries);
        if (parts.Length != 4)
        {
            return Zero;
        }

        return double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var x)
            && double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var y)
            && double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out var width)
            && double.TryParse(parts[3], NumberStyles.Float, CultureInfo.InvariantCulture, out var height)
            ? new AppRevealFrame(x, y, width, height)
            : Zero;
    }
}

public sealed record AppRevealScreenshot(
    string Image,
    int Width,
    int Height,
    double Scale,
    string Format);

public sealed record AppRevealLogEntry(
    DateTimeOffset Timestamp,
    string Level,
    string Message,
    string? Subsystem = null);

public sealed record AppRevealErrorEntry(
    DateTimeOffset Timestamp,
    string Domain,
    string Message,
    string? StackTrace = null);

public sealed record AppRevealNetworkCall(
    string Id,
    string Method,
    string Url,
    int? StatusCode,
    long RequestTimestamp,
    long? ResponseTimestamp,
    IReadOnlyDictionary<string, string>? RequestHeaders = null,
    IReadOnlyDictionary<string, string>? ResponseHeaders = null,
    long? RequestBodySize = null,
    long? ResponseBodySize = null,
    string? Error = null);
