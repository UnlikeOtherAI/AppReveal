using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AppReveal.Windows;

public sealed record McpToolDefinition(
    string Name,
    string Description,
    JsonObject InputSchema);

internal sealed class McpTool
{
    public McpTool(string name, string description, JsonObject inputSchema, Func<JsonObject?, CancellationToken, ValueTask<JsonNode>> handler)
    {
        Definition = new McpToolDefinition(name, description, inputSchema);
        Handler = handler;
    }

    public McpToolDefinition Definition { get; }
    public Func<JsonObject?, CancellationToken, ValueTask<JsonNode>> Handler { get; }
}

internal sealed class McpInvalidParamsException : Exception
{
    public McpInvalidParamsException(string message) : base(message)
    {
    }
}

internal sealed class McpUnknownToolException : Exception
{
    public McpUnknownToolException(string toolName) : base(toolName)
    {
        ToolName = toolName;
    }

    public string ToolName { get; }
}

internal sealed class McpRouter
{
    private readonly Dictionary<string, McpTool> tools = new(StringComparer.Ordinal);
    private readonly string serverName;
    private readonly string version;

    public McpRouter(string serverName, string version)
    {
        this.serverName = serverName;
        this.version = version;
    }

    public IReadOnlyCollection<McpToolDefinition> Tools => tools.Values.Select(tool => tool.Definition).ToArray();

    public void Register(McpTool tool)
    {
        tools[tool.Definition.Name] = tool;
    }

    public async ValueTask<JsonObject?> HandleAsync(JsonObject request, CancellationToken cancellationToken)
    {
        var hasId = request.TryGetPropertyValue("id", out var idNode);
        var id = hasId ? idNode?.DeepClone() : null;
        var method = Json.ReadString(request, "method") ?? "";

        if (!hasId)
        {
            return null;
        }

        try
        {
            return method switch
            {
                "initialize" => Success(id, new JsonObject
                {
                    ["protocolVersion"] = "2025-06-18",
                    ["capabilities"] = new JsonObject { ["tools"] = new JsonObject() },
                    ["serverInfo"] = new JsonObject { ["name"] = serverName, ["version"] = version }
                }),
                "tools/list" => Success(id, new JsonObject
                {
                    ["tools"] = new JsonArray(tools.Values.Select(ToToolJson).ToArray<JsonNode?>())
                }),
                "tools/call" => Success(id, await HandleToolCallAsync(request["params"] as JsonObject, cancellationToken)),
                "ping" => Success(id, new JsonObject()),
                _ => Error(id, -32601, $"Method not found: {method}")
            };
        }
        catch (McpInvalidParamsException ex)
        {
            return Error(id, -32602, $"Invalid params: {ex.Message}");
        }
        catch (McpUnknownToolException ex)
        {
            return Error(id, -32601, $"Method not found: {ex.ToolName}");
        }
        catch (Exception ex)
        {
            return Error(id, -32603, ex.Message);
        }
    }

    public async ValueTask<JsonNode> CallToolAsync(string name, JsonObject? arguments, CancellationToken cancellationToken)
    {
        if (!tools.TryGetValue(name, out var tool))
        {
            throw new McpUnknownToolException(name);
        }

        return await tool.Handler(arguments, cancellationToken);
    }

    private async ValueTask<JsonObject> HandleToolCallAsync(JsonObject? parameters, CancellationToken cancellationToken)
    {
        var toolName = Json.ReadString(parameters, "name");
        if (string.IsNullOrWhiteSpace(toolName))
        {
            throw new McpInvalidParamsException("Missing tool name");
        }

        if (parameters?["arguments"] is JsonNode argumentNode && argumentNode is not JsonObject)
        {
            throw new McpInvalidParamsException("arguments must be an object");
        }

        var arguments = parameters?["arguments"] as JsonObject;
        var result = await CallToolAsync(toolName, arguments, cancellationToken);
        var text = JsonSerializer.Serialize(result, Json.Options);
        return new JsonObject
        {
            ["content"] = new JsonArray
            {
                new JsonObject
                {
                    ["type"] = "text",
                    ["text"] = text
                }
            }
        };
    }

