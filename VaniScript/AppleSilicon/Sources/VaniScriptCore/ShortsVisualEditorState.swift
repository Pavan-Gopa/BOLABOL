import Foundation

public struct AlignedWord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var start: Double
    public var end: Double

    public init(id: String, text: String, start: Double, end: Double) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct AlignedSubtitleSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [AlignedWord]

    public init(id: String, start: Double, end: Double, text: String, words: [AlignedWord] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

public struct FrameKeyframe: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var time: Double
    public var x: Double
    public var y: Double
    public var zoom: Double
    public var backgroundColor: String?

    public init(id: String, time: Double, x: Double, y: Double, zoom: Double, backgroundColor: String? = nil) {
        self.id = id
        self.time = time
        self.x = x
        self.y = y
        self.zoom = zoom
        self.backgroundColor = backgroundColor
    }
}

public struct TimelineCut: Codable, Equatable, Sendable {
    public var startSec: Double
    public var endSec: Double

    public init(startSec: Double, endSec: Double) {
        self.startSec = startSec
        self.endSec = endSec
    }
}

public struct TimelineTrim: Codable, Equatable, Sendable {
    public var trimStartSec: Double
    public var trimEndSec: Double

    public init(trimStartSec: Double, trimEndSec: Double) {
        self.trimStartSec = trimStartSec
        self.trimEndSec = trimEndSec
    }

    public static let zero = TimelineTrim(trimStartSec: 0, trimEndSec: 0)
}

public enum ShortsTextTransform: String, Codable, Equatable, Sendable {
    case none
    case uppercase
    case title
}

public struct ShortsSubtitleStyle: Codable, Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var bold: Bool
    public var textTransform: ShortsTextTransform
    public var textColor: String
    public var boxColor: String
    public var boxOpacity: Double
    public var boxWidth: Double
    public var boxHeight: Double
    public var edgeBlur: Double
    public var letterSpacing: Double
    public var lineSpacing: Double
    public var edgeSoftness: Double
    public var outline: Double
    public var outlineColor: String?
    public var outlineOpacity: Double?
    public var shadow: Double
    public var shadowColor: String?
    public var shadowOpacity: Double?
    public var shadowBlur: Double?
    public var shadowDistance: Double?
    public var shadowAngle: Double?
    public var subtitleBottomMargin: Double?

    public init(
        fontFamily: String,
        fontSize: Double,
        bold: Bool,
        textTransform: ShortsTextTransform,
        textColor: String,
        boxColor: String,
        boxOpacity: Double,
        boxWidth: Double,
        boxHeight: Double,
        edgeBlur: Double,
        letterSpacing: Double,
        lineSpacing: Double,
        edgeSoftness: Double,
        outline: Double,
        outlineColor: String? = nil,
        outlineOpacity: Double? = nil,
        shadow: Double,
        shadowColor: String? = nil,
        shadowOpacity: Double? = nil,
        shadowBlur: Double? = nil,
        shadowDistance: Double? = nil,
        shadowAngle: Double? = nil,
        subtitleBottomMargin: Double? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.bold = bold
        self.textTransform = textTransform
        self.textColor = textColor
        self.boxColor = boxColor
        self.boxOpacity = boxOpacity
        self.boxWidth = boxWidth
        self.boxHeight = boxHeight
        self.edgeBlur = edgeBlur
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.edgeSoftness = edgeSoftness
        self.outline = outline
        self.outlineColor = outlineColor
        self.outlineOpacity = outlineOpacity
        self.shadow = shadow
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.shadowBlur = shadowBlur
        self.shadowDistance = shadowDistance
        self.shadowAngle = shadowAngle
        self.subtitleBottomMargin = subtitleBottomMargin
    }

    public static let orangeImpact = ShortsSubtitleStyle(
        fontFamily: "Cuprum",
        fontSize: 74,
        bold: true,
        textTransform: .uppercase,
        textColor: "#FFFFFF",
        boxColor: "#FF8C00",
        boxOpacity: 0.5,
        boxWidth: 86,
        boxHeight: 1,
        edgeBlur: 0,
        letterSpacing: 0,
        lineSpacing: 1,
        edgeSoftness: 0.25,
        outline: 3,
        shadow: 4,
        subtitleBottomMargin: 560
    )

    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, bold, textTransform, textColor
        case boxColor, boxOpacity, boxWidth, boxHeight, edgeBlur
        case letterSpacing, lineSpacing, edgeSoftness
        case outline, outlineColor, outlineOpacity
        case shadow, shadowColor, shadowOpacity, shadowBlur, shadowDistance, shadowAngle
        case subtitleBottomMargin
    }

    public init(from decoder: Decoder) throws {
        let defaults = ShortsSubtitleStyle.orangeImpact
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fontFamily: try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? defaults.fontFamily,
            fontSize: try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize,
            bold: try container.decodeIfPresent(Bool.self, forKey: .bold) ?? defaults.bold,
            textTransform: try container.decodeIfPresent(ShortsTextTransform.self, forKey: .textTransform) ?? defaults.textTransform,
            textColor: try container.decodeIfPresent(String.self, forKey: .textColor) ?? defaults.textColor,
            boxColor: try container.decodeIfPresent(String.self, forKey: .boxColor) ?? defaults.boxColor,
            boxOpacity: try container.decodeIfPresent(Double.self, forKey: .boxOpacity) ?? defaults.boxOpacity,
            boxWidth: try container.decodeIfPresent(Double.self, forKey: .boxWidth) ?? defaults.boxWidth,
            boxHeight: try container.decodeIfPresent(Double.self, forKey: .boxHeight) ?? defaults.boxHeight,
            edgeBlur: try container.decodeIfPresent(Double.self, forKey: .edgeBlur) ?? defaults.edgeBlur,
            letterSpacing: try container.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? defaults.letterSpacing,
            lineSpacing: try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? defaults.lineSpacing,
            edgeSoftness: try container.decodeIfPresent(Double.self, forKey: .edgeSoftness) ?? defaults.edgeSoftness,
            outline: try container.decodeIfPresent(Double.self, forKey: .outline) ?? defaults.outline,
            outlineColor: try container.decodeIfPresent(String.self, forKey: .outlineColor) ?? defaults.outlineColor,
            outlineOpacity: try container.decodeIfPresent(Double.self, forKey: .outlineOpacity) ?? defaults.outlineOpacity,
            shadow: try container.decodeIfPresent(Double.self, forKey: .shadow) ?? defaults.shadow,
            shadowColor: try container.decodeIfPresent(String.self, forKey: .shadowColor) ?? defaults.shadowColor,
            shadowOpacity: try container.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? defaults.shadowOpacity,
            shadowBlur: try container.decodeIfPresent(Double.self, forKey: .shadowBlur) ?? defaults.shadowBlur,
            shadowDistance: try container.decodeIfPresent(Double.self, forKey: .shadowDistance) ?? defaults.shadowDistance,
            shadowAngle: try container.decodeIfPresent(Double.self, forKey: .shadowAngle) ?? defaults.shadowAngle,
            subtitleBottomMargin: try container.decodeIfPresent(Double.self, forKey: .subtitleBottomMargin) ?? defaults.subtitleBottomMargin
        )
    }
}

