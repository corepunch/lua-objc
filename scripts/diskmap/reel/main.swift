// Diskmap showreel: 30 s, 1920×1080, 30 fps, H.264 + AAC 256 kbps.
// Each frame averages several sub-frame renders for real motion blur.
//
//   diskmap-reel render <captures dir> <out.mov>
//   diskmap-reel stills <captures dir> <out dir> <t1,t2,…>
//   diskmap-reel import <screenshot.png> <out.jpg> <light|dark>
import AppKit
import AVFoundation

let PW = 1920, PH = 1080
let FPS: Int32 = 30
let DURATION = 30.0
let FRAMES = Int(DURATION * Double(FPS))
let SR = 48000.0
let SUBFRAMES = 5
let SHUTTER = 0.5 / Double(FPS) // 180° shutter

func fail(_ message: String) -> Never {
	FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
	exit(1)
}

let args = CommandLine.arguments
guard args.count >= 4 else { fail("usage: diskmap-reel render|stills|import …") }

// MARK: - Import: window-only JPEG from a `--screenshot` capture

// `--screenshot` saves the window with its shadow. Keep the opaque window
// rectangle, flatten the rounded corners onto a neutral colour for the
// appearance (the renderer clips them again) and store it as JPEG.
func importCapture(_ input: String, _ output: String, dark: Bool) {
	guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
		  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("cannot read \(input)") }
	let w = img.width, h = img.height
	let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: SRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
	ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
	let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
	var minX = w, minY = h, maxX = 0, maxY = 0
	for y in 0..<h { for x in 0..<w where p[(y * w + x) * 4 + 3] > 250 {
		minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
	} }
	let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
	guard rect.width == 2880 && rect.height == 1800 else { fail("\(input): expected a 1440×900 pt window at 2×, found \(rect)") }
	let window = img.cropping(to: rect)!
	let flat = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0, space: SRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
	flat.setFillColor(dark ? CGColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1) : CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1))
	flat.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
	flat.draw(window, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
	guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.jpeg" as CFString, 1, nil) else { fail("cannot write \(output)") }
	CGImageDestinationAddImage(dest, flat.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
	CGImageDestinationFinalize(dest)
}

if args[1] == "import" {
	importCapture(args[2], args[3], dark: args.count > 4 && args[4] == "dark")
	exit(0)
}

capturesDir = args[2]

// MARK: - Rendering with motion blur

func makeContext(_ data: UnsafeMutableRawPointer?, bytesPerRow: Int) -> CGContext {
	let ctx = CGContext(data: data, width: PW, height: PH, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: SRGB,
						bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
	ctx.translateBy(x: 0, y: CGFloat(PH))
	ctx.scaleBy(x: 1, y: -1)
	return ctx
}

let scratchRow = PW * 4
let scratch = UnsafeMutableRawPointer.allocate(byteCount: scratchRow * PH, alignment: 64)
let accumulator = UnsafeMutablePointer<UInt16>.allocate(capacity: scratchRow * PH)

// Renders time `t` with motion blur into `dest`.
func renderBlurred(_ t: Double, into dest: UnsafeMutableRawPointer, bytesPerRow: Int) {
	accumulator.initialize(repeating: 0, count: scratchRow * PH)
	for s in 0..<SUBFRAMES {
		let st = t + (Double(s) / Double(SUBFRAMES - 1) - 0.5) * SHUTTER
		autoreleasepool { render(makeContext(scratch, bytesPerRow: scratchRow), max(0, st)) }
		let src = scratch.assumingMemoryBound(to: UInt8.self)
		for i in 0..<(scratchRow * PH) { accumulator[i] &+= UInt16(src[i]) }
	}
	let n = UInt16(SUBFRAMES)
	for y in 0..<PH {
		let row = dest.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
		let acc = accumulator.advanced(by: y * scratchRow)
		for x in 0..<scratchRow { row[x] = UInt8((acc[x] + n / 2) / n) }
	}
}

if args[1] == "stills" {
	guard args.count >= 5 else { fail("usage: diskmap-reel stills <captures> <out dir> <t1,t2,…>") }
	for t in args[4].split(separator: ",").compactMap({ Double($0) }) {
		let ctx = makeContext(nil, bytesPerRow: 0)
		renderBlurred(t, into: ctx.data!, bytesPerRow: ctx.bytesPerRow)
		let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(args[3])/still-\(String(format: "%05.2f", t)).png") as CFURL, "public.png" as CFString, 1, nil)!
		CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
		CGImageDestinationFinalize(dest)
	}
	exit(0)
}

guard args[1] == "render" else { fail("unknown mode \(args[1])") }
let outPath = args[3]

// MARK: - Music

let (left, right) = synthesize(duration: DURATION, sr: SR)
let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("diskmap-reel-\(getpid()).wav")
do {
	let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
	let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)
	let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))!
	buffer.frameLength = AVAudioFrameCount(left.count)
	left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: left.count) }
	right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: right.count) }
	try file.write(from: buffer)
} catch { fail("cannot write the music: \(error)") }
defer { try? FileManager.default.removeItem(at: wavURL) }

// MARK: - Encoding

let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mov)
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
	AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: PW, AVVideoHeightKey: PH,
	AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
								AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
								AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
	AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
									  AVVideoMaxKeyFrameIntervalKey: 30, AVVideoExpectedSourceFrameRateKey: 30],
])
videoInput.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
	kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: PW, kCVPixelBufferHeightKey as String: PH,
])
let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
	AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: SR, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000,
])
audioInput.expectsMediaDataInRealTime = false
writer.add(videoInput)
writer.add(audioInput)

let wavAsset = AVURLAsset(url: wavURL)
let reader = try! AVAssetReader(asset: wavAsset)
let semaphore = DispatchSemaphore(value: 0)
var audioTrack: AVAssetTrack!
wavAsset.loadTracks(withMediaType: .audio) { tracks, _ in audioTrack = tracks!.first!; semaphore.signal() }
semaphore.wait()
let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
	AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
	AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: SR, AVNumberOfChannelsKey: 2,
])
reader.add(readerOutput)
reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)

// Frames render on the main thread (AppKit draws the SF Symbols); audio is
// fed whenever the writer asks, so the two tracks interleave.
var audioDone = false
func feedAudio() {
	while !audioDone && audioInput.isReadyForMoreMediaData {
		if let sample = readerOutput.copyNextSampleBuffer() { audioInput.append(sample) } else { audioInput.markAsFinished(); audioDone = true }
	}
}
let started = Date()
for frame in 0..<FRAMES {
	while !videoInput.isReadyForMoreMediaData { feedAudio(); usleep(2000) }
	var pixelBuffer: CVPixelBuffer?
	CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
	let pb = pixelBuffer!
	CVPixelBufferLockBaseAddress(pb, [])
	renderBlurred(Double(frame) / Double(FPS), into: CVPixelBufferGetBaseAddress(pb)!, bytesPerRow: CVPixelBufferGetBytesPerRow(pb))
	CVPixelBufferUnlockBaseAddress(pb, [])
	adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: FPS))
	feedAudio()
	if frame % 90 == 0 { print("frame \(frame)/\(FRAMES) \(Int(Date().timeIntervalSince(started)))s") }
}
videoInput.markAsFinished()
while !audioDone { feedAudio(); usleep(2000) }
writer.endSession(atSourceTime: CMTime(value: CMTimeValue(FRAMES), timescale: FPS))
writer.finishWriting { semaphore.signal() }
semaphore.wait()
if writer.status != .completed { fail("encoding failed: \(String(describing: writer.error))") }
print("wrote \(outPath)")
