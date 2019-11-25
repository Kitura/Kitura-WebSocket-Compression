import XCTest

import WebSocketCompressionTests

var tests = [XCTestCaseEntry]()
tests += WebSocketCompressionTests.allTests()
XCTMain(tests)
