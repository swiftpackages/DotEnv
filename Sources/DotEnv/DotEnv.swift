//
// DotEnv.swift
//
// A signficant portion of this code comes from [vapor/vapor](https://github.com/vapor/vapor).
//

import Foundation
import NIO

public enum DotEnvError: Error {
    case fileCouldNotBeRead(String, String.Encoding)
}

/// Either provides an EventLoopGroup or indicate to create a new one
public enum EventLoopGroupSource {
    /// Provided EventLoopGroup
    case provided(EventLoopGroup)
    /// Create a EventLoopGroup
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
/// An environment variable loader.
///
/// You can either read the file and then load it or load in one step.
///
///     // read and then load
///     let path: String
///     var env = try DotEnv.read(path: path)
///     env.lines // [Line] (key=value pairs)
///     env.load()
///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
///
/// or
///
///     // load it
///     let path: String
///     var env = try DotEnv.load(path: path)
///     env.lines // [Line] (key=value pairs)
///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
public struct DotEnv {
    /// Reads two `DotEnv` files relevant to the environment and loads them into the environment.
    ///
    /// The `suffix` parameter allows you to read a secondary file.
    /// This file will be loaded first and file that the `path` parameter points to will be read second.
    /// By doing this the `path.suffix` environment settings get overwriten any `path` settings.
    ///
    ///     let path: String
    ///     let suffix: String
    ///     let elgs: EventLoopGroupSource
    ///     let fileio: NonBlockingFileIO
    ///     try DotEnv.load(path: path, suffix: suffix, on: elgs, fileio: fileio)
    ///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
    ///
    /// - parameters:
    ///     - path: Path to the file you wish to load (including filename and extension)
    ///     - suffix: A suffix to add onto the path (for loading a seperate file)
    ///     - eventLoopGroupSource: Either provides an `EventLoopGroup` or tells the function to create a new one
    ///     - fileio: `NonBlockingFileIO` that is used to read the .env file(s)
    ///     - overwrite: Set to false to prevent overwiting current environment variables
    public static func load(
        path: String = ".env",
        suffix: String,
        on eventLoopGroupSource: EventLoopGroupSource = .createNew,
        fileio: NonBlockingFileIO,
        overwrite: Bool = true
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
        DotEnv.load(path: "\(path).\(suffix)",
                    on: .provided(eventLoopGroup),
                    fileio: fileio,
                    overwrite: overwrite)
        DotEnv.load(path: path,
                    on: .provided(eventLoopGroup),
                    fileio: fileio,
                    overwrite: overwrite)
    }

    /// Reads a `DotEnv` file relevant to the environment and loads them into the environment.
    ///
    ///     let path: String
    ///     let elgs: EventLoopGroupSource
    ///     let fileio: NonBlockingFileIO
    ///     try DotEnv.load(path: path, on: elgs, fileio: fileio)
    ///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
    ///
    /// - parameters:
    ///     - path: Path to the file you wish to load (including filename and extension)
    ///     - eventLoopGroupSource: Either provides an `EventLoopGroup` or tells the function to create a new one.
    ///     - fileio: `NonBlockingFileIO` that is used to read the .env file(s).
    ///     - overwrite: Set to false to prevent overwiting current environment variables
    public static func load(
        path: String,
        on eventLoopGroupSource: EventLoopGroupSource = .createNew,
        fileio: NonBlockingFileIO,
        overwrite: Bool = true
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
            try load(path: path,
                     fileio: fileio,
                     on: eventLoopGroup.next(),
                     overwrite: overwrite).wait()
        } catch {
            // :(
        }
    }

    /// Reads  `DotEnv` files relevant to the environment and loads them into the environment.
    ///
    ///     let path: String
    ///     let el: EventLoop
    ///     let fileio: NonBlockingFileIO
    ///     try DotEnv.load(path: path, on: el, fileio: fileio)
    ///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
    ///
    /// - parameters:
    ///     - path: Path to the file you wish to load (including filename and extension)
    ///     - eventLoop: `EventLoop` to perform async work on.
    ///     - fileio: `NonBlockingFileIO` that is used to read the .env file(s).
    ///     - overwrite: Set to false to prevent overwiting current environment variables
    ///     - returns: `EventLoopFuture<Void>`
    public static func load(
        path: String,
        fileio: NonBlockingFileIO,
        on eventLoop: EventLoop,
        overwrite: Bool = true
    ) -> EventLoopFuture<Void> {
        return self.read(path: path, fileio: fileio, on: eventLoop)
            .map { $0.load(overwrite: overwrite) }
    }

