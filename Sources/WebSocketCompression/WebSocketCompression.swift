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

// Protocol for Deflater

public protocol Deflater {
    var noContextTakeOver: Bool { get }
    var maxWindowBits: Int32 { get }

    // The zlib stream
    var stream: z_stream { get set }

    // Initialize the z_stream only once if context takeover is enabled
    var streamInitialized: Bool { get set }

    func deflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator, dropFourTrailingOctets: Bool) -> ByteBuffer

}

// Protocol for Deflater

public protocol Inflater {
    var noContextTakeOver: Bool { get }
    var maxWindowBits: Int32 { get }

    // The zlib stream
    var stream: z_stream { get set }

    // Initialize the z_stream only once if context takeover is enabled
    var streamInitialized: Bool { get set }

    func inflatePayload(in buffer: ByteBuffer, allocator: ByteBufferAllocator) -> ByteBuffer

}
