import Foundation
import ProjectDescription

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
func reject(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); preconditionFailure("Expected rejection: \(message)") }
    catch let error as FeatureBuildConfiguration.Failure {
        require(error.message.contains(message), "Wrong rejection: \(error.message)")
    } catch { preconditionFailure("Unexpected error: \(error)") }
}

let base: [String: Plist.Value] = ["CFBundleDisplayName": "Host", "CFBundleVersion": "4"]
let group: [String: Plist.Value] = ["com.apple.security.application-groups": ["group.host"]]
let unchanged = try FeatureBuildConfiguration().compose(infoPlist: base, entitlements: group)
require(unchanged.infoPlist == base && unchanged.entitlements == group, "Empty configuration changed host")

let a = FeatureBuildRequirement(owner: "camera", infoPlist: [
    "NSCameraUsageDescription": "Take photos", "UIBackgroundModes": ["audio"],
    "CustomOptions": ["enabled": true, "quality": 3],
], entitlements: ["com.apple.security.application-groups": ["group.camera"]])
let b = FeatureBuildRequirement(owner: "scanner", infoPlist: [
    "NSCameraUsageDescription": "Scan documents", "UIBackgroundModes": ["processing", "audio"],
], entitlements: ["com.apple.security.application-groups": ["group.host"]])
reject("NSCameraUsageDescription") {
    _ = try FeatureBuildConfiguration(features: [a, b]).compose(infoPlist: base, entitlements: group)
}
let resolved = FeatureBuildConfiguration(features: [a, b],
    infoPlistResolutions: ["NSCameraUsageDescription": "Camera takes photos; Scanner scans documents"])
let composed = try resolved.compose(infoPlist: base, entitlements: group)
require(composed.infoPlist["UIBackgroundModes"] == ["audio", "processing"], "Set merge lost or duplicated modes")
require(composed.infoPlist["CustomOptions"] == ["enabled": true, "quality": 3], "Custom plist values restricted")
require(composed.entitlements["com.apple.security.application-groups"] == ["group.camera", "group.host"], "Group union failed")
let reversed = try FeatureBuildConfiguration(features: [b, a], infoPlistResolutions: resolved.infoPlistResolutions)
    .compose(infoPlist: base, entitlements: group)
require(composed.infoPlist == reversed.infoPlist && composed.entitlements == reversed.entitlements, "Set result depends on Feature order")
let otherTarget = try FeatureBuildConfiguration().compose(infoPlist: [:], entitlements: group)
require(otherTarget.infoPlist["NSCameraUsageDescription"] == nil && otherTarget.entitlements == group, "Requirements leaked to another target")

reject("unique") { _ = try FeatureBuildConfiguration(features: [a, a]).compose(infoPlist: [:], entitlements: [:]) }
reject("nonempty") { _ = try FeatureBuildConfiguration(features: [.init(owner: " ")]).compose(infoPlist: [:], entitlements: [:]) }
reject("CFBundleIdentifier") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad", infoPlist: ["CFBundleIdentifier": "other.app"])])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("string array") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "bad", infoPlist: ["UIBackgroundModes": [true]])])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("Unused") {
    _ = try FeatureBuildConfiguration(infoPlistResolutions: ["missing": "value"]).compose(infoPlist: [:], entitlements: [:])
}
reject("string array") {
    _ = try FeatureBuildConfiguration(features: [a], infoPlistResolutions: ["UIBackgroundModes": true])
        .compose(infoPlist: [:], entitlements: [:])
}
reject("aps-environment") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "push", entitlements: ["aps-environment": "production"])])
        .compose(infoPlist: [:], entitlements: ["aps-environment": "development"])
}
reject("CFBundleURLTypes") {
    _ = try FeatureBuildConfiguration(features: [.init(owner: "callback", infoPlist: ["CFBundleURLTypes": [["CFBundleURLSchemes": ["callback"]]]])])
        .compose(infoPlist: ["CFBundleURLTypes": [["CFBundleURLSchemes": ["host"]]]], entitlements: [:])
}
let identical = try FeatureBuildConfiguration(features: [.init(owner: "same", infoPlist: ["CFBundleVersion": "4"])])
    .compose(infoPlist: base, entitlements: group)
require(identical.infoPlist == base, "Identical setting rejected")
let activities = try FeatureBuildConfiguration(features: [.init(owner: "activity", infoPlist: ["NSUserActivityTypes": ["custom", "native"]])])
    .compose(infoPlist: ["NSUserActivityTypes": ["native"]], entitlements: [:])
require(activities.infoPlist["NSUserActivityTypes"] == ["custom", "native"], "Activity types lost host continuation")
let entitlementResolution = try FeatureBuildConfiguration(features: [.init(owner: "push", entitlements: ["aps-environment": "production"])],
    entitlementResolutions: ["aps-environment": "development"]).compose(infoPlist: [:], entitlements: ["aps-environment": "development"])
require(entitlementResolution.entitlements["aps-environment"] == "development", "Explicit entitlement resolution ignored")
print("Feature build requirement checks passed: baseline, union, conflict, resolution, custom values, target isolation, validation")
