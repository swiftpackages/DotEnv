import XCTest
import NIO
@testable import DotEnv

final class DotEnvTests: XCTestCase {
    func testByteArrayParser() {
        var parser = ByteArrayParser(source: testBytes)
        let lines = parser.parse()
        XCTAssertEqual(lines, testValues)
    }

    func testStringParser() {
        let test = try! String(contentsOfFile: filePath)
        var parser = StringParser(source: test)
        let lines = parser.parse()
        XCTAssertEqual(lines, testValues)
    }

    func testByteBufferParser() {
        let buffer = ByteBufferAllocator().buffer(bytes: testBytes)
        var parser = ByteBufferParser(source: buffer)
        let lines = parser.parse()
        XCTAssertEqual(lines, testValues)
    }

    func testStringDotEnv() {
        let env = DotEnv.read(path: filePath)
        env.load(overwrite: true)
        for line in testValues {
            XCTAssertEqual(ProcessInfo.processInfo.environment[line.key], line.value )
        }
    }

    func testByteBufferDotEnv() throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let pool = NIOThreadPool(numberOfThreads: 1)
        pool.start()
        let fileio = NonBlockingFileIO(threadPool: pool)
        let file = try DotEnv.read(path: filePath, fileio: fileio, on: elg.next()).wait()
        file.load(overwrite: true)
        for line in testValues {
            XCTAssertEqual(ProcessInfo.processInfo.environment[line.key], line.value )
        }
        try pool.syncShutdownGracefully()
        try elg.syncShutdownGracefully()
    }

    func testNoTrailingNewlineByteBuffer() throws {
        let env = "FOO=bar\nBAR=baz"
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(env)
        var parser = ByteBufferParser(source: buffer)
        let lines = parser.parse()
        XCTAssertEqual(lines, [
            .init(key: "FOO", value: "bar"),
            .init(key: "BAR", value: "baz"),
        ])
    }

    func testNoTrailingNewlineString() throws {
        let env = "FOO=bar\nBAR=baz"
        var parser = StringParser(source: env)
        let lines = parser.parse()
        XCTAssertEqual(lines, [
            .init(key: "FOO", value: "bar"),
            .init(key: "BAR", value: "baz"),
        ])
    }

    func testNoTrailingNewlineByteArray() throws {
        let env: [UInt8] = [0x46,0x4f,0x4f,0x3d,0x62,0x61,0x72,0x0a,0x42,0x41,0x52,0x3d,0x62,0x61,0x7a]
        var parser = ByteArrayParser(source: env)
        let lines = parser.parse()
        XCTAssertEqual(lines, [
            .init(key: "FOO", value: "bar"),
            .init(key: "BAR", value: "baz"),
        ])
    }

    let filePath = "Tests/DotEnvTests/Resources/env.test"

    let testValues: [Line] = [
        .init(key: "NODE_ENV",                       value: "development"),
        .init(key: "BASIC",                          value: "basic"),
        .init(key: "AFTER_LINE",                     value: "after_line"),
        .init(key: "UNDEFINED_EXPAND",               value: "$TOTALLY_UNDEFINED_ENV_KEY"),
        .init(key: "EMPTY",                          value: ""),
        .init(key: "SINGLE_QUOTES",                  value: "single_quotes"),
        .init(key: "DOUBLE_QUOTES",                  value: "double_quotes"),
        .init(key: "EXPAND_NEWLINES",                value: "expand\nnewlines"),
        .init(key: "DONT_EXPAND_NEWLINES_1",         value: "dontexpand\\nnewlines"),
        .init(key: "DONT_EXPAND_NEWLINES_2",         value: "dontexpand\\nnewlines"),
        .init(key: "EQUAL_SIGNS",                    value: "equals=="),
        .init(key: "RETAIN_INNER_QUOTES",            value: "{\"foo\": \"bar\"}"),
        .init(key: "RETAIN_INNER_QUOTES_AS_STRING",  value: "{\"foo\": \"bar\"}"),
        .init(key: "INCLUDE_SPACE",                  value: "some spaced out string"),
        .init(key: "USERNAME",                       value: "therealnerdybeast@example.tld"),
    ]

    let testBytes: [UInt8] = [0x23,0x20,0x53,0x6f,0x75,0x72,0x63,0x65,0x3a,0x20,0x68,0x74,0x74,0x70,0x73,0x3a,0x2f,0x2f,0x67,0x69,0x74,0x68,0x75,0x62,0x2e,0x63,0x6f,0x6d,0x2f,0x6d,0x6f,0x74,0x64,0x6f,0x74,0x6c,0x61,0x2f,0x64,0x6f,0x74,0x65,0x6e,0x76,0x2f,0x62,0x6c,0x6f,0x62,0x2f,0x6d,0x61,0x73,0x74,0x65,0x72,0x2f,0x74,0x65,0x73,0x74,0x73,0x2f,0x2e,0x65,0x6e,0x76,0x0a,0x4e,0x4f,0x44,0x45,0x5f,0x45,0x4e,0x56,0x3d,0x64,0x65,0x76,0x65,0x6c,0x6f,0x70,0x6d,0x65,0x6e,0x74,0x0a,0x42,0x41,0x53,0x49,0x43,0x3d,0x62,0x61,0x73,0x69,0x63,0x0a,0x0a,0x23,0x20,0x70,0x72,0x65,0x76,0x69,0x6f,0x75,0x73,0x20,0x6c,0x69,0x6e,0x65,0x20,0x69,0x6e,0x74,0x65,0x6e,0x74,0x69,0x6f,0x6e,0x61,0x6c,0x6c,0x79,0x20,0x6c,0x65,0x66,0x74,0x20,0x62,0x6c,0x61,0x6e,0x6b,0x0a,0x41,0x46,0x54,0x45,0x52,0x5f,0x4c,0x49,0x4e,0x45,0x3d,0x61,0x66,0x74,0x65,0x72,0x5f,0x6c,0x69,0x6e,0x65,0x0a,0x55,0x4e,0x44,0x45,0x46,0x49,0x4e,0x45,0x44,0x5f,0x45,0x58,0x50,0x41,0x4e,0x44,0x3d,0x24,0x54,0x4f,0x54,0x41,0x4c,0x4c,0x59,0x5f,0x55,0x4e,0x44,0x45,0x46,0x49,0x4e,0x45,0x44,0x5f,0x45,0x4e,0x56,0x5f,0x4b,0x45,0x59,0x0a,0x45,0x4d,0x50,0x54,0x59,0x3d,0x0a,0x53,0x49,0x4e,0x47,0x4c,0x45,0x5f,0x51,0x55,0x4f,0x54,0x45,0x53,0x3d,0x27,0x73,0x69,0x6e,0x67,0x6c,0x65,0x5f,0x71,0x75,0x6f,0x74,0x65,0x73,0x27,0x0a,0x44,0x4f,0x55,0x42,0x4c,0x45,0x5f,0x51,0x55,0x4f,0x54,0x45,0x53,0x3d,0x22,0x64,0x6f,0x75,0x62,0x6c,0x65,0x5f,0x71,0x75,0x6f,0x74,0x65,0x73,0x22,0x0a,0x45,0x58,0x50,0x41,0x4e,0x44,0x5f,0x4e,0x45,0x57,0x4c,0x49,0x4e,0x45,0x53,0x3d,0x22,0x65,0x78,0x70,0x61,0x6e,0x64,0x5c,0x6e,0x6e,0x65,0x77,0x6c,0x69,0x6e,0x65,0x73,0x22,0x0a,0x44,0x4f,0x4e,0x54,0x5f,0x45,0x58,0x50,0x41,0x4e,0x44,0x5f,0x4e,0x45,0x57,0x4c,0x49,0x4e,0x45,0x53,0x5f,0x31,0x3d,0x64,0x6f,0x6e,0x74,0x65,0x78,0x70,0x61,0x6e,0x64,0x5c,0x6e,0x6e,0x65,0x77,0x6c,0x69,0x6e,0x65,0x73,0x0a,0x44,0x4f,0x4e,0x54,0x5f,0x45,0x58,0x50,0x41,0x4e,0x44,0x5f,0x4e,0x45,0x57,0x4c,0x49,0x4e,0x45,0x53,0x5f,0x32,0x3d,0x27,0x64,0x6f,0x6e,0x74,0x65,0x78,0x70,0x61,0x6e,0x64,0x5c,0x6e,0x6e,0x65,0x77,0x6c,0x69,0x6e,0x65,0x73,0x27,0x0a,0x23,0x20,0x43,0x4f,0x4d,0x4d,0x45,0x4e,0x54,0x53,0x3d,0x77,0x6f,0x72,0x6b,0x0a,0x45,0x51,0x55,0x41,0x4c,0x5f,0x53,0x49,0x47,0x4e,0x53,0x3d,0x65,0x71,0x75,0x61,0x6c,0x73,0x3d,0x3d,0x0a,0x52,0x45,0x54,0x41,0x49,0x4e,0x5f,0x49,0x4e,0x4e,0x45,0x52,0x5f,0x51,0x55,0x4f,0x54,0x45,0x53,0x3d,0x7b,0x22,0x66,0x6f,0x6f,0x22,0x3a,0x20,0x22,0x62,0x61,0x72,0x22,0x7d,0x0a,0x52,0x45,0x54,0x41,0x49,0x4e,0x5f,0x49,0x4e,0x4e,0x45,0x52,0x5f,0x51,0x55,0x4f,0x54,0x45,0x53,0x5f,0x41,0x53,0x5f,0x53,0x54,0x52,0x49,0x4e,0x47,0x3d,0x27,0x7b,0x22,0x66,0x6f,0x6f,0x22,0x3a,0x20,0x22,0x62,0x61,0x72,0x22,0x7d,0x27,0x0a,0x49,0x4e,0x43,0x4c,0x55,0x44,0x45,0x5f,0x53,0x50,0x41,0x43,0x45,0x3d,0x73,0x6f,0x6d,0x65,0x20,0x73,0x70,0x61,0x63,0x65,0x64,0x20,0x6f,0x75,0x74,0x20,0x73,0x74,0x72,0x69,0x6e,0x67,0x0a,0x55,0x53,0x45,0x52,0x4e,0x41,0x4d,0x45,0x3d,0x22,0x74,0x68,0x65,0x72,0x65,0x61,0x6c,0x6e,0x65,0x72,0x64,0x79,0x62,0x65,0x61,0x73,0x74,0x40,0x65,0x78,0x61,0x6d,0x70,0x6c,0x65,0x2e,0x74,0x6c,0x64,0x22,0x0a]

    static var allTests = [
        ("testByteArrayParser", testByteArrayParser),
        ("testStringDotEnv", testStringDotEnv),
        ("testByteBufferParser", testByteBufferParser),
        ("testByteBufferDotEnv", testByteBufferDotEnv),
        ("testNoTrailingNewlineByteBuffer", testNoTrailingNewlineByteBuffer),
        ("testNoTrailingNewlineString", testNoTrailingNewlineString),
        ("testNoTrailingNewlineByteArray", testNoTrailingNewlineByteArray),
    ]
}