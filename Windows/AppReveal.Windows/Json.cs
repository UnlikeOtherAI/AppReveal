using System.Text.Json;
using System.Text.Json.Nodes;

namespace AppReveal.Windows;

internal static class Json
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };

    public static JsonNode ToNode(object? value)
    {
        return JsonSerializer.SerializeToNode(value, Options) ?? JsonValue.Create((string?)null)!;
    }

    public static string? ReadString(JsonObject? source, string name)
    {
        if (source is null || !source.TryGetPropertyValue(name, out var node) || node is null)
        {
            return null;
        }

        return node is JsonValue value && value.TryGetValue<string>(out var stringValue)
            ? stringValue
            : null;
    }

    public static int? ReadInt(JsonObject? source, string name)
    {
        if (source is null || !source.TryGetPropertyValue(name, out var node) || node is null)
        {
            return null;
        }

        if (node is JsonValue value && value.TryGetValue<int>(out var intValue))
        {
            return intValue;
        }

        if (node is JsonValue doubleValue && doubleValue.TryGetValue<double>(out var number))
        {
            return (int)number;
        }

        return null;
    }

    public static bool? ReadBool(JsonObject? source, string name)
    {
        if (source is null || !source.TryGetPropertyValue(name, out var node) || node is null)
        {
            return null;
        }

        return node is JsonValue value && value.TryGetValue<bool>(out var boolValue)
            ? boolValue
            : null;
    }

    public static double? ReadDouble(JsonObject? source, string name)
    {
        if (source is null || !source.TryGetPropertyValue(name, out var node) || node is null)
        {
            return null;
        }

        if (node is JsonValue value && value.TryGetValue<double>(out var doubleValue))
        {
            return doubleValue;
        }

        if (node is JsonValue intValue && intValue.TryGetValue<int>(out var number))
        {
            return number;
        }

        return null;
    }
}
