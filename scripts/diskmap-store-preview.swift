// Convert the existing 34-second showreel to an App Store preview, retaining
// the entire story and soundtrack. Native AVFoundation preserves audio pitch.
// make diskmap-store-preview
import Foundation
import AVFoundation

let source = URL(fileURLWithPath: "build/Diskmap-Showreel.mov")
let output = URL(fileURLWithPath: "apps/diskmap/store-assets/en/previews/Diskmap-AppStore-Preview.mov")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let asset = AVURLAsset(url: source)
let originalDuration = try await asset.load(.duration)
let duration = CMTime(seconds: 29.9, preferredTimescale: 600)
let composition = AVMutableComposition()
let sourceTracks = try await asset.load(.tracks)
for track in sourceTracks {
	let destination = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)!
	try destination.insertTimeRange(CMTimeRange(start: .zero, duration: originalDuration), of: track, at: .zero)
	destination.preferredTransform = try await track.load(.preferredTransform)
}
composition.scaleTimeRange(CMTimeRange(start: .zero, duration: originalDuration), toDuration: duration)

let videoTrack = composition.tracks(withMediaType: .video).first!
let layer = AVVideoCompositionLayerInstruction(configuration: .init(trackID: videoTrack.trackID))
let instruction = AVVideoCompositionInstruction(configuration: .init(
	layerInstructions: [layer], timeRange: CMTimeRange(start: .zero, duration: duration)))
let video = AVVideoComposition(configuration: .init(
	frameDuration: CMTime(value: 1, timescale: 30), instructions: [instruction],
	renderSize: CGSize(width: 1920, height: 1080)))

let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080)!
exporter.videoComposition = video
exporter.audioTimePitchAlgorithm = .spectral
exporter.shouldOptimizeForNetworkUse = true
if FileManager.default.fileExists(atPath: output.path) {
	try FileManager.default.removeItem(at: output)
}
try await exporter.export(to: output, as: .mov)
let result = AVURLAsset(url: output)
let exportedDuration = try await result.load(.duration)
let tracks = try await result.load(.tracks)
print("Exported \(output.path), duration \(CMTimeGetSeconds(exportedDuration)) seconds")
for track in tracks {
	let values = try await track.load(.naturalSize, .nominalFrameRate, .estimatedDataRate)
	print("\(track.mediaType.rawValue): \(values.0), \(values.1) fps, \(values.2) bps")
}
