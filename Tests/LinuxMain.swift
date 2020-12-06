import XCTest

import DotEnvTests

var tests = [XCTestCaseEntry]()
tests += DotEnvTests.allTests()
XCTMain(tests)
