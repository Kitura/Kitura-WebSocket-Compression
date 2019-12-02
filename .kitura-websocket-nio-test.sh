# Run Kitura-WebSocket-Compression tests
travis_start "swift_test"
echo ">> Executing Kitura-WebSocket-Compression tests"
swift test
SWIFT_TEST_STATUS=$?
travis_end
if [ $SWIFT_TEST_STATUS -ne 0 ]; then
  echo ">> swift test command exited with $SWIFT_TEST_STATUS"
  # Return a non-zero status so that Package-Builder will generate a backtrace
  return $SWIFT_TEST_STATUS
fi

# Clone Kitura-WebSocket-NIO
set -e
echo ">> Building Kitura"
travis_start "swift_build_kitura_websocket"
cd .. && git clone https://github.com/IBM-Swift/Kitura-WebSocket-NIO && cd Kitura-WebSocket-NIO

# Set KITURA_NIO
export KITURA_NIO=1

# Build once
swift build

# Edit package Kitura-WebSocket-Compression to point to the current branch
echo ">> Editing Kitura package to use latest Kitura-WebSocket-Compression"
swift package edit Kitura-WebSocket-Compression --path ../Kitura-WebSocket-Compression
travis_end
set +e

# Run Kitura tests
travis_start "swift_test_kitura_websocket"
echo ">> Executing Kitura-WebSocket-NIO tests"
swift test
SWIFT_TEST_STATUS=$?
travis_end
if [ $SWIFT_TEST_STATUS -ne 0 ]; then
  echo ">> swift test command exited with $SWIFT_TEST_STATUS"
  # Return a non-zero status so that Package-Builder will generate a backtrace
  return $SWIFT_TEST_STATUS
fi

# Move back to the original build directory. This is needed on macOS builds for the subsequent swiftlint step.
cd ../Kitura-WebSocket-Compression
