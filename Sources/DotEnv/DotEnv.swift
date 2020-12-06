//
// DotEnv.swift
//
// A signficant portion of this code comes from [vapor/vapor](https://github.com/vapor/vapor).
//

import Foundation
import NIO

public enum EventLoopGroupSource {
    case provided(EventLoopGroup)
    case createNew
}

/// Represents a `KEY=VALUE` pair in a dotenv file.
public struct Line: CustomStringConvertible, Equatable {
    /// The key.
    public let key: String

    /// The value.
    public let value: String

    /// `CustomStringConvertible` conformance.
    public var description: String {
        return "\(self.key)=\(self.value)"
    }
}

public struct DotEnv {
    /// Reads two dotenv files relevant to the environment and loads them into the process.
    ///
    ///     let path: String
    ///     let elgp: EventLoopGroupSource
    ///     let fileio: NonBlockingFileIO
    ///     let postfix: String
    ///     try DotEnvFile.load(path: path, postfix: postfix, on: elgs, fileio: fileio)
    ///     print(Environment.process.FOO) // BAR
    ///
    /// - parameters:
    ///     - environment: current environment, selects which .env file to use.
    ///     - eventLoopGroupProvider: Either provides an EventLoopGroup or tells the function to create a new one.
    ///     - fileio: NonBlockingFileIO that is used to read the .env file(s).
    ///     - logger: Optionally provide an existing logger.
    public static func load(
        path: String = ".env",
        postfix: String,
        on eventLoopGroupSource: EventLoopGroupSource = .createNew,
        fileio: NonBlockingFileIO
    ) {
        let eventLoopGroup: EventLoopGroup

        switch eventLoopGroupSource {
            case .provided(let group):
                eventLoopGroup = group
            case .createNew:
                eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }
        defer {
            switch eventLoopGroupSource {
            case .provided:
                break
            case .createNew:
                do {
                    try eventLoopGroup.syncShutdownGracefully()
                } catch {
                    // :(
                }
            }
        }

        // Load specific .env first since values are not overridden.
        DotEnv.load(path: "\(path).\(postfix)", on: .provided(eventLoopGroup), fileio: fileio)
        DotEnv.load(path: path, on: .provided(eventLoopGroup), fileio: fileio)
    }

    /// Reads the dotenv files relevant to the environment and loads them into the process.
    ///
    ///     let path: String
    ///     let elgs: EventLoopGroupSource
    ///     let fileio: NonBlockingFileIO
    ///     try DotEnvFile.load(path: path, on: elgs, fileio: filio)
    ///     print(Environment.process.FOO) // BAR
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - eventLoopGroupProvider: Either provides an EventLoopGroup or tells the function to create a new one.
    ///     - fileio: NonBlockingFileIO that is used to read the .env file(s).
    public static func load(
        path: String,
        on eventLoopGroupSource: EventLoopGroupSource = .createNew,
        fileio: NonBlockingFileIO
    ) {
        let eventLoopGroup: EventLoopGroup

        switch eventLoopGroupSource {
            case .provided(let group):
                eventLoopGroup = group
            case .createNew:
                eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }
        defer {
            switch eventLoopGroupSource {
                case .provided:
                    break
                case .createNew:
                    do {
                        try eventLoopGroup.syncShutdownGracefully()
                    } catch {
                        // :(
                    }
            }
        }

        do {
            try load(path: path, fileio: fileio, on: eventLoopGroup.next()).wait()
        } catch {
            // :(
        }
    }

    /// Reads a dotenv file from the supplied path and loads it into the process.
    ///
    ///     let fileio: NonBlockingFileIO
    ///     let elg: EventLoopGroup
    ///     try DotEnvFile.load(path: ".env", fileio: fileio, on: elg.next()).wait()
    ///     print(Environment.process.FOO) // BAR
    ///
    /// Use `DotEnvFile.read` to read the file without loading it.
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - fileio: File loader.
    ///     - eventLoop: Eventloop to perform async work on.
    ///     - overwrite: If `true`, values already existing in the process' env
    ///                  will be overwritten. Defaults to `false`.
    public static func load(
        path: String,
        fileio: NonBlockingFileIO,
        on eventLoop: EventLoop,
        overwrite: Bool = false
    ) -> EventLoopFuture<Void> {
        return self.read(path: path, fileio: fileio, on: eventLoop)
            .map { $0.load(overwrite: overwrite) }
    }

    /// Reads a dotenv file from the supplied path.
    ///
    ///     let fileio: NonBlockingFileIO
    ///     let elg: EventLoopGroup
    ///     let file = try DotEnvFile.read(path: ".env", fileio: fileio, on: elg.next()).wait()
    ///     for line in file.lines {
    ///         print("\(line.key)=\(line.value)")
    ///     }
    ///     file.load(overwrite: true) // loads all lines into the process
    ///     print(Environment.process.FOO) // BAR
    ///
    /// Use `DotEnvFile.load` to read and load with one method.
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - fileio: File loader.
    ///     - eventLoop: Eventloop to perform async work on.
    public static func read(
        path: String,
        fileio: NonBlockingFileIO,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<DotEnv> {
        return fileio.openFile(path: path, eventLoop: eventLoop).flatMap { arg -> EventLoopFuture<ByteBuffer> in
            return fileio.read(fileRegion: arg.1, allocator: .init(), eventLoop: eventLoop)
                .flatMapThrowing
            { buffer in
                try arg.0.close()
                return buffer
            }
        }.map { buffer in
            var parser = ByteBufferParser(source: buffer)
            return .init(lines: parser.parse())
        }
    }

    public static func load(path: String, encoding: String.Encoding = .utf8, overwrite: Bool = true) {
        let file = try! String(contentsOfFile: path, encoding: encoding)
        var parser = StringParser(source: file)
        let dotenv = Self.init(lines: parser.parse())
        dotenv.load(overwrite: overwrite)
    }

    public static func read(path: String, encoding: String.Encoding = .utf8) -> DotEnv {
        let file = try! String(contentsOfFile: path, encoding: encoding)
        var parser = StringParser(source: file)
        return .init(lines: parser.parse())
    }

    /// All `KEY=VALUE` pairs found in the file.
    public let lines: [Line]

    /// Creates a new DotEnv
    init(lines: [Line]) {
        self.lines = lines
    }

    /// Loads this file's `KEY=VALUE` pairs into the current process.
    ///
    ///     let file: DotEnv
    ///     file.load(overwrite: true) // loads all lines into the process
    ///
    /// - parameters:
    ///     - overwrite: If `true`, values already existing in the process' env
    ///                  will be overwritten. Defaults to `false`.
    public func load(overwrite: Bool = false) {
        for line in self.lines {
            setenv(line.key, line.value, overwrite ? 1 : 0)
        }
    }
}

internal extension UInt8 {
    static var newLine: UInt8 {
        return 0xA
    }

    static var space: UInt8 {
        return 0x20
    }

    static var octothorpe: UInt8 {
        return 0x23
    }

    static var equal: UInt8 {
        return 0x3D
    }
}
