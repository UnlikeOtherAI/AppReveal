using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using UiElement = FlaUI.Core.AutomationElements.AutomationElement;

namespace AppReveal.Windows;

public sealed class CurrentProcessWindowProvider :
    IAppRevealWindowProvider,
    IAppRevealDesktopProvider,
    IAppRevealInteractionProvider
{
    private const int MaxElementCount = 500;
    private const int MaxTreeNodes = 1000;
    private const int DefaultTreeDepth = 50;

    public IReadOnlyList<AppRevealWindowInfo> ListWindows()
    {
        if (!OperatingSystem.IsWindows())
        {
            return Array.Empty<AppRevealWindowInfo>();
        }

        var currentPid = (uint)Environment.ProcessId;
        var windows = new List<AppRevealWindowInfo>();

        NativeMethods.EnumWindows((handle, _) =>
        {
            NativeMethods.GetWindowThreadProcessId(handle, out var pid);
            if (pid != currentPid || !NativeMethods.IsWindowVisible(handle))
            {
                return true;
            }

            var title = GetWindowTitle(handle);
            if (string.IsNullOrWhiteSpace(title))
            {
                title = Process.GetCurrentProcess().ProcessName;
            }

            if (!NativeMethods.GetWindowRect(handle, out var rect))
            {
                rect = default;
            }

            windows.Add(new AppRevealWindowInfo(
                WindowId(handle),
                title,
                new AppRevealFrame(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top),
                handle == NativeMethods.GetForegroundWindow()));
            return true;
        }, IntPtr.Zero);

        return windows;
    }

    public AppRevealElementSnapshot? GetElements(string? windowId)
    {
        return WithRoot(windowId, root =>
        {
            var elements = new List<AppRevealElementInfo>();
            foreach (var item in EnumerateDescendants(root, includeRoot: true).Take(MaxElementCount))
            {
                elements.Add(ToElementInfo(item.Element, item.Index));
            }

            return new AppRevealElementSnapshot(ScreenKey(root), elements);
        });
    }

    public object? GetViewTree(string? windowId, int? maxDepth)
    {
        var depth = Math.Clamp(maxDepth ?? DefaultTreeDepth, 0, DefaultTreeDepth);
        return WithRoot(windowId, root =>
        {
            var remaining = MaxTreeNodes;
            return ToTreeNode(root, depth, 0, ref remaining);
        });
    }

    public AppRevealScreenshot? CaptureScreenshot(string? windowId, string? elementId, string format)
    {
        return WithRoot(windowId, root =>
        {
            var target = string.IsNullOrWhiteSpace(elementId)
                ? root
                : FindElementById(root, elementId!);
            if (target is null)
            {
                return null;
            }

            using var bitmap = target.Capture();
            using var stream = new MemoryStream();
            var imageFormat = string.Equals(format, "jpeg", StringComparison.OrdinalIgnoreCase)
                ? ImageFormat.Jpeg
                : ImageFormat.Png;
            bitmap.Save(stream, imageFormat);
            return new AppRevealScreenshot(
                Convert.ToBase64String(stream.ToArray()),
                bitmap.Width,
                bitmap.Height,
                1,
                string.Equals(format, "jpeg", StringComparison.OrdinalIgnoreCase) ? "jpeg" : "png");
        });
    }

    public bool FocusWindow(string windowId)
    {
        if (!OperatingSystem.IsWindows() || !TryResolveWindowHandle(windowId, out var handle))
        {
            return false;
        }

        return NativeMethods.SetForegroundWindow(handle);
    }

    public object? GetMenuBar()
    {
        return WithRoot(null, root =>
        {
            var menuRoots = EnumerateDescendants(root, includeRoot: true)
                .Where(item => IsMenuContainer(item.Element))
                .Take(25)
                .Select(item => MenuNode(item.Element, item.Index, 0))
                .ToArray();

            return new Dictionary<string, object?>
            {
                ["menus"] = menuRoots,
                ["count"] = menuRoots.Length
            };
        });
    }

    public bool ClickMenuItem(string titlePath)
    {
        if (string.IsNullOrWhiteSpace(titlePath))
        {
            return false;
        }

        var parts = titlePath
            .Split(['>', '/', '\\'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(part => !string.IsNullOrWhiteSpace(part))
            .ToArray();
        if (parts.Length == 0)
        {
            return false;
        }

        return WithRoot(null, root =>
        {
            UiElement? currentScope = root;
            foreach (var part in parts)
            {
                var next = EnumerateDescendants(currentScope, includeRoot: false)
                    .Select(item => item.Element)
                    .FirstOrDefault(element => IsMenuElement(element) && string.Equals(SafeName(element), part, StringComparison.OrdinalIgnoreCase));
                if (next is null)
                {
                    return false;
                }

                ClickOrInvoke(next);
                currentScope = next;
                Thread.Sleep(75);
            }

            return true;
        });
    }

    public ValueTask<JsonNode> InvokeAsync(string tool, JsonObject? args)
    {
        var result = tool switch
        {
            "tap_element" => TapElement(args),
            "tap_text" => TapText(args),
            "tap_point" => TapPoint(args),
            "type_text" => TypeText(args),
            "clear_text" => ClearText(args),
            "scroll" => Scroll(args),
            "scroll_to_element" => ScrollToElement(args),
            "select_tab" => SelectTab(args),
            "navigate_back" => NavigateBack(),
            "dismiss_modal" => DismissModal(),
            "open_deeplink" => OpenDeeplink(args),
            _ => ToolFailure(tool, "unknown_tool", $"Unknown Windows interaction tool: {tool}")
        };

        return ValueTask.FromResult(result);
    }

    private JsonNode TapElement(JsonObject? args)
    {
        var elementId = Json.ReadString(args, "element_id");
        if (string.IsNullOrWhiteSpace(elementId))
        {
            return ToolFailure("tap_element", "missing_argument", "element_id is required");
        }

        return WithRoot(Json.ReadString(args, "window_id"), root =>
        {
            var element = FindElementById(root, elementId);
            if (element is null)
            {
                return ToolFailure("tap_element", "not_found", $"No element found with id '{elementId}'.");
            }

            return ClickOrInvoke(element)
                ? ToolSuccess("tap_element", ("element_id", elementId))
                : ToolFailure("tap_element", "action_failed", $"Element '{elementId}' could not be invoked or clicked.");
        }) ?? ToolFailure("tap_element", "provider_unavailable", "No active window is available.");
    }

    private JsonNode TapText(JsonObject? args)
    {
        var text = Json.ReadString(args, "text");
        if (string.IsNullOrWhiteSpace(text))
        {
            return ToolFailure("tap_text", "missing_argument", "text is required");
        }

        var mode = Json.ReadString(args, "match_mode") ?? "exact";
        var occurrence = Math.Max(0, Json.ReadInt(args, "occurrence") ?? 0);
        return WithRoot(Json.ReadString(args, "window_id"), root =>
        {
            var matches = EnumerateDescendants(root, includeRoot: true)
                .Select(item => item.Element)
                .Where(element => TextMatches(element, text, mode))
                .ToArray();
            var element = matches.Skip(occurrence).FirstOrDefault();
            if (element is null)
            {
                return ToolFailure("tap_text", "not_found", $"No visible element matched '{text}'.");
            }

            return ClickOrInvoke(element)
                ? ToolSuccess("tap_text", ("text", text), ("match_count", matches.Length))
                : ToolFailure("tap_text", "action_failed", $"Matched text '{text}' but could not click it.");
        }) ?? ToolFailure("tap_text", "provider_unavailable", "No active window is available.");
    }

    private static JsonNode TapPoint(JsonObject? args)
    {
        var x = Json.ReadDouble(args, "x");
        var y = Json.ReadDouble(args, "y");
        if (x is null || y is null)
        {
            return ToolFailure("tap_point", "missing_argument", "x and y are required");
        }

        Mouse.LeftClick(new Point((int)Math.Round(x.Value), (int)Math.Round(y.Value)));
        return ToolSuccess("tap_point", ("x", x.Value), ("y", y.Value));
    }

    private JsonNode TypeText(JsonObject? args)
    {
        var text = Json.ReadString(args, "text");
        if (text is null)
        {
            return ToolFailure("type_text", "missing_argument", "text is required");
        }

        var elementId = Json.ReadString(args, "element_id");
        if (!string.IsNullOrWhiteSpace(elementId))
        {
            return WithRoot(Json.ReadString(args, "window_id"), root =>
            {
                var element = FindElementById(root, elementId!);
                if (element is null)
                {
                    return ToolFailure("type_text", "not_found", $"No element found with id '{elementId}'.");
                }

                if (SetElementValue(element, text))
                {
                    return ToolSuccess("type_text", ("element_id", elementId), ("text", text));
                }

                ClickOrInvoke(element);
                Keyboard.Type(text);
                return ToolSuccess("type_text", ("element_id", elementId), ("text", text));
            }) ?? ToolFailure("type_text", "provider_unavailable", "No active window is available.");
        }

        Keyboard.Type(text);
        return ToolSuccess("type_text", ("text", text));
    }

    private JsonNode ClearText(JsonObject? args)
    {
        var elementId = Json.ReadString(args, "element_id");
        if (!string.IsNullOrWhiteSpace(elementId))
        {
            return WithRoot(Json.ReadString(args, "window_id"), root =>
            {
                var element = FindElementById(root, elementId!);
                if (element is null)
                {
                    return ToolFailure("clear_text", "not_found", $"No element found with id '{elementId}'.");
                }

                if (!SetElementValue(element, string.Empty))
                {
                    ClickOrInvoke(element);
                    Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_A);
                    Keyboard.Press(VirtualKeyShort.DELETE);
                }

                return ToolSuccess("clear_text", ("element_id", elementId));
            }) ?? ToolFailure("clear_text", "provider_unavailable", "No active window is available.");
        }

        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_A);
        Keyboard.Press(VirtualKeyShort.DELETE);
        return ToolSuccess("clear_text");
    }

    private static JsonNode Scroll(JsonObject? args)
    {
        var direction = Json.ReadString(args, "direction")?.Trim().ToLowerInvariant() ?? "down";
        var amount = Math.Max(1, Json.ReadInt(args, "amount") ?? 5);
        switch (direction)
        {
            case "up":
                Mouse.Scroll(amount);
                break;
            case "down":
                Mouse.Scroll(-amount);
                break;
            case "left":
                Mouse.HorizontalScroll(-amount);
                break;
            case "right":
                Mouse.HorizontalScroll(amount);
                break;
            default:
                return ToolFailure("scroll", "invalid_argument", "direction must be up, down, left, or right");
        }

        return ToolSuccess("scroll", ("direction", direction), ("amount", amount));
    }

    private JsonNode ScrollToElement(JsonObject? args)
    {
        var elementId = Json.ReadString(args, "element_id");
        if (string.IsNullOrWhiteSpace(elementId))
        {
            return ToolFailure("scroll_to_element", "missing_argument", "element_id is required");
        }

        return WithRoot(Json.ReadString(args, "window_id"), root =>
        {
            var element = FindElementById(root, elementId);
            if (element is null)
            {
                return ToolFailure("scroll_to_element", "not_found", $"No element found with id '{elementId}'.");
            }

            TryScrollIntoView(element);
            return ToolSuccess("scroll_to_element", ("element_id", elementId));
        }) ?? ToolFailure("scroll_to_element", "provider_unavailable", "No active window is available.");
    }

    private JsonNode SelectTab(JsonObject? args)
    {
        var index = Json.ReadInt(args, "index");
        if (index is null || index.Value < 0)
        {
            return ToolFailure("select_tab", "missing_argument", "index is required and must be >= 0");
        }

        return WithRoot(Json.ReadString(args, "window_id"), root =>
        {
            var tabs = EnumerateDescendants(root, includeRoot: true)
                .Select(item => item.Element)
                .Where(element => SafeControlType(element) == ControlType.TabItem)
                .ToArray();
            var tab = tabs.Skip(index.Value).FirstOrDefault();
            if (tab is null)
            {
                return ToolFailure("select_tab", "not_found", $"No tab exists at index {index.Value}.");
            }

            return ClickOrInvoke(tab)
                ? ToolSuccess("select_tab", ("index", index.Value))
                : ToolFailure("select_tab", "action_failed", $"Tab at index {index.Value} could not be selected.");
        }) ?? ToolFailure("select_tab", "provider_unavailable", "No active window is available.");
    }

    private static JsonNode NavigateBack()
    {
        Keyboard.TypeSimultaneously(VirtualKeyShort.ALT, VirtualKeyShort.LEFT);
        return ToolSuccess("navigate_back");
    }

    private static JsonNode DismissModal()
    {
        Keyboard.Press(VirtualKeyShort.ESCAPE);
        return ToolSuccess("dismiss_modal");
    }

    private static JsonNode OpenDeeplink(JsonObject? args)
    {
        var url = Json.ReadString(args, "url");
        if (string.IsNullOrWhiteSpace(url) || !Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            return ToolFailure("open_deeplink", "invalid_argument", "url must be an absolute URI");
        }

        Process.Start(new ProcessStartInfo(uri.ToString()) { UseShellExecute = true });
        return ToolSuccess("open_deeplink", ("url", uri.ToString()));
    }

    private static bool ClickOrInvoke(UiElement element)
    {
        try
        {
            var invoke = element.Patterns.Invoke.PatternOrDefault;
            if (invoke is not null)
            {
                invoke.Invoke();
                return true;
            }
        }
        catch
        {
        }

        try
        {
            element.Click(moveMouse: true);
            return true;
        }
        catch
        {
        }

        try
        {
            if (element.TryGetClickablePoint(out var point))
            {
                Mouse.LeftClick(point);
                return true;
            }
        }
        catch
        {
        }

        return false;
    }

    private static bool SetElementValue(UiElement element, string value)
    {
        try
        {
            var pattern = element.Patterns.Value.PatternOrDefault;
            if (pattern is null || pattern.IsReadOnly)
            {
                return false;
            }

            pattern.SetValue(value);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string? ElementValue(UiElement element)
    {
        try
        {
            return element.Patterns.Value.PatternOrDefault?.Value;
        }
        catch
        {
            return null;
        }
    }

    private static void TryScrollIntoView(UiElement element)
    {
        try
        {
            element.Patterns.ScrollItem.PatternOrDefault?.ScrollIntoView();
        }
        catch
        {
        }
    }

    private T? WithRoot<T>(string? windowId, Func<UiElement, T?> callback)
    {
        if (!OperatingSystem.IsWindows() || !TryResolveWindowHandle(windowId, out var handle))
        {
            return default;
        }

        using var automation = new UIA3Automation();
        var root = automation.FromHandle(handle);
        return callback(root);
    }

    private static IEnumerable<(UiElement Element, int Index)> EnumerateDescendants(UiElement root, bool includeRoot)
    {
        var index = 0;
        if (includeRoot)
        {
            yield return (root, index++);
        }

        UiElement[] descendants;
        try
        {
            descendants = root.FindAllDescendants();
        }
        catch
        {
            yield break;
        }

        foreach (var descendant in descendants)
        {
            yield return (descendant, index++);
        }
    }

    private static UiElement? FindElementById(UiElement root, string elementId)
    {
        foreach (var item in EnumerateDescendants(root, includeRoot: true))
        {
            if (string.Equals(ElementId(item.Element, item.Index), elementId, StringComparison.Ordinal))
            {
                return item.Element;
            }
        }

        return null;
    }

    private static AppRevealElementInfo ToElementInfo(UiElement element, int index)
    {
        var controlType = SafeControlType(element);
        var frame = Frame(element);
        var visible = !SafeIsOffscreen(element) && frame.Width > 0 && frame.Height > 0;
        var enabled = SafeIsEnabled(element);
        var tappable = visible && enabled && IsTappable(element, controlType);
        var actions = ActionsFor(controlType, tappable);

        return new AppRevealElementInfo(
            ElementId(element, index),
            ToElementType(controlType),
            SafeName(element),
            ElementValue(element),
            enabled,
            visible,
            tappable,
            frame,
            actions,
            string.IsNullOrWhiteSpace(SafeAutomationId(element)) ? "derived" : "accessibility");
    }

    private static Dictionary<string, object?> ToTreeNode(UiElement element, int maxDepth, int depth, ref int remaining)
    {
        remaining--;
        var controlType = SafeControlType(element);
        var node = new Dictionary<string, object?>
        {
            ["id"] = ElementId(element, remaining),
            ["className"] = SafeClassName(element),
            ["type"] = ToElementType(controlType),
            ["controlType"] = controlType.ToString(),
            ["name"] = SafeName(element),
            ["automationId"] = SafeAutomationId(element),
            ["enabled"] = SafeIsEnabled(element),
            ["visible"] = !SafeIsOffscreen(element),
            ["frame"] = Frame(element),
            ["depth"] = depth
        };

        if (remaining <= 0 || depth >= maxDepth)
        {
            node["children"] = Array.Empty<object>();
            return node;
        }

        UiElement[] children;
        try
        {
            children = element.FindAllChildren();
        }
        catch
        {
            children = Array.Empty<UiElement>();
        }

        var childNodes = new List<object?>();
        foreach (var child in children)
        {
            if (remaining <= 0)
            {
                break;
            }

            childNodes.Add(ToTreeNode(child, maxDepth, depth + 1, ref remaining));
        }

        node["children"] = childNodes;
        return node;
    }

    private static Dictionary<string, object?> MenuNode(UiElement element, int index, int depth)
    {
        var children = Array.Empty<object?>();
        if (depth < 4)
        {
            try
            {
                children = element.FindAllChildren()
                    .Where(IsMenuElement)
                    .Select((child, childIndex) => MenuNode(child, childIndex, depth + 1))
                    .Cast<object?>()
                    .ToArray();
            }
            catch
            {
            }
        }

        return new Dictionary<string, object?>
        {
            ["id"] = ElementId(element, index),
            ["title"] = SafeName(element),
            ["type"] = ToElementType(SafeControlType(element)),
            ["enabled"] = SafeIsEnabled(element),
            ["children"] = children
        };
    }

    private bool TryResolveWindowHandle(string? windowId, out IntPtr handle)
    {
        handle = IntPtr.Zero;
        if (!string.IsNullOrWhiteSpace(windowId))
        {
            return TryParseWindowId(windowId, out handle) && IsCurrentProcessWindow(handle);
        }

        var foreground = NativeMethods.GetForegroundWindow();
        if (foreground != IntPtr.Zero && IsCurrentProcessWindow(foreground))
        {
            handle = foreground;
            return true;
        }

        var first = ListWindows().FirstOrDefault();
        if (first is null)
        {
            return false;
        }

        return TryParseWindowId(first.Id, out handle);
    }

    private static bool IsCurrentProcessWindow(IntPtr handle)
    {
        NativeMethods.GetWindowThreadProcessId(handle, out var pid);
        return pid == (uint)Environment.ProcessId && NativeMethods.IsWindowVisible(handle);
    }

    private static bool TextMatches(UiElement element, string expected, string mode)
    {
        if (SafeIsOffscreen(element))
        {
            return false;
        }

        var candidates = new[] { SafeName(element), ElementValue(element), SafeAutomationId(element) }
            .Where(value => !string.IsNullOrWhiteSpace(value));
        return string.Equals(mode, "contains", StringComparison.OrdinalIgnoreCase)
            ? candidates.Any(value => value!.Contains(expected, StringComparison.OrdinalIgnoreCase))
            : candidates.Any(value => string.Equals(value, expected, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsTappable(UiElement element, ControlType controlType)
    {
        if (controlType is ControlType.Button or ControlType.CheckBox or ControlType.ComboBox
            or ControlType.Hyperlink or ControlType.ListItem or ControlType.MenuItem
            or ControlType.RadioButton or ControlType.SplitButton or ControlType.TabItem
            or ControlType.TreeItem)
        {
            return true;
        }

        try
        {
            return element.Patterns.Invoke.PatternOrDefault is not null
                || element.TryGetClickablePoint(out _);
        }
        catch
        {
            return false;
        }
    }

    private static IReadOnlyList<string> ActionsFor(ControlType controlType, bool tappable)
    {
        var actions = new List<string>();
        if (tappable)
        {
            actions.Add("tap");
        }

        if (controlType is ControlType.Edit or ControlType.ComboBox)
        {
            actions.Add("type");
            actions.Add("clear");
        }

        if (controlType is ControlType.Document or ControlType.List or ControlType.Pane or ControlType.Table or ControlType.Tree or ControlType.Window)
        {
            actions.Add("scroll");
        }

        return actions;
    }

    private static bool IsMenuContainer(UiElement element)
    {
        var controlType = SafeControlType(element);
        return controlType is ControlType.MenuBar or ControlType.Menu or ControlType.ToolBar;
    }

    private static bool IsMenuElement(UiElement element)
    {
        var controlType = SafeControlType(element);
        return controlType is ControlType.MenuBar or ControlType.Menu or ControlType.MenuItem or ControlType.Button;
    }

    private static string ElementId(UiElement element, int index)
    {
        var automationId = SafeAutomationId(element);
        if (!string.IsNullOrWhiteSpace(automationId))
        {
            return $"uia:{automationId}";
        }

        var name = SafeName(element);
        if (!string.IsNullOrWhiteSpace(name))
        {
            return $"uia:{Slug(name)}:{index.ToString(CultureInfo.InvariantCulture)}";
        }

        return $"uia:{ToElementType(SafeControlType(element))}:{index.ToString(CultureInfo.InvariantCulture)}";
    }

    private static string WindowId(IntPtr handle) => $"hwnd:{handle.ToInt64():x}";

    private static string ScreenKey(UiElement root)
    {
        var name = SafeName(root);
        return string.IsNullOrWhiteSpace(name) ? "windows.unknown" : Slug(name);
    }

    private static AppRevealFrame Frame(UiElement element)
    {
        try
        {
            var rect = element.BoundingRectangle;
            return new AppRevealFrame(rect.X, rect.Y, rect.Width, rect.Height);
        }
        catch
        {
            return AppRevealFrame.Zero;
        }
    }

    private static ControlType SafeControlType(UiElement element)
    {
        try
        {
            return element.ControlType;
        }
        catch
        {
            return ControlType.Unknown;
        }
    }

    private static string SafeName(UiElement element)
    {
        try
        {
            return element.Name ?? "";
        }
        catch
        {
            return "";
        }
    }

    private static string SafeAutomationId(UiElement element)
    {
        try
        {
            return element.AutomationId ?? "";
        }
        catch
        {
            return "";
        }
    }

    private static string SafeClassName(UiElement element)
    {
        try
        {
            return element.ClassName ?? "";
        }
        catch
        {
            return "";
        }
    }

    private static bool SafeIsEnabled(UiElement element)
    {
        try
        {
            return element.IsEnabled;
        }
        catch
        {
            return false;
        }
    }

    private static bool SafeIsOffscreen(UiElement element)
    {
        try
        {
            return element.IsOffscreen;
        }
        catch
        {
            return true;
        }
    }

    private static string ToElementType(ControlType controlType)
    {
        var value = controlType.ToString();
        return string.IsNullOrWhiteSpace(value)
            ? "unknown"
            : char.ToLowerInvariant(value[0]) + value[1..];
    }

    private static string Slug(string value)
    {
        var builder = new StringBuilder(value.Length);
        foreach (var ch in value.Trim())
        {
            if (char.IsLetterOrDigit(ch))
            {
                builder.Append(char.ToLowerInvariant(ch));
            }
            else if (builder.Length > 0 && builder[^1] != '.')
            {
                builder.Append('.');
            }
        }

        return builder.ToString().Trim('.');
    }

    private static JsonNode ToolSuccess(string tool, params (string Name, object? Value)[] values)
    {
        var payload = new Dictionary<string, object?>
        {
            ["success"] = true,
            ["tool"] = tool
        };

        foreach (var (name, value) in values)
        {
            payload[name] = value;
        }

        return Json.ToNode(payload);
    }

    private static JsonNode ToolFailure(string tool, string error, string message)
    {
        return Json.ToNode(new Dictionary<string, object?>
        {
            ["success"] = false,
            ["tool"] = tool,
            ["error"] = error,
            ["message"] = message
        });
    }

    private static string GetWindowTitle(IntPtr handle)
    {
        var length = NativeMethods.GetWindowTextLength(handle);
        if (length <= 0)
        {
            return "";
        }

        var builder = new StringBuilder(length + 1);
        NativeMethods.GetWindowText(handle, builder, builder.Capacity);
        return builder.ToString();
    }

    private static bool TryParseWindowId(string windowId, out IntPtr handle)
    {
        handle = IntPtr.Zero;
        const string prefix = "hwnd:";
        if (!windowId.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!long.TryParse(windowId[prefix.Length..], NumberStyles.HexNumber, null, out var raw))
        {
            return false;
        }

        handle = new IntPtr(raw);
        return true;
    }

    private static class NativeMethods
    {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
