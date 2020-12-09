![macOS](https://github.com/swiftpackages/DotEnv/workflows/macOS/badge.svg)
![ubuntu](https://github.com/swiftpackages/DotEnv/workflows/ubuntu/badge.svg)
![docs](https://github.com/swiftpackages/DotEnv/workflows/docs/badge.svg)

# DotEnv

A swift DotEnv file loader inspired by [vlucas/phpdotenv](https://github.com/vlucas/phpdotenv).
This swift package enables you to quickly and easily use a `.env` file in your swift project today.
Using [SwiftNIO](https://github.com/apple/swift-nio) in project?
Don't worry, you can use `NonBlockingFileIO` to ensure everything runs smoothly.

## Getting Started

You can easily add as a requirement with [SwiftPM](https://swift.org/package-manager/).

### Know what you're doing?

Here are some quick copypastas for you

```swift
.package(url: "https://github.com/swiftpackages/DotEnv.git", from: "1.0.0"),
```
```swift
.product(name: "DotEnv", package: "DotEnv"),
```

### Need a reminder?

Your `Package.swift` file should look something like this

`Package.swift`
```swift
// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SuperCoolProject",
    products: [
        .library(
            name: "SuperCoolProject",
            targets: ["SuperCoolProject"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftpackages/DotEnv.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SuperCoolProject",
            dependencies: [
                .product(name: "DotEnv", package: "DotEnv"),
            ]),
        .testTarget(
            name: "SuperCoolProject",
            dependencies: ["SuperCoolProject"])
    ]
)
```

## Usage

### Without SwiftNIO
Read and then load

```swift
let path = "path/to/your/.env"
var env = try DotEnv.read(path: path)
env.lines // [Line] (key=value pairs)
env.load()
print(ProcessInfo.processInfo.environment["FOO"]) // BAR
```

or

Just load

```swift
let path = "path/to/your/.env"
var env = try DotEnv.load(path: path)
env.lines // [Line] (key=value pairs)
print(ProcessInfo.processInfo.environment["FOO"]) // BAR
```

Do you have two `.env` files you wish to load? You can do that without breaking a sweat.
By using a `load` method with a `suffix` parameter you can easily load your shared `.env.development` file, and then overwrite anything you need to with your local `.env` file.

```swift
let path = "path/to/your/.env"
let suffix = "development"
try DotEnv.load(path: path, suffix: suffix)
print(ProcessInfo.processInfo.environment["FOO"]) // BAR
```

### With SwiftNIO
Read and then load

```swift
let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let pool = NIOThreadPool(numberOfThreads: 1)
pool.start()
let fileio = NonBlockingFileIO(threadPool: pool)

let env = try DotEnv.read(path: filePath, fileio: fileio, on: elg.next()).wait()
env.load(overwrite: true)

print(ProcessInfo.processInfo.environment["FOO"]) // BAR

try pool.syncShutdownGracefully()
try elg.syncShutdownGracefully()
```

or

Just load

```swift
let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let pool = NIOThreadPool(numberOfThreads: 1)
pool.start()
let fileio = NonBlockingFileIO(threadPool: pool)

DotEnv.load(path: filePath, fileio: fileio, on: elg.next()).wait()

print(ProcessInfo.processInfo.environment["FOO"]) // BAR

try pool.syncShutdownGracefully()
try elg.syncShutdownGracefully()
```

### Additional Documentation

[You can find the full documentation on the documentation website.](https://swiftpackages.github.io/DotEnv)

## Credits

A signficant portion of this project comes from [vapor/vapor](https://github.com/vapor/vapor) under [The MIT License](https://github.com/vapor/vapor/blob/4.36.0/LICENSE).
