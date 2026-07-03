import AVFoundation
import CoreMedia
import Foundation
import VaniScriptCore

enum AudioSampleBufferLevels {
    static func levels(from sampleBuffer: CMSampleBuffer, bandCount: Int = AudioSpectrumAnalyzer.defaultBandCount) -> [Double]? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let asbd = streamDescription.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM else { return nil }

        var bufferListSize = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, bufferListSize > 0 else { return nil }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.assumingMemoryBound(to: AudioBufferList.self)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let samples = pcmSamples(from: audioBufferList, streamDescription: asbd)
        guard !samples.isEmpty else { return nil }

        return AudioSpectrumAnalyzer.frequencyBands(
            samples: samples,
            sampleRate: asbd.mSampleRate,
            bandCount: bandCount
        )
    }

    private static func pcmSamples(
        from audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> [Float] {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let flags = streamDescription.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        var samples: [Float] = []

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)
            if isFloat, bitsPerChannel == 32 {
                let count = byteCount / MemoryLayout<Float>.stride
                let pointer = data.assumingMemoryBound(to: Float.self)
                samples.reserveCapacity(samples.count + count)
                for index in 0..<count {
                    samples.append(pointer[index])
                }
            } else if isFloat, bitsPerChannel == 64 {
                let count = byteCount / MemoryLayout<Double>.stride
                let pointer = data.assumingMemoryBound(to: Double.self)
                samples.reserveCapacity(samples.count + count)
                for index in 0..<count {
                    samples.append(Float(max(-1, min(1, pointer[index]))))
                }
            } else if isSignedInteger, bitsPerChannel == 16 {
                let count = byteCount / MemoryLayout<Int16>.stride
                let pointer = data.assumingMemoryBound(to: Int16.self)
                samples.reserveCapacity(samples.count + count)
                for index in 0..<count {
                    samples.append(Float(pointer[index]) / Float(Int16.max))
                }
            } else if isSignedInteger, bitsPerChannel == 32 {
                let count = byteCount / MemoryLayout<Int32>.stride
                let pointer = data.assumingMemoryBound(to: Int32.self)
                samples.reserveCapacity(samples.count + count)
                for index in 0..<count {
                    samples.append(Float(pointer[index]) / Float(Int32.max))
                }
            }
        }

        return samples
    }
}
