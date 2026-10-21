// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AppleAccountKit
final class MemoryCapabilityTests: XCTestCase {
    private func snapshot(enabled: Bool = false) -> [String: Any] {
        let caps: [[String: Any]] = [("PUSH_NOTIFICATIONS", "push", true), ("INCREASED_MEMORY_LIMIT", "ram", enabled)].map { cap, id, value in
            ["id": id, "type": "bundleIdCapabilities", "attributes": ["enabled": value, "settings": [["key": "keep", "options": ["existing"]]]],
             "relationships": ["capability": ["data": ["type": "capabilities", "id": cap]]]]
        }
        return ["data": ["relationships": ["bundleIdCapabilities": ["data": caps.map { ["id": $0["id"]!, "type": "bundleIdCapabilities"] }]]], "included": caps]
    }
    func testPreservesOtherCapabilitiesAndOpaqueSettings() throws {
        let before = snapshot()
        let after = try MemoryCapability.updatedCapabilities(before)
        XCTAssertEqual(after.count, 2)
        let attrs: [String: Any] = ["data": ["attributes": ["identifier":"example.playport", "seedId":"OLDERPREFIX", "hasExclusiveManagedCapabilities":true, "readOnlyServerField":"ignored"]]]
        let preserved = try MemoryCapability.preservedAttributes(attrs, installedBundleID:"example.playport")
        XCTAssertEqual(preserved["seedId"] as? String, "OLDERPREFIX")
        XCTAssertEqual(preserved["hasExclusiveManagedCapabilities"] as? Bool, true)
        XCTAssertNil(preserved["readOnlyServerField"])
        XCTAssertThrowsError(try MemoryCapability.preservedAttributes(attrs, installedBundleID:"example.other"))
        let sparse: [String:Any] = ["data":["attributes":["identifier":"example.playport"]]]
        XCTAssertNil(try MemoryCapability.preservedAttributes(sparse, installedBundleID:"example.playport")["seedId"])

        let original = (before["included"] as! [[String: Any]])[0]
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: after[0], options: .sortedKeys),
                       try JSONSerialization.data(withJSONObject: original, options: .sortedKeys))
        XCTAssertEqual((after[1]["attributes"] as? [String: Any])?["enabled"] as? Bool, true)
    }
    func testIncompleteSnapshotRefusesWrites() {
        var broken = snapshot(); broken["included"] = []
        XCTAssertThrowsError(try MemoryCapability.updatedCapabilities(broken))
        XCTAssertThrowsError(try MemoryCapability.updatedCapabilities([:]))
    }
    func testInstalledIdentifierMustMatchExactlyAndUniquely() throws {
        let other = DeveloperApp(id: "other", bundleID: "example.other", name: "Other")
        let own = DeveloperApp(id: "own", bundleID: "example.playport", name: "Playport")
        XCTAssertEqual(try MemoryCapability.select([other, own], installedBundleID: own.bundleID).id, own.id)
        XCTAssertThrowsError(try MemoryCapability.select([other], installedBundleID: own.bundleID))
        XCTAssertThrowsError(try MemoryCapability.select([own, own], installedBundleID: own.bundleID))
    }
    func testAlreadyEnabledIsIdempotentAndMissingCapabilityIsAddedOnce() throws {
        XCTAssertTrue(MemoryCapability.isEnabled(snapshot(enabled: true)))
        XCTAssertFalse(MemoryCapability.isEnabled(snapshot()))
        let empty: [String: Any] = ["data": ["relationships": ["bundleIdCapabilities": ["data": [[String: Any]]()]]], "included": [[String: Any]]()]
        XCTAssertEqual(try MemoryCapability.updatedCapabilities(empty).count, 1)
        XCTAssertEqual(try MemoryCapability.updatedCapabilities(snapshot(enabled: true)).count, 2)
    }
    func testPaginatedOrDuplicateRelationshipsRefuseWrites() {
        let included = snapshot()["included"]!
        let duplicate: [String: Any] = ["data": ["relationships": ["bundleIdCapabilities": ["data": [["id":"push"],["id":"push"]]]]], "included": included]
        XCTAssertThrowsError(try MemoryCapability.updatedCapabilities(duplicate))
        let paginated: [String: Any] = ["data": ["relationships": ["bundleIdCapabilities": ["data": [[String: Any]](), "links": ["next":"another-page"]]]], "included": included]
        XCTAssertThrowsError(try MemoryCapability.updatedCapabilities(paginated))
    }
    func testUnrelatedIncludedMemoryCapabilityDoesNotCount() {
        var value = snapshot(enabled: true)
        value["data"] = ["relationships": ["bundleIdCapabilities": ["data": [["id":"push","type":"bundleIdCapabilities"]]]]]
        XCTAssertFalse(MemoryCapability.isEnabled(value))
    }

}
