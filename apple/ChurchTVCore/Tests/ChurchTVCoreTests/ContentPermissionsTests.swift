import XCTest
@testable import ChurchTVCore

final class ContentPermissionsTests: XCTestCase {
    func testRoles() {
        XCTAssertTrue(ContentPermissions.canEditContent(role: .owner, modules: [], module: .slides), "owners and admins have every module")
        XCTAssertTrue(ContentPermissions.canEditContent(role: .admin, modules: [], module: .kids))
        XCTAssertTrue(ContentPermissions.canEditContent(role: .editor, modules: [.kids], module: .kids))
        XCTAssertFalse(ContentPermissions.canEditContent(role: .editor, modules: [.kids], module: .slides), "an editor needs the module")
        XCTAssertFalse(ContentPermissions.canEditContent(role: .operator, modules: AppModule.allCases, module: .kids), "operators cannot edit")
        XCTAssertEqual(ContentPermissions.editableModules(role: .editor, modules: [.slides, .kids]), [.kids, .slides])
        XCTAssertEqual(ContentPermissions.editableModules(role: .operator, modules: AppModule.allCases), [])
    }

    func testSiteScope() {
        let a = UUID(), b = UUID(), c = UUID()
        // all sites
        XCTAssertTrue(ContentPermissions.hasAllSites(role: .editor, siteIds: nil))
        XCTAssertTrue(ContentPermissions.inSiteScope(role: .editor, siteIds: nil, siteId: nil))
        XCTAssertTrue(ContentPermissions.inSiteScope(role: .editor, siteIds: nil, siteId: a))
        // limited editor: only their sites, and never church-wide content
        XCTAssertFalse(ContentPermissions.hasAllSites(role: .editor, siteIds: [a, b]))
        XCTAssertTrue(ContentPermissions.inSiteScope(role: .editor, siteIds: [a, b], siteId: a))
        XCTAssertFalse(ContentPermissions.inSiteScope(role: .editor, siteIds: [a, b], siteId: c))
        XCTAssertFalse(ContentPermissions.inSiteScope(role: .editor, siteIds: [a, b], siteId: nil))
        XCTAssertFalse(ContentPermissions.inSiteScope(role: .editor, siteIds: [], siteId: a))
        // admins are never limited (in_site_scope)
        XCTAssertTrue(ContentPermissions.inSiteScope(role: .admin, siteIds: [a], siteId: c))
        let sites = [Site(id: a, name: "A"), Site(id: b, name: "B"), Site(id: c, name: "C")]
        XCTAssertEqual(ContentPermissions.selectableSites(role: .editor, siteIds: [b], allSites: sites).map(\.name), ["B"])
        XCTAssertEqual(ContentPermissions.selectableSites(role: .editor, siteIds: nil, allSites: sites).count, 3)
        XCTAssertNil(ContentPermissions.defaultSiteId(role: .editor, siteIds: nil, allSites: sites))
        XCTAssertEqual(ContentPermissions.defaultSiteId(role: .editor, siteIds: [b, c], allSites: sites), b)
        XCTAssertTrue(ContentPermissions.canEditContent(role: .editor, modules: [.kids], siteIds: [a], module: .kids, siteId: a))
        XCTAssertFalse(ContentPermissions.canEditContent(role: .editor, modules: [.kids], siteIds: [a], module: .kids, siteId: nil))
    }

    func testCreateSectionVisibility() {
        let org = Organization(id: UUID(), name: "C")
        XCTAssertTrue(ChurchAccess(organization: org, role: .editor, modules: [.signage]).showsCreateSection)
        XCTAssertTrue(ChurchAccess(organization: org, role: .owner, modules: [.slides]).showsCreateSection)
        XCTAssertFalse(ChurchAccess(organization: org, role: .operator, modules: AppModule.allCases).showsCreateSection)
        XCTAssertFalse(ChurchAccess(organization: org, role: .admin, modules: []).showsCreateSection, "no module live")
    }
}
