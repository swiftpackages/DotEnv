import XCTest
import NIO
@testable import DotEnv

final class DotEnvTests: XCTestCase {
    let testString = """
        NODE_ENV=development
        BASIC=basic
        AFTER_LINE=after_line
        UNDEFINED_EXPAND=$TOTALLY_UNDEFINED_ENV_KEY
        EMPTY=
        SINGLE_QUOTES=single_quotes
        DOUBLE_QUOTES=double_quotes
        EXPAND_NEWLINES=expand\nnewlines
        DONT_EXPAND_NEWLINES_1=dontexpand\\nnewlines
        DONT_EXPAND_NEWLINES_2=dontexpand\\nnewlines
        EQUAL_SIGNS=equals==
        RETAIN_INNER_QUOTES={"foo": "bar"}
        RETAIN_INNER_QUOTES_AS_STRING={"foo": "bar"}
        INCLUDE_SPACE=some spaced out string
        USERNAME=therealnerdybeast@example.tld
        """

    let testStringValues: [(key: String, value: String)] = [
        (key: "NODE_ENV",                       value: "development"),
        (key: "BASIC",                          value: "basic"),
        (key: "AFTER_LINE",                     value: "after_line"),
        (key: "UNDEFINED_EXPAND",               value: "$TOTALLY_UNDEFINED_ENV_KEY"),
        (key: "EMPTY",                          value: ""),
        (key: "SINGLE_QUOTES",                  value: "single_quotes"),
        (key: "DOUBLE_QUOTES",                  value: "double_quotes"),
        (key: "EXPAND_NEWLINES",                value: "expand\nnewlines"),
        (key: "DONT_EXPAND_NEWLINES_1",         value: "dontexpand\\nnewlines"),
        (key: "DONT_EXPAND_NEWLINES_2",         value: "dontexpand\\nnewlines"),
        (key: "EQUAL_SIGNS",                    value: "equals=="),
        (key: "RETAIN_INNER_QUOTES",            value: "{\"foo\": \"bar\"}"),
        (key: "RETAIN_INNER_QUOTES_AS_STRING",  value: "{\"foo\": \"bar\"}"),
        (key: "INCLUDE_SPACE",                  value: "some spaced out string"),
        (key: "USERNAME",                       value: "therealnerdybeast@example.tld"),
    ]

    func testStringDotEnv() {
        let env = DotEnv.read(path: "Tests/DotEnvTests/Resources/env.test")
        env.load(overwrite: true)
        for (key, value) in testStringValues {
            XCTAssertEqual(ProcessInfo.processInfo.environment[key], value )
        }
    }

    func testReadFile() throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let pool = NIOThreadPool(numberOfThreads: 1)
        pool.start()
        let fileio = NonBlockingFileIO(threadPool: pool)
        let folder = #file.split(separator: "/").dropLast().joined(separator: "/")
        let path = "/" + folder + "/Resources/env.test"
        let file = try DotEnv.read(path: path, fileio: fileio, on: elg.next()).wait()
        let test = file.lines.map { $0.description }.joined(separator: "\n")
        XCTAssertEqual(test, testString)
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

    static var allTests = [
        "testStringDotEnv": testStringDotEnv,
        "testReadFile": testReadFile,
        "testNoTrailingNewlineByteBuffer": testNoTrailingNewlineByteBuffer,
        "testNoTrailingNewlineString": testNoTrailingNewlineString,
    ]
}
