import Foundation
import Darwin

@main
struct Benchmark {
    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    static func floats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
    }
    static func main() async throws {
        guard CommandLine.arguments.count >= 3 else { fatalError("benchmark <assets> <report.json> [hashes.json] [model name]") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let clock = ContinuousClock(), started = clock.now
        var hashes = [
            "main.mlirb": "bee41aeed2beefaa413bc1531f7dd3aa787655f8053364617fbce76a378e487f"
        ]
        if CommandLine.arguments.count > 3 {
            hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf:
                URL(fileURLWithPath: CommandLine.arguments[3])))
        }
        let name = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "mbr_full_fp16.aimodel"
        let separator = try await SGStemSeparator(modelURL: root.appendingPathComponent(name), payloadHashes: hashes)
        let load = seconds(clock.now - started)
        let samples = separator.chunkSamples
        let raw = try floats(root.appendingPathComponent("golden_raw.f32"))
        let golden = try floats(root.appendingPathComponent("golden_vocals.f32"))
        guard raw.count == 2 * samples, golden.count == raw.count else { fatalError("wrong golden shape") }
        var input = [Float](repeating: 0, count: raw.count)
        for n in 0..<samples { input[n * 2] = raw[n]; input[n * 2 + 1] = raw[n + samples] }
        var times: [Double] = [], cosine = 0.0, rmsRatio = 0.0
        for run in 0..<4 {
            let start = clock.now
            let vocals = try await separator.vocals(for: input)
            times.append(seconds(clock.now - start))
            var dot = 0.0, aa = 0.0, bb = 0.0
            for n in 0..<samples {
                for c in 0..<2 {
                    let a = Double(vocals[n * 2 + c]), b = Double(golden[c * samples + n])
                    dot += a * b; aa += a * a; bb += b * b
                }
            }
            cosine = dot / sqrt(aa * bb); rmsRatio = sqrt(aa / bb)
            print("run \(run): \(times.last!) s, cosine \(cosine), rms ratio \(rmsRatio)")
            guard cosine >= 0.999, abs(rmsRatio - 1) < 0.01 else { fatalError("golden parity failed") }
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let warm = times.dropFirst().max()!
        let collect = Double(samples) / 44100
        let report: [String: Any] = [
            "platform": "macOS", "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "chunkSamples": samples, "chunkSeconds": collect, "loadSeconds": load,
            "inferenceSeconds": times, "cosine": cosine, "rmsRatio": rmsRatio,
            "peakResidentBytes": usage.ru_maxrss,
            "causalActivationLowerBoundSeconds": collect + warm,
            "meetsThreeSecondActivation": collect + warm <= 3,
            "liveValidated": false
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        try json.write(to: destination)
        print(String(decoding: json, as: UTF8.self))
    }
}
