import XCTest

extension FlowTests {
    static let __allTests = [
        ("testSubscription", testSubscription),
        ("testTeamSubscription", testTeamSubscription),
        ("testTeamMemberSignupForNotLoggedIn", testTeamMemberSignupForNotLoggedIn),
        ("testChangingProfileUpdatesEmailWithRecurly", testChangingProfileUpdatesEmailWithRecurly),
        ("testChangingProfileDoesNotUpdateRecurlyWithoutRecurlyAccount", testChangingProfileDoesNotUpdateRecurlyWithoutRecurlyAccount)
    ]
}

extension RouteTests {
    static let __allTests = [
        ("testLandingPages", testLandingPages),
    ]
}

extension TaskTests {
    static let __allTests = [
        ("testSyncTeamMembersBillsAllTeamMembersForStandardUser", testSyncTeamMembersBillsAllTeamMembersForStandardUser),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(FlowTests.__allTests),
        testCase(RouteTests.__allTests),
        testCase(TaskTests.__allTests),
    ]
}
#endif
