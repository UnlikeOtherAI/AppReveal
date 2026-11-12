using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using AppReveal.Windows;

internal static class Program
{
    private static int checks;
    private static int exitCode;
    [STAThread]
    static int Main(string[] args)
    {
        if (!args.Contains("--ui"))
        {
            Protocol().GetAwaiter().GetResult();
            Console.WriteLine($"PASS {checks} authenticated HTTP protocol/provider checks");
            return 0;
        }
        ApplicationConfiguration.Initialize();
        using var form = new VerificationForm { Text = "AppReveal Windows verification", Width = 700, Height = 600 };
        var edit = new TextBox { Name = "edit", Top = 20, Left = 20, Width = 300 };
        var readOnly = new TextBox { Name = "readonly", Top = 60, Left = 20, ReadOnly = true, Text = "fixed" };
        var button = new Button { Text = "Count", Name = "count", Top = 100, Left = 20 };
        var disabled = new Button { Text = "Disabled", Name = "disabled", Top = 140, Left = 20, Enabled = false };
        var tabs = new TabControl { Left = 20, Top = 210, Width = 300, Height = 180 };
        tabs.TabPages.Add("First"); tabs.TabPages.Add("Second");
        var list = new ListBox { Name = "scroll-list", Left = 400, Top = 20, Width = 200, Height = 350 };
        list.Items.AddRange(Enumerable.Range(0, 100).Select(index => (object)$"Row {index}").ToArray());
        var state = new State { ScrollPosition = () => (int)form.Invoke(new Func<int>(() => list.TopIndex)) };
        form.OnBack = () => state.Back++;
        form.OnDismiss = () => state.Dismiss++;
        tabs.SelectedIndexChanged += (_, _) => state.Tab = tabs.SelectedIndex;
        button.Click += (_, _) => state.Clicks++;
        edit.TextChanged += (_, _) => state.Text = edit.Text;
        var menu = new MenuStrip { Dock = DockStyle.Bottom };
        var menuRoot = new ToolStripMenuItem("Action");
        menuRoot.DropDownItems.Add("Increment menu", null, (_, _) => state.Menu++);
        menu.Items.Add(menuRoot);
        form.MainMenuStrip = menu;
        form.Controls.AddRange([edit, readOnly, button, disabled, tabs, list, menu]);
        form.Shown += async (_, _) => {
            try
            {
                // UIA must run off the GUI thread; this is a real in-process WinForms host.
                await Task.Run(async () => {
                    using var session = AppReveal.Windows.AppReveal.Start(new AppRevealOptions { StateProvider = state });
                    using var client = Client(session);
                    var windows = await Call(client, "list_windows");
                    var window = windows["windows"]![0]!["id"]!.GetValue<string>();
                    var inventory = await Call(client, "get_elements", new { window_id = window });
                    string Id(string label) => inventory["elements"]!.AsArray().First(e => e!["label"]?.GetValue<string>() == label)!["id"]!.GetValue<string>();
                    var editId = inventory["elements"]!.AsArray().First(e => e!["type"]?.GetValue<string>() == "edit" && e["value"]?.GetValue<string>() == "")!["id"]!.GetValue<string>();
                    var readOnlyId = inventory["elements"]!.AsArray().First(e => e!["value"]?.GetValue<string>() == "fixed")!["id"]!.GetValue<string>();
                    var countId = Id("Count");
                    var tree = await Call(client, "get_view_tree");
                    Check(tree.ToJsonString().Contains(countId), "tree IDs match actionable inventory IDs");
                    Check((await Call(client, "tap_element", new { element_id = countId }))["success"]!.GetValue<bool>(), "button tap accepted");
                    Check((await Call(client, "get_state"))["clicks"]!.GetValue<int>() == 1, "button changed real app state");
                    var unicode = "Žluťoučký 🦕 東京 \"quote\"\n";
                    Check((await Call(client, "type_text", new { element_id = editId, text = unicode.TrimEnd() }))["success"]!.GetValue<bool>(), "Unicode type accepted");
                    Check((await Call(client, "get_state"))["text"]!.GetValue<string>() == unicode.TrimEnd(), "Unicode reached real textbox");
                    await Call(client, "clear_text", new { element_id = editId });
                    Check((await Call(client, "get_state"))["text"]!.GetValue<string>() == "", "clear changed real textbox");
                    await Failed(client, "type_text", new { element_id = readOnlyId, text = "changed" });
                    await Failed(client, "tap_element", new { element_id = Id("Disabled") });
                    await Failed(client, "tap_element", new { element_id = "missing" });
                    await Failed(client, "tap_point", new { x = -100000, y = -100000 });
                    await Failed(client, "scroll", new { direction = "sideways" });
                    await Failed(client, "scroll", new { element_id = countId });
                    Check((await Call(client, "select_tab", new { index = 1 }))["success"]!.GetValue<bool>(), "tab selection accepted");
                    Check((await Call(client, "get_state"))["tab"]!.GetValue<int>() == 1, "tab selection changed real app state");
                    var listId = inventory["elements"]!.AsArray().First(e => e!["type"]?.GetValue<string>() == "list")!["id"]!.GetValue<string>();
                    Check((await Call(client, "scroll", new { element_id = listId, direction = "down", amount = 3 }))["success"]!.GetValue<bool>(), "list scroll accepted");
                    Check((await Call(client, "get_state"))["topIndex"]!.GetValue<int>() > 0, "list scroll changed real viewport");
                    var rowId = inventory["elements"]!.AsArray().First(e => e!["label"]?.GetValue<string>() == "Row 90")!["id"]!.GetValue<string>();
                    Check((await Call(client, "scroll_to_element", new { element_id = rowId }))["success"]!.GetValue<bool>(), "scroll-to-element accepted");
                    Check((await Call(client, "get_state"))["topIndex"]!.GetValue<int>() > 70, "scroll-to-element reached target row");
                    await Failed(client, "scroll_to_element", new { element_id = "missing" });
                    await Failed(client, "select_tab", new { index = 999 });
                    await Failed(client, "open_deeplink", new { url = "relative" });
                    Check((await Call(client, "get_menu_bar"))["count"]!.GetValue<int>() > 0, "native menu inventory available");
                    Check((await Call(client, "click_menu_item", new { title_path = "Action > Increment menu" }))["success"]!.GetValue<bool>(), "native menu action accepted");
                    Check((await Call(client, "get_state"))["menu"]!.GetValue<int>() == 1, "native menu changed real app state");
                    Check((await Call(client, "focus_window", new { window_id = window }))["success"]!.GetValue<bool>(), "app window focused");
                    Check((await Call(client, "navigate_back", new { window_id = window }))["input_sent"]!.GetValue<bool>(), "back shortcut dispatched");
                    await Task.Delay(100);
                    Check((await Call(client, "get_state"))["back"]!.GetValue<int>() == 1, "back shortcut reached real app handler");
                    Check((await Call(client, "dismiss_modal", new { window_id = window }))["input_sent"]!.GetValue<bool>(), "dismiss shortcut dispatched");
                    await Task.Delay(100);
                    Check((await Call(client, "get_state"))["dismiss"]!.GetValue<int>() == 1, "dismiss shortcut reached real app handler");
                    await Failed(client, "navigate_back", new { window_id = "hwnd:0" });
                    await Failed(client, "dismiss_modal", new { window_id = "hwnd:0" });
                    var image = await Rpc(client, "tools/call", new { name = "screenshot", arguments = new { element_id = countId } });
                    Check(image["result"]!["content"]![0]!["type"]!.GetValue<string>() == "image", "screenshot is MCP image content");
                    var bytes = Convert.FromBase64String(image["result"]!["content"]![0]!["data"]!.GetValue<string>());
                    using var stream = new MemoryStream(bytes);
                    using var decoded = System.Drawing.Image.FromStream(stream);
                    Check(decoded.Width > 0 && decoded.Height > 0, "actual screenshot decodes");
                    await Call(client, "tap_element", new { element_id = countId });
                    Check((await Call(client, "get_state"))["clicks"]!.GetValue<int>() == 2, "interaction recovers after failures");
                });
                Console.WriteLine($"PASS {checks} real WinForms UI/MCP checks");
            }
            catch (Exception exception) { Console.Error.WriteLine(exception); exitCode = 1; }
            finally { form.Close(); }
        };
        Application.Run(form);
        return exitCode;
    }

