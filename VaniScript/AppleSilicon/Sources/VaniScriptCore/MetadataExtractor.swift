import Foundation

public enum MetadataExtractor {
    public static func extract(fromFileName fileName: String) -> AudioMetadata {
        let stem = deletingMediaExtension(from: fileName)
        let normalizedStem = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scriptureTitles = extractScriptureTitles(from: normalizedStem)
        let peopleStem = removingScriptureTitles(from: normalizedStem)

        return AudioMetadata(
            date: extractDate(from: stem) ?? "",
            location: extractLocation(from: normalizedStem) ?? "",
            lecturer: extractLecturer(from: peopleStem) ?? "",
            participants: scriptureTitles.joined(separator: ", ")
        )
    }

    private static func deletingMediaExtension(from fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension.lowercased()
        let knownExtensions = ["mp3", "mp4", "m4a", "wav", "webm", "mov", "mkv", "flac"]
        if knownExtensions.contains(ext) {
            return url.deletingPathExtension().lastPathComponent
        }
        let name = url.lastPathComponent
        let pattern = #"\.[a-z0-9]{2,4}$"#
        if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    private static func extractScriptureTitles(from stem: String) -> [String] {
        let knownTitles: [(String, String)] = [
            (#"\b(?:Srimad|Śrīmad|Shrimad)\s+Bhagavatam\b"#, "Srimad Bhagavatam"),
            (#"\bBhagavatam\b"#, "Srimad Bhagavatam"),
            (#"\b(?:ŚB|SB)\b"#, "Srimad Bhagavatam"),
            (#"\b(?:Caitanya|Chaitanya)\s+(?:Caritamrita|Charitamrita|Caritāmṛta|Charitāmṛta)\b"#, "Caitanya Caritamrita"),
            (#"\bCC\b"#, "Caitanya Caritamrita"),
            (#"\bBhagavad\s+Gita\b"#, "Bhagavad Gita"),
            (#"\bBG\b"#, "Bhagavad Gita"),
            (#"\bNectar\s+of\s+Devotion\b"#, "Nectar of Devotion"),
            (#"\bNOD\b"#, "Nectar of Devotion"),
            (#"\bNectar\s+of\s+Instruction\b"#, "Nectar of Instruction"),
            (#"\bNOI\b"#, "Nectar of Instruction"),
        ]

        var result: [String] = []
        for (pattern, title) in knownTitles {
            if stem.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil,
               !result.contains(title) {
                result.append(title)
            }
        }
        return result
    }

    private static func removingScriptureTitles(from stem: String) -> String {
        let patterns = [
            #"\b(?:Srimad|Śrīmad|Shrimad)\s+Bhagavatam\b"#,
            #"\bBhagavatam\b"#,
            #"\b(?:ŚB|SB)\b"#,
            #"\b(?:Caitanya|Chaitanya)\s+(?:Caritamrita|Charitamrita|Caritāmṛta|Charitāmṛta)\b"#,
            #"\bCC\b"#,
            #"\bBhagavad\s+Gita\b"#,
            #"\bBG\b"#,
            #"\bNectar\s+of\s+Devotion\b"#,
            #"\bNOD\b"#,
            #"\bNectar\s+of\s+Instruction\b"#,
            #"\bNOI\b"#,
            #"\bClass\b"#,
            #"\bLecture\b"#,
        ]
        return patterns.reduce(stem) { partial, pattern in
            partial.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractDate(from stem: String) -> String? {
        let patterns = [
            #"\b\d{4}[-._]\d{1,2}[-._]\d{1,2}\b"#,
            #"\b\d{1,2}[-._]\d{1,2}[-._]\d{4}\b"#,
            #"\b\d{8}\b"#,
            #"\b(?:19|20)\d{2}\b"#,
        ]

        for pattern in patterns {
            guard let match = stem.range(of: pattern, options: .regularExpression) else { continue }
            return String(stem[match]).replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "_", with: "-")
        }
        return nil
    }

    private static func extractLecturer(from stem: String) -> String? {
        let upper = stem.uppercased()
        let abbreviations: [(String, String)] = [
            ("KKS", "HH Kadamba Kanana Swami"),
            ("KK", "HH Kadamba Kanana Swami"),
            ("IDS", "HH Indradyumna Swami"),
            ("JPS", "HH Jayapataka Swami"),
            ("RNS", "HH Radhanath Swami"),
            ("SNS", "HH Sacinandana Swami"),
        ]

        for (token, lecturer) in abbreviations {
            if upper.range(of: #"(^|\s)\#(token)(\s|$)"#, options: .regularExpression) != nil {
                return lecturer
            }
        }

        let pattern = #"\b((?:HH|His Holiness|HG|H\.H\.)?\s*(?:[A-Z][A-Za-zāīūṛṣṅñṭḍṇĀĪŪṚṢṄÑṬḌṆ]+\s*){1,5}(?:Swami|Maharaja|Mahārāja|Das|Dasa|Goswami|Gosvami|Thakur|Ṭhākura|Prabhu|Mataji|Devi Dasi))\b"#
        guard let match = stem.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(stem[match]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractLocation(from stem: String) -> String? {
        let locations = [
            "Mayapur",
            "Māyāpur",
            "Vrindavan",
            "Vṛndāvana",
            "Govardhan",
            "Radha Kunda",
            "Radhakund",
            "Nabadwip",
            "Navadvipa",
            "Jagannath Puri",
            "Puri",
            "Mumbai",
            "Delhi",
            "Kolkata",
            "London",
            "New York",
            "Los Angeles",
            "Australia",
            "India",
        ]

        for location in locations {
            let escaped = NSRegularExpression.escapedPattern(for: location).replacingOccurrences(of: #"\\ "#, with: #"\s+"#)
            if stem.range(of: #"\b\#(escaped)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return location
            }
        }
        return nil
    }
}
