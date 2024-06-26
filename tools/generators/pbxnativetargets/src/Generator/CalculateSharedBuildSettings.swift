import OrderedCollections
import PBXProj
import ToolCommon

extension Generator {
    struct CalculateSharedBuildSettings {
        private let callable: Callable

        /// - Parameters:
        ///   - callable: The function that will be called in
        ///     `callAsFunction()`.
        init(callable: @escaping Callable = Self.defaultCallable) {
            self.callable = callable
        }

        /// Calculates a target's shared build settings. These are the build
        /// settings that are the same for every Xcode configuration.
        func callAsFunction(
            name: String,
            label: BazelLabel,
            platforms: OrderedSet<Platform>,
            productType: PBXProductType,
            productName: String,
            uiTestHostName: String?
        ) -> [BuildSetting] {
            return callable(
                /*name:*/ name,
                /*label:*/ label,
                /*platforms:*/ platforms,
                /*productType:*/ productType,
                /*productName:*/ productName,
                /*uiTestHostName:*/ uiTestHostName
            )
        }
    }
}

// MARK: - CalculateSharedBuildSettings.Callable

extension Generator.CalculateSharedBuildSettings {
    typealias Callable = (
        _ name: String,
        _ label: BazelLabel,
        _ platforms: OrderedSet<Platform>,
        _ productType: PBXProductType,
        _ productName: String,
        _ uiTestHostName: String?
    ) -> [BuildSetting]

    static func defaultCallable(
        name: String,
        label: BazelLabel,
        platforms: OrderedSet<Platform>,
        productType: PBXProductType,
        productName: String,
        uiTestHostName: String?
    ) -> [BuildSetting] {
        var buildSettings: [BuildSetting] = []

        buildSettings.append(
            .init(key: "PRODUCT_NAME", value: productName.pbxProjEscaped)
        )
        buildSettings.append(
            .init(key: "TARGET_NAME", value: name.pbxProjEscaped)
        )
        buildSettings.append(
            .init(
                key: "COMPILE_TARGET_NAME",
                value: label.name.pbxProjEscaped
            )
        )

        buildSettings.append(
            .init(key: "SDKROOT", value: platforms.first!.os.sdkRoot)
        )

        var supportedPlatforms = platforms
        if productType == .appExtension {
            // Xcode has a bug where if we don't include device platforms in
            // app extension targets, then it will fail to install the hosting
            // application
            if let index = supportedPlatforms.firstIndex(of: .iOSSimulator) {
                supportedPlatforms.insert(.iOSDevice, at: index + 1)
            }
            if let index = supportedPlatforms.firstIndex(of: .tvOSSimulator) {
                supportedPlatforms.insert(.tvOSDevice, at: index + 1)
            }
            if let index = supportedPlatforms.firstIndex(
                of: .watchOSSimulator
            ) {
                supportedPlatforms.insert(.watchOSDevice, at: index + 1)
            }
            if let index = supportedPlatforms.firstIndex(
                of: .visionOSSimulator
            ) {
                supportedPlatforms.insert(.visionOSDevice, at: index + 1)
            }
        }
        buildSettings.append(
            .init(
                key: "SUPPORTED_PLATFORMS",
                value: supportedPlatforms.map(\.rawValue).joined(separator: " ")
                    .pbxProjEscaped
            )
        )

        if !platforms.intersection(iPhonePlatforms).isEmpty {
            buildSettings.append(
                .init(
                    key: "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD",
                    value: platforms.contains(.iOSDevice) ? "YES" : "NO"
                )
            )
        }

        if productType != .resourceBundle {
            // This is used in `calculate_output_groups.py`. We only want to set
            // it on buildable targets.
            buildSettings.append(
                .init(
                    key: "BAZEL_LABEL",
                    value: label.description.pbxProjEscaped
                )
            )
        }

        if productType == .framework {
            // Xcode previews require frameworks to be code signed
            buildSettings.append(
                .init(
                    key: "CODE_SIGNING_ALLOWED",
                    value: #""$(ENABLE_PREVIEWS)""#
                )
            )
        } else if productType == .uiTestBundle {
            // UI tests require code signing to enable debugging
            buildSettings.append(
                .init(key: "CODE_SIGNING_ALLOWED", value: "YES")
            )
        }

        if productType == .uiTestBundle {
            if let uiTestHostName {
                buildSettings.append(
                    .init(
                        key: "TEST_TARGET_NAME",
                        value: uiTestHostName.pbxProjEscaped
                    )
                )
            }
        } else if productType == .staticFramework {
            // We set the `productType` to `.framework` to get the better
            // looking icon, so we need to manually set `MACH_O_TYPE`
            buildSettings.append(.init(key: "MACH_O_TYPE", value: "staticlib"))
        }

        return buildSettings
    }
}

private let iPhonePlatforms: Set<Platform> = [
    .iOSDevice,
    .iOSSimulator,
]

private extension PBXProductType {
    var isLaunchable: Bool {
        switch self {
        case .application,
             .messagesApplication,
             .onDemandInstallCapableApplication,
             .watch2App,
             .watch2AppContainer,
             .appExtension,
             .intentsServiceExtension,
             .messagesExtension,
             .tvExtension,
             .extensionKitExtension,
             .watch2Extension,
             .xcodeExtension,
             .ocUnitTestBundle,
             .unitTestBundle,
             .uiTestBundle,
             .driverExtension,
             .systemExtension,
             .commandLineTool,
             .xpcService:
            return true
        case .stickerPack,
             .resourceBundle,
             .bundle,
             .framework,
             .staticFramework,
             .xcFramework,
             .dynamicLibrary,
             .staticLibrary,
             .instrumentsPackage,
             .metalLibrary:
            return false
        }
    }
}

private extension Platform.OS {
    var deploymentTargetBuildSettingKey: String {
        switch self {
        case .macOS: return "MACOSX_DEPLOYMENT_TARGET"
        case .iOS: return "IPHONEOS_DEPLOYMENT_TARGET"
        case .tvOS: return "TVOS_DEPLOYMENT_TARGET"
        case .visionOS: return "XROS_DEPLOYMENT_TARGET"
        case .watchOS: return "WATCHOS_DEPLOYMENT_TARGET"
        }
    }

    var sdkRoot: String {
        switch self {
        case .macOS: return "macosx"
        case .iOS: return "iphoneos"
        case .tvOS: return "appletvos"
        case .visionOS: return "xros"
        case .watchOS: return "watchos"
        }
    }
}