    private static JsonObject ToToolJson(McpTool tool)
    {
        return new JsonObject
        {
            ["name"] = tool.Definition.Name,
            ["description"] = tool.Definition.Description,
            ["inputSchema"] = tool.Definition.InputSchema.DeepClone()
        };
    }

    private static JsonObject Success(JsonNode? id, JsonNode result)
    {
        return new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id,
            ["result"] = result
        };
    }

    private static JsonObject Error(JsonNode? id, int code, string message)
    {
        return new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id,
            ["error"] = new JsonObject
            {
                ["code"] = code,
                ["message"] = message
            }
        };
    }
}

internal sealed class McpServer
{
    private const string SessionTokenHeaderName = "X-AppReveal-Session";
    private const string SessionTokenQueryName = "appreveal_session_token";

    private readonly McpRouter router;
    private readonly int requestedPort;
    private readonly string sessionToken;
    private readonly HashSet<string> allowedCorsOrigins = new(StringComparer.OrdinalIgnoreCase);
    private readonly bool allowLoopbackCorsOrigins;
    private CancellationTokenSource? cancellation;
    private HttpListener? listener;
    private Task? acceptLoop;

    public McpServer(
        McpRouter router,
        int requestedPort,
        string sessionToken,
        IEnumerable<string>? allowedCorsOrigins = null,
        bool allowLoopbackCorsOrigins = true)
    {
        this.router = router;
        this.requestedPort = requestedPort;
        this.sessionToken = string.IsNullOrWhiteSpace(sessionToken)
            ? throw new ArgumentException("Session token is required.", nameof(sessionToken))
            : sessionToken;
        this.allowLoopbackCorsOrigins = allowLoopbackCorsOrigins;

        foreach (var origin in allowedCorsOrigins ?? Array.Empty<string>())
        {
            var normalized = NormalizeOrigin(origin);
            if (normalized is not null)
            {
                this.allowedCorsOrigins.Add(normalized);
            }
        }
    }

    public int Port { get; private set; }

    public string Url { get; private set; } = "";

    public string SessionUrl => string.IsNullOrEmpty(Url)
        ? ""
        : $"{Url}?{SessionTokenQueryName}={Uri.EscapeDataString(sessionToken)}";

    public void Start()
    {
        if (listener is not null)
        {
            return;
        }

        var nextCancellation = new CancellationTokenSource();
        var nextListener = new HttpListener();
        try
        {
            Port = requestedPort == 0 ? FindFreeTcpPort() : requestedPort;
            Url = $"http://localhost:{Port}/";
            nextListener.Prefixes.Add(Url);
            nextListener.Start();

            cancellation = nextCancellation;
            listener = nextListener;
            acceptLoop = Task.Run(() => AcceptLoopAsync(nextCancellation.Token));
        }
        catch
        {
            try
            {
                nextListener.Close();
            }
            catch
            {
                // Best-effort cleanup for partially initialized listeners.
            }

            nextCancellation.Dispose();
            Port = 0;
            Url = "";
            throw;
        }
    }

