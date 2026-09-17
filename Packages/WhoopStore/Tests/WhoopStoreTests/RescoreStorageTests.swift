import XCTest
import GRDB
@testable import WhoopStore

final class RescoreStorageTests: XCTestCase {
    private func workout(_ start: Int, source: String = "my-whoop-noop", sport: String = "Run") -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 900, sport: sport, source: source,
                   durationS: 900, energyKcal: 150, avgHr: 140, maxHr: 160, strain: 6,
                   distanceM: 2000, zonesJSON: "{}", notes: "custom")
    }

    func testFingerprintTracksLateStreamsAndReaddedDevice() async throws {
        let store = try await WhoopStore.inMemory()
        var previous = try await store.analysisFingerprint()
        let inserts = [
            "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('new-strap',100,65)",
            "INSERT INTO rrInterval(deviceId,ts,rrMs) VALUES ('new-strap',99,950)",
            "INSERT INTO gravitySample(deviceId,ts,x,y,z) VALUES ('new-strap',98,0,0,1)",
            "INSERT INTO rawImuSample(deviceId,ts,samples) VALUES ('new-strap',97,X'0000')"
        ]
        for sql in inserts {
            try await store.registryWriter.write { db in try db.execute(sql: sql) }
            let next = try await store.analysisFingerprint()
            XCTAssertNotEqual(next, previous)
            previous = next
        }
        let unchanged = try await store.analysisFingerprint()
        XCTAssertEqual(unchanged, previous)
        try await store.registryWriter.write { db in try db.execute(sql: "DELETE FROM rrInterval") }
        let deleted = try await store.analysisFingerprint()
        XCTAssertNotEqual(deleted, previous)
    }

    func testReplacementKeepsManualImportedAndOutOfWindowWorkouts() async throws {
        let store = try await WhoopStore.inMemory()
        let manual = workout(110, source: "manual", sport: "Badminton")
        let outside = workout(10)
        try await store.upsertWorkouts([workout(100), manual, outside], deviceId: "my-whoop-noop")
        let imported = workout(100, source: "apple-health")
        try await store.upsertWorkouts([imported], deviceId: "apple-health")
        try await store.replaceDetectedWorkouts([workout(101)], deviceId: "my-whoop-noop", from: 100, to: 1000)
        try await store.replaceDetectedWorkouts([workout(101)], deviceId: "my-whoop-noop", from: 100, to: 1000)
        let rows = try await store.workouts(deviceId: "my-whoop-noop", from: 0, to: 2000, limit: 20)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.contains(manual))
        XCTAssertTrue(rows.contains(outside))
        XCTAssertTrue(rows.contains(workout(101)))
        let imports = try await store.workouts(deviceId: "apple-health", from: 0, to: 2000, limit: 20)
        XCTAssertEqual(imports, [imported])
        try await store.replaceDetectedWorkouts([], deviceId: "my-whoop-noop", from: 100, to: 1000)
        let remaining = try await store.workouts(deviceId: "my-whoop-noop", from: 0, to: 2000, limit: 20)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains(manual))
    }

    func testInsertFailureRollsBackDeletion() async throws {
        let store = try await WhoopStore.inMemory()
        let old = workout(100)
        try await store.upsertWorkouts([old], deviceId: "my-whoop-noop")
        try await store.registryWriter.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_test_workout BEFORE INSERT ON workout
                WHEN NEW.startTs = 101 BEGIN SELECT RAISE(ABORT, 'injected write failure'); END
                """)
        }
        do {
            try await store.replaceDetectedWorkouts([workout(101)], deviceId: "my-whoop-noop", from: 0, to: 1000)
            XCTFail("Expected insert failure")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.description.contains("injected write failure"))
        }
        let rows = try await store.workouts(deviceId: "my-whoop-noop", from: 0, to: 2000, limit: 20)
        XCTAssertEqual(rows, [old])
    }

    func testReplacementCannotOverwriteManualOrImportedRowsWithTheSameKey() async throws {
        let store = try await WhoopStore.inMemory()
        let manual = workout(100, source: "manual")
        let imported = workout(200, source: "apple-health")
        try await store.upsertWorkouts([manual, imported], deviceId: "my-whoop-noop")
        try await store.replaceDetectedWorkouts(
            [workout(100), workout(200), workout(300)],
            deviceId: "my-whoop-noop", from: 0, to: 1000)
        let rows = try await store.workouts(deviceId: "my-whoop-noop", from: 0, to: 2000, limit: 20)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.contains(manual))
        XCTAssertTrue(rows.contains(imported))
        XCTAssertTrue(rows.contains(workout(300)))
    }
}