    static async Task Protocol()
    {
        using var session = AppReveal.Windows.AppReveal.Start(new AppRevealOptions { LogProvider = new Logs(), InteractionProvider = new FailureProvider(), DesktopProvider = null });
        using var client = Client(session);
        using var unauthenticated = new HttpClient { BaseAddress = new Uri(session.Url) };
        using var denied = await unauthenticated.PostAsync("", new StringContent("{}"));
        Check(denied.StatusCode == HttpStatusCode.Unauthorized, "missing token rejected");
        var tools = (await Rpc(client, "tools/list"))["result"]!["tools"]!.AsArray();
        Check(!tools.Any(t => t!["name"]!.GetValue<string>() == "get_state"), "unconfigured state not advertised");
        var type = tools.First(t => t!["name"]!.GetValue<string>() == "type_text")!;
        Check(type["inputSchema"]!["properties"]!["text"] is not null, "interaction schema describes text");
        foreach (var body in new[] { "{}", "{\"id\":1,\"method\":\"ping\"}", "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"ping\"}", "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"params\":false}" })
        {
            var response = await Post(client, body);
            Check(response["error"]!["code"]!.GetValue<int>() == -32600, "malformed envelope rejected");
        }
        Check((await Post(client, "{"))["error"]!["code"]!.GetValue<int>() == -32700, "invalid JSON rejected");
        using var invalidUtf8 = await client.PostAsync("", new ByteArrayContent([0xff]));
        var invalidEncodingResponse = JsonNode.Parse(await invalidUtf8.Content.ReadAsStringAsync())!;
        Check(invalidEncodingResponse["error"]!["code"]!.GetValue<int>() == -32700, "invalid UTF-8 rejected");
        Check((await Post(client, " "))["error"]!["code"]!.GetValue<int>() == -32700, "empty JSON rejected as parse error");
        using var notification = await client.PostAsync("", new StringContent("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"));
        Check(notification.StatusCode == HttpStatusCode.NoContent, "notification has no response");
        await Failed(client, "tap_element", new { element_id = "missing" });
        var badType = await Rpc(client, "tools/call", new { name = "type_text", arguments = new { text = 42 } });
        Check(badType["error"]?["code"]?.GetValue<int>() == -32602, "invalid argument type is a parameter error");
        var batch = await Call(client, "batch", new { stop_on_error = true, actions = new[] { new { tool = "tap_element" }, new { tool = "launch_context" } } });
        Check(batch["results"]!.AsArray().Count == 1 && batch["success"]!.GetValue<bool>() == false, "batch stops on provider failure");
        foreach (var emptyError in new[] { "", " \t\n" })
        {
            var ok = await Rpc(client, "tools/call", new { name = "type_text", arguments = new { text = emptyError } });
            Check(ok["result"]?["isError"]?.GetValue<bool>() != true, "empty error text remains successful");
        }
        var errorBatch = await Call(client, "batch", new { stop_on_error = true, actions = new[] {
            new { tool = "type_text", arguments = new { text = "" } },
            new { tool = "type_text", arguments = new { text = " \t" } },
            new { tool = "type_text", arguments = new { text = "timeout" } },
            new { tool = "type_text", arguments = new { text = "" } }
        } });
        Check(errorBatch["results"]!.AsArray().Count == 3 && errorBatch["results"]![0]!["success"]!.GetValue<bool>() && errorBatch["results"]![1]!["success"]!.GetValue<bool>() && !errorBatch["results"]![2]!["success"]!.GetValue<bool>(), "batch continues past empty errors and stops on real error");
        var oversizedBatch = await Rpc(client, "tools/call", new { name = "batch", arguments = new { actions = Enumerable.Range(0, 101).Select(_ => new { tool = "launch_context" }).ToArray() } });
        Check(oversizedBatch["error"]?["code"]?.GetValue<int>() == -32602, "oversized batch rejected before execution");
        Check((await Call(client, "device_info"))["physicalMemoryMB"]!.GetValue<ulong>() > 0, "device reports installed physical memory");
        var logs = await Call(client, "get_logs", new { subsystem = "wanted", limit = 1 });
        Check(logs["logs"]!.AsArray().Count == 1 && logs["logs"]![0]!["subsystem"]!.GetValue<string>() == "wanted", "subsystem filter precedes limit");
        using var oversized = await client.PostAsync("", new StringContent(new string('x', 1024 * 1024 + 1)));
        Check(oversized.StatusCode == HttpStatusCode.RequestEntityTooLarge, "oversized body rejected");
        Check((await Rpc(client, "ping"))["result"] is JsonObject, "server recovered after errors");
    }
    static HttpClient Client(AppRevealSession session)
    {
        var client = new HttpClient { BaseAddress = new Uri(session.Url), Timeout = TimeSpan.FromSeconds(30) };
        client.DefaultRequestHeaders.Add("X-AppReveal-Session", session.SessionToken);
        return client;
    }
    static async Task<JsonNode> Post(HttpClient client, string body)
    {
        using var response = await client.PostAsync("", new StringContent(body, Encoding.UTF8, "application/json"));
        return JsonNode.Parse(await response.Content.ReadAsStringAsync())!;
    }
    static Task<JsonNode> Rpc(HttpClient client, string method, object? parameters = null) => Post(client, System.Text.Json.JsonSerializer.Serialize(new { jsonrpc = "2.0", id = 1, method, @params = parameters }));
    static async Task<JsonNode> Call(HttpClient client, string name, object? args = null)
    {
        var response = await Rpc(client, "tools/call", new { name, arguments = args });
        if (response["error"] is { } error) throw new Exception(error.ToJsonString());
        return JsonNode.Parse(response["result"]!["content"]![0]!["text"]!.GetValue<string>())!;
    }
    static async Task Failed(HttpClient client, string name, object? args)
    {
        var response = await Rpc(client, "tools/call", new { name, arguments = args });
        Check(response["result"]?["isError"]?.GetValue<bool>() == true, name + " failure is an MCP tool error");
    }
    static void Check(bool passed, string message) { if (!passed) throw new Exception(message); checks++; Console.WriteLine("PASS " + message); }
    sealed class VerificationForm : Form
    {
        public Action? OnBack;
        public Action? OnDismiss;
        protected override bool ProcessCmdKey(ref Message message, Keys keyData)
        {
            if (keyData == (Keys.Alt | Keys.Left)) { OnBack?.Invoke(); return true; }
            if (keyData == Keys.Escape) { OnDismiss?.Invoke(); return true; }
            return base.ProcessCmdKey(ref message, keyData);
        }
    }
    sealed class State : IAppRevealStateProvider { public int Clicks; public int Tab; public int Menu; public int Back; public int Dismiss; public string Text = ""; public Func<int>? ScrollPosition; public object Snapshot() => new { clicks = Clicks, text = Text, tab = Tab, menu = Menu, back = Back, dismiss = Dismiss, topIndex = ScrollPosition?.Invoke() }; }
    sealed class FailureProvider : IAppRevealInteractionProvider { public ValueTask<JsonNode> InvokeAsync(string tool, JsonObject? args) => ValueTask.FromResult<JsonNode>(tool == "type_text" ? new JsonObject { ["success"] = true, ["error"] = args?["text"]?.DeepClone() } : new JsonObject { ["success"] = false, ["error"] = "not_found" }); }
    sealed class Logs : IAppRevealLogProvider
    {
        public IReadOnlyList<AppRevealLogEntry> RecentLogs(int limit) => [new(DateTimeOffset.UtcNow, "info", "skip", "other"), new(DateTimeOffset.UtcNow, "info", "keep", "wanted")];
        public IReadOnlyList<AppRevealErrorEntry> RecentErrors() => [];
    }
}