public struct ShortsBackgroundSettings: Codable, Equatable, Sendable {
    public var effectReferenceHeight: Double?
    public var solidEnabled: Bool
    public var solidColor: String
    public var blurEnabled: Bool
    public var blurStrength: Double
    public var blurScale: Double
    public var blurPanX: Double?
    public var gradientEnabled: Bool
    public var gradientType: String
    public var gradientColorA: String
    public var gradientColorB: String
    public var gradientAngle: Double
    public var gradientOpacity: Double
    public var featherEnabled: Bool
    public var featherTop: Double
    public var featherBottom: Double
    public var featherLeft: Double
    public var featherRight: Double
    public var frameGuideColor: String
    public var frameGuideOpacity: Double
    public var frameGuideBorderWidth: Double
    public var frameGuideBlur: Double
    public var frameGuideBorderOpacity: Double
    public var featherTopHeight: Double?
    public var featherBottomHeight: Double?

    public init(
        effectReferenceHeight: Double? = nil,
        solidEnabled: Bool,
        solidColor: String,
        blurEnabled: Bool,
        blurStrength: Double,
        blurScale: Double,
        gradientEnabled: Bool,
        gradientType: String,
        gradientColorA: String,
        gradientColorB: String,
        gradientAngle: Double,
        gradientOpacity: Double,
        featherEnabled: Bool,
        featherTop: Double,
        featherBottom: Double,
        featherLeft: Double,
        featherRight: Double,
        frameGuideColor: String,
        frameGuideOpacity: Double,
        frameGuideBorderWidth: Double,
        frameGuideBlur: Double,
        frameGuideBorderOpacity: Double,
        featherTopHeight: Double? = nil,
        featherBottomHeight: Double? = nil,
        blurPanX: Double? = nil
    ) {
        self.effectReferenceHeight = effectReferenceHeight
        self.solidEnabled = solidEnabled
        self.solidColor = solidColor
        self.blurEnabled = blurEnabled
        self.blurStrength = blurStrength
        self.blurScale = blurScale
        self.gradientEnabled = gradientEnabled
        self.gradientType = gradientType
        self.gradientColorA = gradientColorA
        self.gradientColorB = gradientColorB
        self.gradientAngle = gradientAngle
        self.gradientOpacity = gradientOpacity
        self.featherEnabled = featherEnabled
        self.featherTop = featherTop
        self.featherBottom = featherBottom
        self.featherLeft = featherLeft
        self.featherRight = featherRight
        self.frameGuideColor = frameGuideColor
        self.frameGuideOpacity = frameGuideOpacity
        self.frameGuideBorderWidth = frameGuideBorderWidth
        self.frameGuideBlur = frameGuideBlur
        self.frameGuideBorderOpacity = frameGuideBorderOpacity
        self.featherTopHeight = featherTopHeight
        self.featherBottomHeight = featherBottomHeight
        self.blurPanX = blurPanX
    }

