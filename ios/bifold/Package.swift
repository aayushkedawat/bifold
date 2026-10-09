// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bifold",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "bifold", targets: ["bifold"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "bifold",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            // No resources. A PrivacyInfo.xcprivacy used to sit in Sources/
            // bundled by neither this target nor the podspec, which with
            // SwiftPM also made it an unhandled-resource build warning and
            // with CocoaPods swept it in as a source file. This plugin calls
            // no required-reason API and is not on Apple's listed-SDK list, so
            // no manifest is required -- and a dead one is worse than none.
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
