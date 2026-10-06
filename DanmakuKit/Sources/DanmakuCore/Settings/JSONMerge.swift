import Foundation

/// Decodes settings by merging stored JSON over the JSON of the defaults, so files written by older or newer
/// versions (missing or unknown keys) always load.
public enum JSONMerge {
    public static func decode<T: Codable>(_ type: T.Type, from stored: Data, defaults: T) throws -> T {
        let encoder = JSONEncoder()
        let base = try JSONSerialization.jsonObject(with: encoder.encode(defaults))
        let overlay = try JSONSerialization.jsonObject(with: stored)
        let merged = merge(base, overlay)
        let data = try JSONSerialization.data(withJSONObject: merged)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // A value of the wrong type somewhere: fall back to merging key by key at the top level.
            guard let baseDict = base as? [String: Any], let overlayDict = overlay as? [String: Any] else {
                return defaults
            }
            var result = baseDict
            for (key, value) in overlayDict where baseDict[key] != nil {
                var candidate = result
                candidate[key] = merge(baseDict[key]!, value)
                if let d = try? JSONSerialization.data(withJSONObject: candidate),
                    (try? JSONDecoder().decode(T.self, from: d)) != nil
                {
                    result = candidate
                }
            }
            let d = try JSONSerialization.data(withJSONObject: result)
            return (try? JSONDecoder().decode(T.self, from: d)) ?? defaults
        }
    }

    /// Recursively overlays `overlay` onto `base`. Dictionaries merge; anything else is replaced.
    static func merge(_ base: Any, _ overlay: Any) -> Any {
        guard let b = base as? [String: Any], let o = overlay as? [String: Any] else { return overlay }
        var result = b
        for (key, value) in o {
            if let existing = b[key] {
                result[key] = merge(existing, value)
            } else if b.isEmpty {
                // Free-form dictionaries (e.g. preferredAdapters) accept any key.
                result[key] = value
            }
        }
        return result
    }
}