    public static let universalDefault = ShortsBackgroundSettings(
        solidEnabled: false,
        solidColor: "#000000",
        blurEnabled: false,
        blurStrength: 30,
        blurScale: 1.3,
        gradientEnabled: false,
        gradientType: "linear",
        gradientColorA: "#000000",
        gradientColorB: "#1a1a2e",
        gradientAngle: 180,
        gradientOpacity: 0.6,
        featherEnabled: false,
        featherTop: 20,
        featherBottom: 20,
        featherLeft: 10,
        featherRight: 10,
        frameGuideColor: "#ffaa19",
        frameGuideOpacity: 0.5,
        frameGuideBorderWidth: 2,
        frameGuideBlur: 0,
        frameGuideBorderOpacity: 1,
        featherTopHeight: 100,
        featherBottomHeight: 100,
        blurPanX: 0.0
    )
}

public struct LogoOverlaySettings: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var src: String
    public var name: String?
    public var size: Double
    public var opacity: Double
    public var position: String?
    public var hidden: Bool?

    public init(
        id: String,
        src: String,
        name: String? = nil,
        size: Double,
        opacity: Double,
        position: String? = nil,
        hidden: Bool? = nil
    ) {
        self.id = id
        self.src = src
        self.name = name
        self.size = size
        self.opacity = opacity
        self.position = position
        self.hidden = hidden
    }
}

public struct IntroOutroOverlaySettings: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var src: String
    public var name: String?
    public var duration: Double
    public var x: Double
    public var y: Double
    public var scale: Double
    public var animation: String
    public var hidden: Bool?
    public var speed: Double?
    public var transitionSec: Double?

    public init(
        id: String,
        src: String,
        name: String? = nil,
        duration: Double,
        x: Double,
        y: Double,
        scale: Double,
        animation: String,
        hidden: Bool? = nil,
        speed: Double? = nil,
        transitionSec: Double? = nil
    ) {
        self.id = id
        self.src = src
        self.name = name
        self.duration = duration
        self.x = x
        self.y = y
        self.scale = scale
        self.animation = animation
        self.hidden = hidden
        self.speed = speed
        self.transitionSec = transitionSec
    }
}

public struct TextOverlayBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startSec: Double
    public var endSec: Double
    public var text: String
    public var hidden: Bool?

    public init(id: String, startSec: Double, endSec: Double, text: String, hidden: Bool? = nil) {
        self.id = id
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
        self.hidden = hidden
    }
}

public struct TextOverlayTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var hidden: Bool?
    public var muted: Bool?
    public var blocks: [TextOverlayBlock]
    public var style: ShortsSubtitleStyle?

    public init(
        id: String,
        name: String,
        hidden: Bool? = nil,
        muted: Bool? = nil,
        blocks: [TextOverlayBlock],
        style: ShortsSubtitleStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.muted = muted
        self.blocks = blocks
        self.style = style
    }
}

public struct ExtraAudioTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var src: String
    public var previewSrc: String?
    public var startSec: Double
    public var trimStartSec: Double
    public var trimEndSec: Double
    public var volume: Double
    public var fadeInSec: Double
    public var fadeOutSec: Double
    public var muted: Bool?
    public var assetDuration: Double?

    public init(
        id: String,
        name: String,
        src: String,
        previewSrc: String? = nil,
        startSec: Double,
        trimStartSec: Double,
        trimEndSec: Double,
        volume: Double,
        fadeInSec: Double,
        fadeOutSec: Double,
        muted: Bool? = nil,
        assetDuration: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.src = src
        self.previewSrc = previewSrc
        self.startSec = startSec
        self.trimStartSec = trimStartSec
        self.trimEndSec = trimEndSec
        self.volume = volume
        self.fadeInSec = fadeInSec
        self.fadeOutSec = fadeOutSec
        self.muted = muted
        self.assetDuration = assetDuration
    }
}

