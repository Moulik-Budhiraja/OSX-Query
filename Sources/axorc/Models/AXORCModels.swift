// AXORCModels.swift - Shared version/build metadata for AXORC CLI

import Foundation

let axorcVersion = "0.1.3"

/// Returns a human-readable build stamp (yyMMddHHmm) evaluated at runtime.
/// Good enough for confirming we're on the binary we just built.
var axorcBuildStamp: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyMMddHHmm"
    return formatter.string(from: Date())
}
