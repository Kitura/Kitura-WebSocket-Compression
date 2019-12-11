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

/// A general deflater used by the WebSocket protocol
public protocol Deflater {
    /// Is the compression context saved and carried over to subsequent compression operations?
    var noContextTakeOver: Bool { get }

    /// If compression context is saved, how long is the compression history window?
    var maxWindowBits: Int32 { get }

    /// Indicates if the deflater is initialized 
    var initialized: Bool { get set }

    /// Deflate data in the input ByteBuffer and return the compressed data in a new ByteBuffer
    func deflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, dropFourTrailingOctets: Bool) -> ByteBuffer

    /// Free the compression stream state
    func end()
}

/// A general inflater used by the WebSocket protocol
public protocol Inflater {
    /// Is the compression context saved and carried over to subsequent compression operations?
    var noContextTakeOver: Bool { get }

    /// If compression context is saved, how long is the compression history window?
    var maxWindowBits: Int32 { get }

    /// Indicates if the inflater is initialized 
    var initialized: Bool { get set }

    /// Inflate data in the input ByteBuffer and return the decompressed data in a new ByteBuffer
    func inflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator) -> ByteBuffer

    /// Free the decompression stream state
    func end()
}