public enum ShortsVisualEditorStateBuilder {
    public static func segments(
        fromCaptionText captionText: String,
        clipStartSec: Double,
        clipEndSec: Double
    ) -> [AlignedSubtitleSegment] {
        let clipDuration = max(0, clipEndSec - clipStartSec)
        let parsed = captionText
            .split(whereSeparator: \.isNewline)
            .compactMap { parseCaptionLine(String($0), clipStartSec: clipStartSec, clipDuration: clipDuration) }
            .sorted { $0.start < $1.start }

        return parsed.enumerated().map { index, item in
            let nextStart = index + 1 < parsed.count ? parsed[index + 1].start : clipDuration
            let end = max(item.start + 0.25, min(clipDuration, nextStart))
            let base = AlignedSubtitleSegment(
                id: "sub_\(index)_\(stableSuffix(item.text))",
                start: item.start,
                end: end,
                text: item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return AlignedSubtitleSegment(
                id: base.id,
                start: base.start,
                end: base.end,
                text: base.text,
                words: inferredWords(for: base)
            )
        }
    }

    public static func segments(for plan: ShortsClipPlan, language: ShortsIdeaDisplayLanguage) -> [AlignedSubtitleSegment] {
        switch language {
        case .source:
            if let sourceAlignment = plan.sourceAlignment, !sourceAlignment.isEmpty {
                return normalized(sourceAlignment, duration: clipDuration(plan))
            }
            return segments(
                fromCaptionText: plan.sourceCaptionText ?? plan.captionText ?? "",
                clipStartSec: ShortsPlanner.parseTimestampToSeconds(plan.start),
                clipEndSec: ShortsPlanner.parseTimestampToSeconds(plan.end)
            )
        case .target:
            if let targetAlignment = plan.targetAlignment, !targetAlignment.isEmpty {
                return normalized(targetAlignment, duration: clipDuration(plan))
            }
            return segments(
                fromCaptionText: plan.targetCaptionText ?? plan.captionText ?? "",
                clipStartSec: ShortsPlanner.parseTimestampToSeconds(plan.start),
                clipEndSec: ShortsPlanner.parseTimestampToSeconds(plan.end)
            )
        }
    }

    public static func inferredWords(for segment: AlignedSubtitleSegment) -> [AlignedWord] {
        let words = segment.text.split { $0.isWhitespace }.map(String.init)
        guard !words.isEmpty else { return [] }
        let duration = max(0.25, segment.end - segment.start)
        let step = duration / Double(words.count)
        return words.enumerated().map { index, word in
            let start = segment.start + (Double(index) * step)
            let end = index == words.count - 1 ? segment.end : segment.start + (Double(index + 1) * step)
            return AlignedWord(id: "word_\(index)_\(stableSuffix(word))", text: word, start: start, end: end)
        }
    }

    public static func normalized(_ segments: [AlignedSubtitleSegment], duration: Double) -> [AlignedSubtitleSegment] {
        segments
            .map { segment in
                let start = min(max(0, segment.start), duration)
                let end = min(max(start + 0.25, segment.end), duration)
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = AlignedSubtitleSegment(id: segment.id, start: start, end: end, text: text)
                let words = segment.words.isEmpty ? inferredWords(for: base) : segment.words
                return AlignedSubtitleSegment(id: segment.id, start: start, end: end, text: text, words: words)
            }
            .sorted { $0.start < $1.start }
    }

    public static func clipDuration(_ plan: ShortsClipPlan) -> Double {
        max(0, ShortsPlanner.parseTimestampToSeconds(plan.end) - ShortsPlanner.parseTimestampToSeconds(plan.start))
    }

    private static func parseCaptionLine(
        _ line: String,
        clipStartSec: Double,
        clipDuration: Double
    ) -> (start: Double, text: String)? {
        let pattern = #"^\s*\[?(\d{1,2}:\d{2}(?::\d{2})?)\]?\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let timeRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line)
        else { return nil }

        let absolute = ShortsPlanner.parseTimestampToSeconds(String(line[timeRange]))
        let local = min(max(0, absolute - clipStartSec), clipDuration)
        let text = String(line[textRange])
        return (local, text)
    }

    private static func stableSuffix(_ text: String) -> String {
        let cleaned = text
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(8)
        let suffix = String(String.UnicodeScalarView(cleaned))
        return suffix.isEmpty ? "empty" : suffix
    }
}
