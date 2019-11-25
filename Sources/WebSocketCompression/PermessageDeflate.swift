/*
* Copyright IBM Corporation 2019
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import NIO
import NIOWebSocket
import CZlib

// Implementation of a deflater using zlib. This class acts like an interceptor, consuming original frames from
// WebSocketCompressor, compressing the payload and returning it back to WebSocketCompressor.

public class PermessageDeflateCompressor: Deflater {

    public var noContextTakeOver: Bool
    public var maxWindowBits: Int32

    public init(noContextTakeOver: Bool = false, maxWindowBits: Int32 = 15) {
        self.noContextTakeOver = noContextTakeOver
        self.maxWindowBits = maxWindowBits
    }

    // The zlib stream
    public var stream: z_stream = z_stream()

    // Initialize the z_stream only once if context takeover is enabled
    public var streamInitialized = false

    public func deflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, dropFourTrailingOctets: Bool = false) -> ByteBuffer {
        // Initialize the deflater as per https://www.zlib.net/zlib_how.html
        if noContextTakeOver || streamInitialized == false {
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = nil
            stream.avail_in = 0
            // The zlib manual asks us to provide a negative windowBits value for raw deflate
            let rc = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -self.maxWindowBits, 8,
                                   Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")
            self.streamInitialized = true
        }

        defer {
            if noContextTakeOver {
                // We aren't doing a context takeover.
                // This means the deflater is to be used on a per-message basis.
                // So, we deinitialize the deflater before returning.
                deflateEnd(&stream)
            }
        }

        // Deflate/compress the payload
        return compressPayload(in: buffer, allocator: allocator, flag: Z_SYNC_FLUSH, dropFourTrailingOctets: dropFourTrailingOctets)
    }

    private func compressPayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, flag: Int32, dropFourTrailingOctets: Bool = false) -> ByteBuffer {
        var inputBuffer = buffer
        guard inputBuffer.readableBytes > 0 else {
            //TODO: Log an error message
            return inputBuffer
        }

        // Allocate an output buffer, with a size hint equal to the input (there's no other derivable value for this)
        let bufferSize = Int(deflateBound(&stream, UInt(inputBuffer.readableBytes)))
        var outputBuffer = allocator.buffer(capacity: bufferSize)

        // Compress the payload
        stream._deflate(from: &inputBuffer, to: &outputBuffer, flag: flag)

        // Make sure all of inputBuffer was read, and outputBuffer isn't empty
        precondition(inputBuffer.readableBytes == 0)
        precondition(outputBuffer.readableBytes > 0)

        // Ignore the 0, 0, 0xff, 0xff trailer added by zlib
        if dropFourTrailingOctets {
            outputBuffer = outputBuffer.getSlice(at: 0, length: outputBuffer.readableBytes-4) ?? outputBuffer
        }

        return outputBuffer
    }
}

// Implementation of a deflater using zlib. This class acts like an interceptor, consuming original frames from
// WebSocketDeCompressor, compressing the payload and returning it back to WebSocketDeCompressor.

public class PermessageDeflateDecompressor: Inflater {
    public var noContextTakeOver: Bool
    public var maxWindowBits:  Int32

    // The zlib stream
    public var stream: z_stream = z_stream()

    public var streamInitialized = false

    public init (noContextTakeOver: Bool = false, maxWindowBits: Int32 = 15) {
        self.noContextTakeOver = noContextTakeOver
        self.maxWindowBits = maxWindowBits
    }

    public func inflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator) -> ByteBuffer {
        // Initialize the inflater as per https://www.zlib.net/zlib_how.html
        if noContextTakeOver || streamInitialized == false {
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.avail_in = 0
            stream.next_in = nil
            let rc = inflateInit2_(&stream, -self.maxWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")
            self.streamInitialized = true
        }

        defer {
            if noContextTakeOver {
                // Deinitialize before returning
                inflateEnd(&stream)
            }
        }

        // Inflate/decompress the payload
        return decompressPayload(in: buffer, allocator: allocator, flag: Z_SYNC_FLUSH)
    }

    func decompressPayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, flag: Int32) -> ByteBuffer {
        var inputBuffer = buffer
        guard inputBuffer.readableBytes > 0 else {
            // TODO: Log an error
            return buffer
        }
        let payloadSize =  inputBuffer.readableBytes
        var outputBuffer = allocator.buffer(capacity: 2) // starting with a small capacity hint

        // Decompression may happen in steps, we'd need to continue calling inflate() until there's no available input
        repeat {
            var partialOutputBuffer = allocator.buffer(capacity: inputBuffer.readableBytes)
            stream._inflate(from: &inputBuffer, to: &partialOutputBuffer, flag: flag)
            // calculate the number of bytes processed
            let processedBytes = payloadSize - Int(stream.avail_in)
            // move the reader index
            inputBuffer.moveReaderIndex(to: processedBytes)
            // append partial output to the ouput buffer
            outputBuffer.writeBuffer(&partialOutputBuffer)
        } while stream.avail_in > 0
        return outputBuffer
    }
}

// This code is borrowed from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
private extension z_stream {
    // Executes deflate from one buffer to another buffer. The advantage of this method is that it
    // will ensure that the stream is "safe" after each call (that is, that the stream does not have
    // pointers to byte buffers any longer).
    mutating func _deflate(from: inout ByteBuffer, to: inout ByteBuffer, flag: Int32) {
        defer {
            // Per https://www.zlib.net/zlib_how.html
            self.avail_in = 0
            self.next_in = nil
            self.avail_out = 0
            self.next_out = nil
        }

        from.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr,
                                                          count: dataPtr.count)

            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!

            let rc = deflateToBuffer(buffer: &to, flag: flag)
            precondition(rc == Z_OK || rc == Z_STREAM_END, "Deflate failed: \(rc)")

            return typedDataPtr.count - Int(self.avail_in)
        }
    }

    // A private function that sets the deflate target buffer and then calls deflate.
    // This relies on having the input set by the previous caller: it will use whatever input was
    // configured.
    private mutating func deflateToBuffer(buffer: inout ByteBuffer, flag: Int32) -> Int32 {
        var rc = Z_OK

        buffer.writeWithUnsafeMutableBytes { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                            count: outputPtr.count)
            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!
            rc = deflate(&self, flag)
            return typedOutputPtr.count - Int(self.avail_out)
        }

        return rc
    }
}

// This code is derived from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
extension z_stream {
    // Executes inflate from one buffer to another buffer.
    mutating func _inflate(from: inout ByteBuffer, to: inout ByteBuffer, flag: Int32) {
        from.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr, count: dataPtr.count)
            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!
            let rc = inflateToBuffer(buffer: &to, flag: flag)
            precondition(rc == Z_OK || rc == Z_STREAM_END, "Decompression failed: \(rc)")
            if rc == Z_STREAM_END {
                inflateEnd(&self)
            }
            return typedDataPtr.count - Int(self.avail_in)
        }
    }

    // A private function that sets the inflate target buffer and then calls inflate.
    // This relies on having the input set by the previous caller: it will use whatever input was
    // configured.
    private mutating func inflateToBuffer(buffer: inout ByteBuffer, flag: Int32) -> Int32 {
        var rc = Z_OK

        buffer.writeWithUnsafeMutableBytes { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                            count: outputPtr.count)
            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!
            rc = inflate(&self, flag)
            return typedOutputPtr.count - Int(self.avail_out)
        }
        return rc
    }
}
