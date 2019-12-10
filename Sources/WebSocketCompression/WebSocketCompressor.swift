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

// Implementation of a deflater using zlib. This ChannelOutboundHandler acts like an interceptor, consuming original frames written by
// WebSocketConnection, compressing the payload and writing the new frames with a compressed payload onto the channel.

// Some of the code here is borrowed from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
public class WebSocketCompressor : ChannelOutboundHandler {
    public typealias OutboundIn = WebSocketFrame 
    public typealias OutboundOut = WebSocketFrame 

    public init(deflater: Deflater) {
        self.deflater = deflater
    }

    // The default LZ77 window value; 15
    var maxWindowBits = MAX_WBITS

    var deflater: Deflater
    // A buffer that accumulates payload data across multiple frames
    var payload: ByteBuffer?

    private var messageType: WebSocketOpcode?

    // PermessageDeflateCompressor is an outbound handler, this function gets called when a frame is written to the channel by WebSocketConnection.
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var frame = unwrapOutboundIn(data)

        // If this is a control frame, do not attempt compression.
        guard frame.isDataFrame || frame.isContinuationFrame else {
             context.writeAndFlush(self.wrapOutboundOut(frame)).whenComplete { _ in
                 promise?.succeed(())
             }
             return
        }

        // If this is a continuation frame, have the frame data appended to `payload`, else set payload to frame data.
        if frame.opcode == .continuation {
            self.payload?.writeBuffer(&frame.data)
        } else {
            self.payload = frame.data
            self.messageType = frame.opcode
        }

        // If the current frame isn't the final frame or if payload is empty, there's nothing to do.
        guard frame.fin, let payload = payload else { return }

        // Compress the payload
        let deflatedPayload = deflater.deflatePayload(in: payload, allocator: context.channel.allocator, dropFourTrailingOctets: true)

        // Create a new frame with the compressed payload, the rsv1 bit must be set to indicate compression
        let deflatedFrame = WebSocketFrame(fin: frame.fin, rsv1: true, opcode: self.messageType!, maskKey: frame.maskKey, data: deflatedPayload)

        // Write the new frame onto the pipeline
        _ = context.writeAndFlush(self.wrapOutboundOut(deflatedFrame))
    }

    public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        // PermessageDeflateCompressor is an outbound handler. If the underlying
        // WebSocketConnection decides to close the connection, the close message
        // needs to be intercepted and the deflater closed while we're using context takeover.
        if deflater.noContextTakeOver == false {
            deflater.end()
        }
        context.close(mode: mode, promise: promise)
    }
}