    /// Reads a DotEnv file from the supplied path.
    ///
    ///     let path: String
    ///     let fileio: NonBlockingFileIO
    ///     let elg: EventLoopGroup
    ///     let file = try DotEnv.read(path: path, fileio: fileio, on: elg.next()).wait()
    ///     for line in file.lines {
    ///         print("\(line.key)=\(line.value)")
    ///     }
    ///     file.load() // loads lines into the process
    ///     print(Environment.process.FOO) // BAR
    ///
    /// Use `DotEnv.load` to read and load with one method.
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - fileio: `NonBlockingFileIO`
    ///     - eventLoop: `EventLoop` to perform async work on.
    ///     - returns: `EventLoopFuture<DotEnv>`
    public static func read(
        path: String = ".env",
        fileio: NonBlockingFileIO,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<DotEnv> {
        return fileio.openFile(path: path, eventLoop: eventLoop).flatMap { arg -> EventLoopFuture<ByteBuffer> in
            return fileio.read(fileRegion: arg.1, allocator: .init(), eventLoop: eventLoop)
                .flatMapThrowing { buffer in
                try arg.0.close()
                return buffer
            }
        }.map { buffer in
            var parser = ByteBufferParser(source: buffer)
            return .init(lines: parser.parse())
        }
    }

    /// Reads two `DotEnv` files relevant to the environment and loads them into the environment.
    ///
    /// The `suffix` parameter allows you to read a secondary file.
    /// This file will be loaded first and file that the `path` parameter points to will be read second.
    /// By doing this the `path.suffix` environment settings get overwriten any `path` settings.
    ///
    ///     let path: String
    ///     let suffix: String
    ///     let encoding: String.Encoding
    ///     try DotEnv.load(path: path, suffix: suffix, encoding: Encoding)
    ///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
    ///
    /// - parameters:
    ///     - path: Path to the file you wish to load (including filename and extension)
    ///     - suffix: A suffix to add onto the path (for loading a seperate file)
    ///     - encoding: The file's encoding
    ///     - overwrite: Set to false to prevent overwiting current environment variables
    public static func load(path: String,
                            suffix: String,
                            encoding: String.Encoding = .utf8,
                            overwrite: Bool = true) throws {
        try load(path: "\(path).\(suffix)",
             encoding: encoding,
             overwrite: overwrite)
        try load(path: path,
             encoding: encoding,
             overwrite: overwrite)
    }

    /// Reads a `DotEnv` file relevant to the environment and loads them into the environment.
    ///
    ///     let path: String
    ///     let encoding: String.Encoding
    ///     try DotEnv.load(path: path, encoding: Encoding)
    ///     print(ProcessInfo.processInfo.environment["FOO"]) // BAR
    ///
    /// - parameters:
    ///     - path: Path to the file you wish to load (including filename and extension)
    ///     - encoding: The file's encoding
    ///     - overwrite: Set to false to prevent overwiting current environment variables
    public static func load(path: String,
                            encoding: String.Encoding = .utf8,
                            overwrite: Bool = true) throws {
        do {
            let file = try String(contentsOfFile: path, encoding: encoding)
            var parser = StringParser(source: file)
            let dotenv = Self.init(lines: parser.parse())
            dotenv.load(overwrite: overwrite)
        } catch {
            throw DotEnvError.fileCouldNotBeRead(path, encoding)
        }
    }

    /// Reads a `DotEnv` file from the supplied path.
    ///
    ///     let path: String
    ///     let encoding: String.Encoding
    ///     let file = try DotEnv.read(path: path, encoding: encoding)
    ///     for line in file.lines {
    ///         print("\(line.key)=\(line.value)")
    ///     }
    ///     file.load() // loads lines into the process
    ///     print(Environment.process.FOO) // BAR
    ///
    /// Use `DotEnv.load` to read and load with one method.
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - encoding: Encoding of the file
    ///     - returns: `DotEnv`
    public static func read(path: String, encoding: String.Encoding = .utf8) throws -> DotEnv {
        do {
            let file = try String(contentsOfFile: path, encoding: encoding)
            var parser = StringParser(source: file)
            return .init(lines: parser.parse())
        } catch {
            throw DotEnvError.fileCouldNotBeRead(path, encoding)
        }
    }

    /// All `KEY=VALUE` pairs found in the file.
    public let lines: [Line]

    /// Creates a new `DotEnv`
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
    ///                  will be overwritten. Defaults to `true`.
    public func load(overwrite: Bool = true) {
        for line in self.lines {
            setenv(line.key, line.value, overwrite ? 1 : 0)
        }
    }
}