    public void Stop()
    {
        cancellation?.Cancel();
        try
        {
            listener?.Stop();
            listener?.Close();
        }
        catch
        {
            // HttpListener can throw while an async accept is being interrupted.
        }

        listener = null;
        acceptLoop = null;
        cancellation?.Dispose();
        cancellation = null;
        Port = 0;
        Url = "";
    }

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested && listener is not null)
        {
            try
            {
                var context = await listener.GetContextAsync().WaitAsync(cancellationToken).ConfigureAwait(false);
                _ = Task.Run(() => HandleContextAsync(context, cancellationToken), CancellationToken.None);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (ObjectDisposedException)
            {
                break;
            }
            catch (HttpListenerException)
            {
                break;
            }
            catch (InvalidOperationException)
            {
                break;
            }
        }
    }

    private async Task HandleContextAsync(HttpListenerContext context, CancellationToken cancellationToken)
    {
        string? corsOrigin = null;
        try
        {
            if (!IsLoopbackRequest(context.Request))
            {
                await WriteResponseAsync(context.Response, 403, "Forbidden", "text/plain", null, cancellationToken);
                return;
            }

            corsOrigin = ResolveCorsOrigin(context.Request);
            if (context.Request.Headers["Origin"] is not null && corsOrigin is null)
            {
                await WriteResponseAsync(context.Response, 403, "Forbidden origin", "text/plain", null, cancellationToken);
                return;
            }

            if (context.Request.HttpMethod == "OPTIONS")
            {
                if (!IsCorsPreflightForPost(context.Request))
                {
                    await WriteResponseAsync(context.Response, 405, "Only POST is supported", "text/plain", corsOrigin, cancellationToken);
                    return;
                }

                WriteEmptyResponse(context.Response, 204, corsOrigin);
                return;
            }

            if (string.Equals(context.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase)
                && string.Equals(context.Request.Url?.AbsolutePath, "/health", StringComparison.Ordinal))
            {
                var health = new JsonObject
                {
                    ["status"] = "ok",
                    ["port"] = Port,
                    ["auth"] = "session-token",
                    ["discovery"] = "optional-provider"
                };
                await WriteResponseAsync(context.Response, 200, health.ToJsonString(Json.Options), "application/json", corsOrigin, cancellationToken);
                return;
            }

            if (!string.Equals(context.Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
            {
                await WriteResponseAsync(context.Response, 405, "Only POST is supported", "text/plain", corsOrigin, cancellationToken);
                return;
            }

            if (!IsAuthorized(context.Request))
            {
                await WriteResponseAsync(context.Response, 401, JsonRpcError(null, -32001, "Unauthorized"), "application/json", corsOrigin, cancellationToken);
                return;
            }

            using var reader = new StreamReader(context.Request.InputStream, context.Request.ContentEncoding ?? Encoding.UTF8);
            var body = await reader.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(body))
            {
                await WriteResponseAsync(context.Response, 400, JsonRpcError(null, -32600, "Empty body"), "application/json", corsOrigin, cancellationToken);
                return;
            }

            JsonObject? request;
            try
            {
                request = JsonNode.Parse(body) as JsonObject;
            }
            catch (JsonException)
            {
                await WriteResponseAsync(context.Response, 400, JsonRpcError(null, -32700, "Parse error"), "application/json", corsOrigin, cancellationToken);
                return;
            }

            if (request is null)
            {
                await WriteResponseAsync(context.Response, 400, JsonRpcError(null, -32600, "Invalid request"), "application/json", corsOrigin, cancellationToken);
                return;
            }

            var response = await router.HandleAsync(request, cancellationToken);
            if (response is null)
            {
                WriteEmptyResponse(context.Response, 204, corsOrigin);
                return;
            }

            await WriteResponseAsync(context.Response, 200, response.ToJsonString(Json.Options), "application/json", corsOrigin, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            try
            {
                context.Response.Close();
            }
            catch
            {
                // The listener is shutting down.
            }
        }
        catch (Exception ex)
        {
            if (context.Response.OutputStream.CanWrite)
            {
                await WriteResponseAsync(context.Response, 500, JsonRpcError(null, -32603, ex.Message), "application/json", corsOrigin, CancellationToken.None);
            }
        }
    }

    private static async Task WriteResponseAsync(HttpListenerResponse response, int status, string body, string contentType, string? corsOrigin, CancellationToken cancellationToken)
    {
        AddCorsHeaders(response, corsOrigin);
        response.StatusCode = status;
        response.ContentType = contentType;
        var bodyBytes = Encoding.UTF8.GetBytes(body);
        response.ContentLength64 = bodyBytes.Length;
        await response.OutputStream.WriteAsync(bodyBytes, cancellationToken).ConfigureAwait(false);
        response.Close();
    }

    private static void WriteEmptyResponse(HttpListenerResponse response, int status, string? corsOrigin)
    {
        AddCorsHeaders(response, corsOrigin);
        response.StatusCode = status;
        response.ContentLength64 = 0;
        response.Close();
    }

    private static void AddCorsHeaders(HttpListenerResponse response, string? corsOrigin)
    {
        if (corsOrigin is null)
        {
            return;
        }

        response.Headers["Access-Control-Allow-Origin"] = corsOrigin;
        response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
        response.Headers["Access-Control-Allow-Headers"] = $"Content-Type, Accept, Authorization, {SessionTokenHeaderName}";
        response.Headers["Vary"] = "Origin";
    }

    private bool IsAuthorized(HttpListenerRequest request)
    {
        return TokenMatches(ReadBearerToken(request.Headers["Authorization"]))
            || TokenMatches(request.Headers[SessionTokenHeaderName])
            || TokenMatches(request.QueryString[SessionTokenQueryName]);
    }

    private bool TokenMatches(string? candidate)
    {
        if (string.IsNullOrEmpty(candidate))
        {
            return false;
        }

        var expectedBytes = Encoding.UTF8.GetBytes(sessionToken);
        var candidateBytes = Encoding.UTF8.GetBytes(candidate);
        return expectedBytes.Length == candidateBytes.Length
            && CryptographicOperations.FixedTimeEquals(candidateBytes, expectedBytes);
    }

    private static string? ReadBearerToken(string? authorization)
    {
        const string prefix = "Bearer ";
        return authorization is not null && authorization.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            ? authorization[prefix.Length..].Trim()
            : null;
    }

    private string? ResolveCorsOrigin(HttpListenerRequest request)
    {
        var origin = request.Headers["Origin"];
        if (string.IsNullOrWhiteSpace(origin))
        {
            return null;
        }

        var normalized = NormalizeOrigin(origin);
        if (normalized is null)
        {
            return null;
        }

        if (allowedCorsOrigins.Contains(normalized))
        {
            return normalized;
        }

        return allowLoopbackCorsOrigins
            && Uri.TryCreate(normalized, UriKind.Absolute, out var originUri)
            && IsLoopbackHost(originUri.Host)
            ? normalized
            : null;
    }

    private static bool IsCorsPreflightForPost(HttpListenerRequest request)
    {
        var requestedMethod = request.Headers["Access-Control-Request-Method"];
        return string.IsNullOrWhiteSpace(requestedMethod)
            || string.Equals(requestedMethod, "POST", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsLoopbackRequest(HttpListenerRequest request)
    {
        if (request.RemoteEndPoint is not null && !IPAddress.IsLoopback(request.RemoteEndPoint.Address))
        {
            return false;
        }

        var host = ExtractHost(request.Headers["Host"] ?? request.UserHostName);
        return IsLoopbackHost(host);
    }

    private static bool IsLoopbackHost(string host)
    {
        if (string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return IPAddress.TryParse(host, out var address) && IPAddress.IsLoopback(address);
    }

    private static string ExtractHost(string? hostHeader)
    {
        if (string.IsNullOrWhiteSpace(hostHeader))
        {
            return "";
        }

        var host = hostHeader.Trim();
        if (host.StartsWith("[", StringComparison.Ordinal) && host.IndexOf(']') is var endBracket && endBracket > 0)
        {
            return host[1..endBracket];
        }

        var colon = host.LastIndexOf(':');
        if (colon > 0 && host.IndexOf(':') == colon)
        {
            return host[..colon];
        }

        return host;
    }

    private static string? NormalizeOrigin(string origin)
    {
        if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return null;
        }

        return uri.GetComponents(UriComponents.SchemeAndServer, UriFormat.UriEscaped).TrimEnd('/');
    }

    private static string JsonRpcError(JsonNode? id, int code, string message)
    {
        return new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id,
            ["error"] = new JsonObject
            {
                ["code"] = code,
                ["message"] = message
            }
        }.ToJsonString(Json.Options);
    }

    private static int FindFreeTcpPort()
    {
        var portProbe = new TcpListener(IPAddress.Loopback, 0);
        portProbe.Start();
        try
        {
            return ((IPEndPoint)portProbe.LocalEndpoint).Port;
        }
        finally
        {
            portProbe.Stop();
        }
    }
}
