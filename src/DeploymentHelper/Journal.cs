using System.Text.Json;
using System.Text.Json.Serialization;

internal sealed record Journal(string Nonce, bool CertificateCreated, string UserSid,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? InstallRoot = null);

[JsonSerializable(typeof(Journal))]
internal partial class JournalContext : JsonSerializerContext { }

internal static class JournalJson {
    internal static string Serialize(Journal value) => JsonSerializer.Serialize(value, JournalContext.Default.Journal);
    internal static Journal Deserialize(string json) => JsonSerializer.Deserialize(json, JournalContext.Default.Journal)
        ?? throw new InvalidDataException("Missing transaction receipt.");
}
