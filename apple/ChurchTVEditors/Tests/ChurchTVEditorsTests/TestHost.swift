import SwiftUI
import ChurchTVCore
@testable import ChurchTVEditors

/// A minimal `ContentHost` for tests: the demo service and the demo church, no TVs.
@MainActor
final class TestHost: ContentHost {
    let service: any ChurchService = MockService()
    private(set) var church: ChurchAccess?
    private(set) var reloadedPlayNow = 0
    private(set) var reloadedSchedule = 0
    private(set) lazy var content = ContentModel(host: self)

    func start() async { church = try? await service.loadChurches().first }
    func choose(_ church: ChurchAccess) { self.church = church; content.reset() }
    func loadPlayNow() async { reloadedPlayNow += 1 }
    func loadSchedule() async { reloadedSchedule += 1 }
}
