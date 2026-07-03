public enum ChunkPlanner {
    public static func plan(
        sourcePath: String,
        durationSec: Double,
        chunkDurationMin: Int
    ) -> [ChunkData] {
        let safeDuration = max(0, durationSec)
        let chunkDuration = max(60, Double(max(1, chunkDurationMin)) * 60)
        guard safeDuration > 0 else {
            return [
                makeChunk(
                    index: 0,
                    sourcePath: sourcePath,
                    startSec: 0,
                    endSec: 0
                ),
            ]
        }

        var cutPoints: [Double] = []
        var cursor = chunkDuration
        while cursor < safeDuration {
            cutPoints.append(cursor)
            cursor += chunkDuration
        }

        return plan(sourcePath: sourcePath, durationSec: safeDuration, cutPointsSec: cutPoints)
    }

    public static func plan(
        sourcePath: String,
        durationSec: Double,
        cutPointsSec: [Double]
    ) -> [ChunkData] {
        let safeDuration = max(0, durationSec)
        guard safeDuration > 0 else {
            return [
                makeChunk(
                    index: 0,
                    sourcePath: sourcePath,
                    startSec: 0,
                    endSec: 0
                ),
            ]
        }

        var cleaned: [Double] = []
        for cut in cutPointsSec.sorted() {
            guard cut > 0, cut < safeDuration else { continue }
            guard let previous = cleaned.last else {
                cleaned.append(cut)
                continue
            }
            if cut - previous >= 0.1 {
                cleaned.append(cut)
            }
        }

        let bounds = [0] + cleaned + [safeDuration]
        return (0..<(bounds.count - 1)).map { index in
            makeChunk(
                index: index,
                sourcePath: sourcePath,
                startSec: bounds[index],
                endSec: bounds[index + 1]
            )
        }
    }

    private static func makeChunk(
        index: Int,
        sourcePath: String,
        startSec: Double,
        endSec: Double
    ) -> ChunkData {
        ChunkData(
            index: index,
            filePath: sourcePath,
            durationSec: max(0, endSec - startSec),
            startSec: startSec,
            endSec: endSec,
            original: "",
            translated: "",
            originalFormats: nil,
            translatedFormats: nil,
            unrecognizedFragments: [],
            status: .pending,
            approved: false
        )
    }
}
