import Foundation

public struct ConfigHit: Equatable, Sendable {
    public var file: String
    public var keys: [String]
    public var error: String?

    public init(file: String, keys: [String], error: String? = nil) {
        self.file = file
        self.keys = keys
        self.error = error
    }
}

public enum ClaudeStateScanner {
    /// Drops relay and proxy keys anywhere in the tree. A token is dropped only in the same object as a non-official base URL.
    public static func cleaning(_ data: Data) throws -> SettingsEdit {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any] else { throw CleanError.notAnObject }
        let (scrubbed, removed) = scrub(object)
        let unique = Array(Set(removed)).sorted()
        guard !unique.isEmpty else { return SettingsEdit(removed: [], data: nil) }
        let written = try JSONSerialization.data(withJSONObject: scrubbed, options: [.prettyPrinted, .sortedKeys])
        return SettingsEdit(removed: unique, data: written)
    }

    public static func hits(in data: Data) throws -> [String] {
        try cleaning(data).removed
    }

    static func scrub(_ object: [String: Any]) -> ([String: Any], [String]) {
        var dict = object
        var removed: [String] = []
        let relay = dict.contains { key, value in
            LeftoverName.baseURLKeys.contains(key) && !official(value)
        }
        for key in dict.keys.sorted() {
            let dropProxy = LeftoverName.isProxyKey(key)
            let dropURL = LeftoverName.baseURLKeys.contains(key) && !official(dict[key])
            let dropToken = relay && LeftoverName.tokenKeys.contains(key)
            if dropProxy || dropURL || dropToken {
                dict.removeValue(forKey: key)
                removed.append(key)
            }
        }
        for key in Array(dict.keys) {
            if let child = dict[key] as? [String: Any] {
                let (next, more) = scrub(child)
                if key == "env", next.isEmpty {
                    dict.removeValue(forKey: key)
                } else {
                    dict[key] = next
                }
                removed.append(contentsOf: more)
            } else if let list = dict[key] as? [Any] {
                var next: [Any] = []
                for item in list {
                    if let child = item as? [String: Any] {
                        let (scrubbed, more) = scrub(child)
                        next.append(scrubbed)
                        removed.append(contentsOf: more)
                    } else {
                        next.append(item)
                    }
                }
                dict[key] = next
            }
        }
        return (dict, removed)
    }

    private static func official(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return LeftoverName.isOfficialAPI(value)
    }
}

public enum ProjectSettingsScanner {
    public static let skipNames: Set<String> = ["node_modules", ".git", ".build", "DerivedData", "Library"]

    public static func scan(roots: [URL], maxDepth: Int = 4) -> [ConfigHit] {
        var hits: [ConfigHit] = []
        let files = FileManager.default
        for root in roots {
            var isDir: ObjCBool = false
            guard files.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let enumerator = files.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            let rootDepth = root.standardizedFileURL.pathComponents.count
            while let item = enumerator.nextObject() as? URL {
                let name = item.lastPathComponent
                let depth = item.standardizedFileURL.pathComponents.count - rootDepth
                if skipNames.contains(name) || depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard name == "settings.json" || name == "settings.local.json" else { continue }
                guard item.deletingLastPathComponent().lastPathComponent == ".claude" else { continue }
                hits.append(hit(at: item))
            }
        }
        return hits.sorted { $0.file < $1.file }
    }

    public static func hit(at url: URL) -> ConfigHit {
        let file = PathDisplay.abbreviate(url.path)
        do {
            let data = try Data(contentsOf: url)
            let edit = try SettingsCleaner.cleaning(data)
            return ConfigHit(file: file, keys: edit.removed.sorted())
        } catch {
            return ConfigHit(file: file, keys: [], error: "Could not read \(file).")
        }
    }
}

public enum CodexConfig {
    public static func hits(in text: String) -> [String] {
        decisions(in: text).map(\.key)
    }

    public static func commenting(_ text: String, date: String) -> ShellEdit {
        var section = ""
        var removed: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let edited = lines.map { line -> String in
            if let next = sectionName(in: line) {
                section = next
                return line
            }
            guard let found = badAssignment(in: line, section: section) else { return line }
            removed.append(found.key)
            return "# cavok \(date): commented out \(found.key)\n# \(line)"
        }
        let joined = edited.joined(separator: "\n")
        let restored = text.hasSuffix("\n") && !joined.hasSuffix("\n") ? joined + "\n" : joined
        return ShellEdit(text: restored, removed: removed)
    }

    static func decisions(in text: String) -> [(key: String, line: String)] {
        var section = ""
        var found: [(key: String, line: String)] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let next = sectionName(in: line) {
                section = next
                continue
            }
            if let hit = badAssignment(in: line, section: section) {
                found.append((hit.key, line))
            }
        }
        return found
    }

    static func sectionName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.hasPrefix("#") else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    static func badAssignment(in line: String, section: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        guard let regex = try? NSRegularExpression(
            pattern: #"^(openai_base_url|chatgpt_base_url|base_url)\s*=\s*(.+)$"#
        ) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let keyRange = Range(match.range(at: 1), in: trimmed),
              let valueRange = Range(match.range(at: 2), in: trimmed) else { return nil }
        let name = String(trimmed[keyRange])
        if name == "base_url", !section.hasPrefix("model_providers") { return nil }
        let value = tomlString(String(trimmed[valueRange]))
        guard !LeftoverName.isOfficialAPI(value) else { return nil }
        let key = name == "base_url" && !section.isEmpty ? "\(section).\(name)" : name
        return (key, value)
    }

    static func tomlString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "\"" || first == "'" else {
            return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        }
        var out = ""
        var index = trimmed.index(after: trimmed.startIndex)
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == first { break }
            out.append(character)
            index = trimmed.index(after: index)
        }
        return out
    }
}

public enum PathDisplay {
    public static func abbreviate(_ path: String, home: String? = nil) -> String {
        let homePath = home ?? FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath { return "~" }
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        if path.hasPrefix(prefix) { return "~/" + path.dropFirst(prefix.count) }
        return path
    }
}
