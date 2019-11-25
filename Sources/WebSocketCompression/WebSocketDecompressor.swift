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
import CZlib
import NIOWebSocket

// Implementation of `WebSocketDecompressor` a `ChannelInboundHandler` that intercepts incoming WebSocket frames, inflating the payload and
// writing the new frames back to the channel, to be eventually received by WebSocketConnection.

// Some parts of this code are derived from swift-nio: https://github.com/apple/swift-nio/blob/master/Sources/NIOHTTP1/HTTPResponseCompressor.swift
public class WebSocketDecompressor : ChannelInboundHandler {
    public typealias InboundIn = WebSocketFrame 
    public typealias InboundOut = WebSocketFrame

    public init(inflater: Inflater) {
        self.inflater = inflater
    }

    public var inflater: Inflater
    // A buffer to accumulate payload across multiple frames
    var payload: ByteBuffer?

    // Is this a text or binary message? Continuation frames don't have this information.
    private var messageType: WebSocketOpcode?

    // The default LZ77 window size; 15
    var maxWindowBits = MAX_WBITS

    // A message may span multiple frames. Only the first frame (text/binary) may indicate compression.
    // This flag is used to tell the decompressor if a continuation frame belongs to a compressed message.
    private var receivingCompressedMessage = false

    // PermessageDeflateDecompressor is a `ChannelInboundHandler`, this function gets called when the previous inbound handler fires a channel read event.
    // Here, we intercept incoming compressed frames, decompress the payload across multiple continuation frame and write a fire a channel read event
    // with the entire frame data decompressed.
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        // We should either have a data frame with rsv1 set, or a continuation frame of a compressed message. There's nothing to do otherwise.
        guard frame.isCompressedDataFrame || (frame.isContinuationFrame && self.receivingCompressedMessage) else {
            // If we are using context takeover, this is a good time to free the zstream!
            if inflater.streamInitialized && frame.opcode == .connectionClose && !inflater.noContextTakeOver {
                deflateEnd(&inflater.stream)
                inflater.streamInitialized = false
            }

            context.fireChannelRead(self.wrapInboundOut(frame))
            return
        }

        // If this is a continuation frame, have the payload appended to `payload`, else set `payload` and store the messageType
        var receivedPayload = frame.unmaskedData
        if frame.opcode == .continuation {
            self.payload?.writeBuffer(&receivedPayload)
        } else {
            self.messageType = frame.opcode
            self.payload = receivedPayload
            self.receivingCompressedMessage = true
        }

        // If the current frame isn't a final frame of a message or if `payload` still empty, there's nothing to do.
        guard frame.fin, var inputBuffer = self.payload else { return }

        // We've received all frames pertaining to the message. Reset the compressedMessage flag.
        self.receivingCompressedMessage = false

        // Append the trailer 0, 0, ff, ff before decompressing
        inputBuffer.writeBytes([0x00, 0x00, 0xff, 0xff])

        var inflatedPayload = inflater.inflatePayload(in: inputBuffer, allocator: context.channel.allocator)

        // Apply the WebSocket mask on the inflated payload
        if let maskKey = frame.maskKey {
            inflatedPayload.webSocketMask(maskKey)
        }

        // Create a new frame with the inflated payload and pass it on to the next inbound handler, mostly WebSocketConnection
        let inflatedFrame = WebSocketFrame(fin: true, rsv1: false, opcode: self.messageType!, maskKey: frame.maskKey, data: inflatedPayload)
        context.fireChannelRead(self.wrapInboundOut(inflatedFrame))
    }

}

extension WebSocketFrame {
    var isDataFrame: Bool {
        return self.opcode == .text || self.opcode == .binary
    }

    var isCompressedDataFrame: Bool {
        return self.isDataFrame && self.rsv1 == true
    }

    var isContinuationFrame: Bool {
        return self.opcode == .continuation
    }
}
