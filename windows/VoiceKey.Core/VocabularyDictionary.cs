using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace VoiceKey.Core;

/// <summary>
/// User-editable custom vocabulary: terms that bias Whisper through an initial prompt,
/// plus spoken-to-written replacement rules applied to the finished transcript.
/// </summary>
public sealed class VocabularyDictionary : IEquatable<VocabularyDictionary>
{
    public IReadOnlyList<string> Terms { get; }
    public IReadOnlyDictionary<string, string> Replacements { get; }

    public VocabularyDictionary(
        IReadOnlyList<string>? terms = null,
        IReadOnlyDictionary<string, string>? replacements = null)
    {
        Terms = terms ?? [];
        Replacements = replacements ?? new Dictionary<string, string>();
    }

    /// <summary>
    /// Whisper initial-prompt text biasing recognition toward the terms, or null when
    /// there are no terms.
    /// </summary>
    public string? PromptText
    {
        get
        {
            var named = Terms.Where(term => !string.IsNullOrWhiteSpace(term)).ToArray();
            return named.Length == 0 ? null : "Glossary: " + string.Join(", ", named) + ".";
        }
    }

    /// <summary>
    /// Applies every replacement rule in a single left-to-right pass, so a rule's output
    /// can never be rewritten by another rule. Longer keys win over overlapping shorter ones.
    /// </summary>
    public string ApplyingReplacements(string text) =>
        Matcher.For(Replacements)?.Applied(text) ?? text;

    /// <summary>Starter content written on first use so the user edits a documented example.</summary>
    public static VocabularyDictionary Template { get; } = new(
        terms: ["VoiceKey", "Whisper", "Kubernetes"],
        replacements: new Dictionary<string, string>
        {
            ["get hub"] = "GitHub",
            ["jason"] = "JSON",
        });

    /// <summary>
    /// A transcript offered back as a vocabulary term, or null when it is plainly
    /// a sentence rather than a name: terms bias recognition, and biasing towards
    /// a whole sentence would do more harm than good.
    /// </summary>
    public static string? SuggestedTerm(string transcript)
    {
        var words = transcript.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (words.Length is < 1 or > 4) return null;
        var term = string.Join(" ", words);
        return term.Length <= 40 ? term : null;
    }

    // MARK: - Storage

    /// <summary>
    /// Reads JSON from disk; null if the file is missing or malformed — a broken user edit
    /// must degrade to "no custom vocabulary", never crash the app.
    /// </summary>
    public static VocabularyDictionary? Load(string path)
    {
        try
        {
            var dto = JsonSerializer.Deserialize<Dto>(File.ReadAllText(path));
            return dto is null ? null : new VocabularyDictionary(dto.Terms, dto.Replacements);
        }
        catch (Exception exception) when (exception is IOException or JsonException
            or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Save(string path)
    {
        // Sorted keys and indentation so a hand-edited file stays readable and
        // diffs stay stable.
        var dto = new Dto(new SortedDictionary<string, string>(
                Replacements.ToDictionary(entry => entry.Key, entry => entry.Value),
                StringComparer.Ordinal),
            Terms);
        File.WriteAllText(path, JsonSerializer.Serialize(dto, SerializerOptions));
    }

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private sealed record Dto(
        [property: JsonPropertyName("replacements")] IReadOnlyDictionary<string, string> Replacements,
        [property: JsonPropertyName("terms")] IReadOnlyList<string> Terms);

    // MARK: - Equality

    public bool Equals(VocabularyDictionary? other) =>
        other is not null
        && Terms.SequenceEqual(other.Terms)
        && Replacements.Count == other.Replacements.Count
        && Replacements.All(entry => other.Replacements.TryGetValue(entry.Key, out var value)
                                     && value == entry.Value);

    public override bool Equals(object? obj) => Equals(obj as VocabularyDictionary);

    public override int GetHashCode() => HashCode.Combine(Terms.Count, Replacements.Count);
}

/// <summary>
/// One combined case-insensitive alternation over every rule key. Building a single
/// expression is what guarantees the single pass; ordering the alternatives longest-first
/// is what gives longer keys precedence.
/// </summary>
internal sealed class Matcher
{
    private readonly Regex _expression;
    private readonly IReadOnlyDictionary<string, string> _valuesByLowercasedKey;

    private Matcher(Regex expression, IReadOnlyDictionary<string, string> valuesByLowercasedKey)
    {
        _expression = expression;
        _valuesByLowercasedKey = valuesByLowercasedKey;
    }

    internal static Matcher? For(IReadOnlyDictionary<string, string> replacements)
    {
        var keys = replacements.Keys
            .Where(key => key.Length > 0)
            .OrderByDescending(key => key.Length)
            .ThenByDescending(key => key, StringComparer.Ordinal)
            .ToArray();
        if (keys.Length == 0) return null;

        var pattern = string.Join("|", keys.Select(WholeWordPattern));
        var values = new Dictionary<string, string>();
        foreach (var entry in replacements) values[entry.Key.ToLowerInvariant()] = entry.Value;

        try
        {
            return new Matcher(new Regex(pattern, RegexOptions.IgnoreCase), values);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    internal string Applied(string text) =>
        _expression.Replace(text, match =>
            _valuesByLowercasedKey.TryGetValue(match.Value.ToLowerInvariant(), out var value)
                ? value
                : match.Value);

    /// <summary>
    /// Escapes the key so metacharacters ("c++", "node.js") stay literal, and fences it with
    /// boundaries that adapt to the edge characters — <c>\b</c> only works next to word
    /// characters, so keys ending in punctuation get a "not followed by a word character"
    /// assertion instead.
    /// </summary>
    private static string WholeWordPattern(string key)
    {
        var leading = IsWordCharacter(key[0]) ? @"\b" : @"(?<!\w)";
        var trailing = IsWordCharacter(key[^1]) ? @"\b" : @"(?!\w)";
        return leading + Regex.Escape(key) + trailing;
    }

    private static bool IsWordCharacter(char character) =>
        character == '_' || char.IsLetter(character) || char.IsNumber(character);
}
