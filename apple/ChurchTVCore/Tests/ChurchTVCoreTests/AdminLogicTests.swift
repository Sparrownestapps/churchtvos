import XCTest
@testable import ChurchTVCore

final class AdminLogicTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let org = UUID()
    func d(_ n: Double) -> Date { now.addingTimeInterval(n * 86400) }
    func ent(_ status: String, limit: Int = 2, plan: String = "standard", end: Double? = nil, grace: Double? = nil, module: String = "kids") -> AdminEnt {
        AdminEnt(module: module, status: status, tvLimit: limit, plan: plan, currentPeriodEnd: end.map(d), graceEndsAt: grace.map(d))
    }
    func church(_ name: String = "A", status: OrgStatus = .active, reviewed: Bool = true, ents: [AdminEnt] = [], owners: [String] = [], created: Double = -10, members: Int = 1, bytes: Int64 = 0, seen: Double? = nil, screens: Int = 0) -> AdminOrg {
        AdminOrg(id: UUID(), name: name, slug: name.lowercased(), createdAt: d(created), status: status, reviewedAt: reviewed ? d(created) : nil, ownerEmails: owners,
                 memberCount: members, screenCount: screens, lastSeenAt: seen.map(d), storageBytes: bytes, entitlements: ents)
    }

    func testLiveRuleAndChips() {
        XCTAssertTrue(AdminLogic.isLive(ent("active"), .active, now: now))
        XCTAssertFalse(AdminLogic.isLive(ent("active"), .suspended, now: now))
        XCTAssertTrue(AdminLogic.isLive(ent("trialing", end: 3), .active, now: now)); XCTAssertFalse(AdminLogic.isLive(ent("trialing", end: -1), .active, now: now))
        XCTAssertTrue(AdminLogic.isLive(ent("past_due", grace: 2), .active, now: now)); XCTAssertFalse(AdminLogic.isLive(ent("past_due"), .active, now: now))
        XCTAssertEqual(AdminLogic.planChip(ent("trialing", end: 12), .active, now: now).text, "Live trial 12d left")
        XCTAssertEqual(AdminLogic.planChip(ent("trialing", end: 12), .active, now: now).tone, .ok)
        XCTAssertEqual(AdminLogic.planChip(ent("trialing", end: 5), .active, now: now).tone, .warn)
        XCTAssertEqual(AdminLogic.planChip(ent("trialing", end: -2), .active, now: now).text, "Expired")
        XCTAssertEqual(AdminLogic.planChip(ent("trialing"), .active, now: now).text, "Live trial")
        XCTAssertEqual(AdminLogic.planChip(ent("active", plan: "internal"), .active, now: now).text, "Active internal")
        XCTAssertEqual(AdminLogic.planChip(ent("active"), .suspended, now: now).tone, .off)
        XCTAssertEqual(AdminLogic.planChip(ent("past_due", grace: 1), .active, now: now).tone, .warn)
        XCTAssertEqual(AdminLogic.planChip(ent("canceled"), .active, now: now).text, "Canceled")
        XCTAssertEqual(AdminLogic.relDays(d(-3), now: now), "3 days ago"); XCTAssertEqual(AdminLogic.relDays(d(4), now: now), "in 4 days")
        XCTAssertEqual(AdminLogic.relDays(now, now: now), "today"); XCTAssertEqual(AdminLogic.relDays(d(-1), now: now), "1 day ago")
        XCTAssertEqual(AdminLogic.daysLeft(d(2.2), now: now), 3); XCTAssertNil(AdminLogic.daysLeft(nil, now: now))
    }

    func testBucketsAndLimit() {
        let fresh = church("New", reviewed: false, ents: [ent("trialing", end: 20)])
        let ending = church("Ending", ents: [ent("trialing", end: 4)])
        let paid = church("Paid", ents: [ent("active", limit: 10), ent("trialing", limit: 3, end: 5, module: "slides")])
        let expired = church("Expired", ents: [ent("trialing", end: -3)])
        let none = church("None")
        let susp = church("Susp", status: .suspended, ents: [ent("active")])
        let all = [fresh, ending, paid, expired, none, susp]
        func names(_ b: AdminLogic.Bucket) -> [String] { all.filter { AdminLogic.inBucket($0, b, now: now) }.map(\.name) }
        XCTAssertEqual(names(.all).count, 6)
        XCTAssertEqual(names(.new), ["New"])
        XCTAssertEqual(names(.trial), ["New", "Ending", "Paid"])
        XCTAssertEqual(names(.paid), ["Paid"])
        XCTAssertEqual(names(.expired), ["Expired", "None"])
        XCTAssertEqual(names(.suspended), ["Susp"])
        XCTAssertTrue(AdminLogic.trialEndingSoon(ending, now: now)); XCTAssertFalse(AdminLogic.trialEndingSoon(fresh, now: now)); XCTAssertFalse(AdminLogic.trialEndingSoon(expired, now: now))
        XCTAssertEqual(AdminLogic.tvLimit(paid, now: now), 10)
        XCTAssertEqual(AdminLogic.tvLimit(susp, now: now), 0)
        XCTAssertEqual(AdminLogic.tvLimit(church("T", ents: [ent("active", limit: 4), ent("canceled", limit: 99, module: "x")]), now: now), 4)
        let st = AdminLogic.stats(all, now: now)
        XCTAssertEqual(st.total, 6); XCTAssertEqual(st.fresh, 1); XCTAssertEqual(st.ending, 2); XCTAssertEqual(st.expired, 2); XCTAssertEqual(st.suspended, 1)
    }

    func testSearchSort() {
        let a = church("Alpha", owners: ["boss@alpha.org"], created: -5, members: 3, bytes: 500, seen: -1)
        let b = church("beta", created: -50, members: 9, bytes: 100, seen: -10)
        let c = church("Gamma", owners: ["x@gamma.org"], created: -1, members: 1, bytes: 900)
        let list = [a, b, c]
        func order(_ s: AdminLogic.SortKey, _ desc: Bool, search: String = "", bucket: AdminLogic.Bucket = .all) -> [String] {
            AdminLogic.rows(list, search: search, bucket: bucket, sort: s, descending: desc, now: now).map(\.name)
        }
        XCTAssertEqual(order(.created, true), ["Gamma", "Alpha", "beta"])
        XCTAssertEqual(order(.created, false), ["beta", "Alpha", "Gamma"])
        XCTAssertEqual(order(.name, false), ["Alpha", "beta", "Gamma"])           // case-insensitive
        XCTAssertEqual(order(.members, true), ["beta", "Alpha", "Gamma"])
        XCTAssertEqual(order(.media, true), ["Gamma", "Alpha", "beta"])
        XCTAssertEqual(order(.seen, true), ["Alpha", "beta", "Gamma"])            // never seen sorts last
        XCTAssertEqual(order(.name, false, search: "gamma.org"), ["Gamma"])       // owner email search
        XCTAssertEqual(order(.name, false, search: "  ALP "), ["Alpha"])
        XCTAssertEqual(order(.name, false, search: "zzz"), [])
    }

    func testPresets() throws {
        let cur = ent("active", limit: 10)
        let trial = try XCTUnwrap(AdminLogic.applyPreset(.trial, orgId: org, module: "kids", current: nil, now: now))
        XCTAssertEqual(trial.status, "trialing"); XCTAssertEqual(trial.tvLimit, 2); XCTAssertEqual(trial.plan, "trial"); XCTAssertEqual(trial.currentPeriodEnd, d(30))
        XCTAssertNil(AdminLogic.applyPreset(.extend, orgId: org, module: "kids", current: cur, now: now))     // paid plans have no trial to extend
        let ext = try XCTUnwrap(AdminLogic.applyPreset(.extend, orgId: org, module: "kids", current: ent("trialing", limit: 0, end: 3), now: now))
        XCTAssertEqual(ext.currentPeriodEnd, d(17)); XCTAssertEqual(ext.tvLimit, 2)                            // from the existing end date; limit 0 becomes 2
        let expiredExt = try XCTUnwrap(AdminLogic.applyPreset(.extend, orgId: org, module: "kids", current: ent("trialing", end: -9), now: now))
        XCTAssertEqual(expiredExt.currentPeriodEnd, d(14))                                                     // from today when already over
        let internalPlan = try XCTUnwrap(AdminLogic.applyPreset(.internal, orgId: org, module: "kids", current: nil, now: now))
        XCTAssertEqual(internalPlan.tvLimit, 50); XCTAssertEqual(internalPlan.plan, "internal"); XCTAssertNil(internalPlan.currentPeriodEnd)
        XCTAssertEqual(AdminLogic.applyPreset(.standard, orgId: org, module: "kids", current: nil, now: now)?.tvLimit, 10)
        XCTAssertNil(AdminLogic.applyPreset(.cancel, orgId: org, module: "kids", current: nil, now: now))
        XCTAssertEqual(AdminLogic.applyPreset(.cancel, orgId: org, module: "kids", current: cur, now: now)?.status, "canceled")
        XCTAssertEqual(AdminLogic.applyPreset(.cancel, orgId: org, module: "kids", current: cur, now: now)?.tvLimit, 10)
        XCTAssertEqual(AdminLogic.Preset.allCases.count, 5)
    }

    func testEntitlementPayloadAndCleaning() throws {
        let row = AdminEntitlementRow(organizationId: org, module: "slides", status: "trialing", tvLimit: -4, plan: "  ", currentPeriodEnd: nil, graceEndsAt: now)
        let cleaned = AdminLogic.cleanedEntitlement(row)
        XCTAssertEqual(cleaned.tvLimit, 0); XCTAssertEqual(cleaned.plan, "standard")
        let json = String(data: try JSONEncoder().encode(cleaned), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"current_period_end\":null")); XCTAssertTrue(json.contains("\"grace_ends_at\":\""))
        XCTAssertTrue(json.contains("\"organization_id\":\"\(org.uuidString.lowercased())\""))
    }

    func testUpdateParamsOnlySendWhatChanges() throws {
        func json(_ c: AdminOrgChange) throws -> String { String(data: try JSONEncoder().encode(AdminUpdateParams(org: org, change: c)), encoding: .utf8)! }
        let notes = try json(AdminOrgChange(notes: "hello"))
        XCTAssertTrue(notes.contains("p_notes")); XCTAssertFalse(notes.contains("p_status")); XCTAssertFalse(notes.contains("p_ndi"))
        let susp = try json(AdminOrgChange(status: .suspended, reason: "unpaid"))
        XCTAssertTrue(susp.contains("\"p_status\":\"suspended\"")); XCTAssertTrue(susp.contains("p_reason"))
        XCTAssertTrue(try json(AdminOrgChange(reviewed: true)).contains("\"p_reviewed\":true"))
        XCTAssertTrue(try json(AdminOrgChange(ndi: false)).contains("\"p_ndi\":false"))
    }

    func testDecodeAdminRowFromRPC() throws {
        let json = """
        [{"id":"11111111-1111-4111-8111-111111111111","name":"Hope","slug":"hope","created_at":"2026-10-01T12:00:00.123456+00:00","status":"active","suspended_reason":null,"admin_notes":"n","reviewed_at":null,
          "owner_emails":["a@b.org"],"member_count":"3","screen_count":2,"last_seen_at":null,"media_count":5,"storage_bytes":1048576,"song_count":1,"deck_count":0,"playlist_count":4,
          "entitlements":[{"module":"kids","status":"trialing","tv_limit":2,"plan":"trial","current_period_end":"2026-11-01T00:00:00+00:00","grace_ends_at":null,"live":true}],"ndi_enabled":true}]
        """
        let orgs = try ChurchJSON.decoder().decode([AdminOrg].self, from: Data(json.utf8))
        let o = try XCTUnwrap(orgs.first)
        XCTAssertEqual(o.name, "Hope"); XCTAssertEqual(o.memberCount, 3); XCTAssertEqual(o.storageBytes, 1_048_576); XCTAssertNil(o.reviewedAt)
        XCTAssertEqual(o.entitlements.first?.tvLimit, 2); XCTAssertEqual(o.entitlements.first?.live, true); XCTAssertTrue(o.ndiEnabled); XCTAssertEqual(o.adminNotes, "n")
        // an older server without ndi_enabled and with null lists
        let old = #"[{"id":"11111111-1111-4111-8111-111111111111","name":"Old","slug":"old","created_at":"2026-10-01T12:00:00+00:00","status":"suspended","owner_emails":null,"entitlements":null}]"#
        let o2 = try XCTUnwrap(try ChurchJSON.decoder().decode([AdminOrg].self, from: Data(old.utf8)).first)
        XCTAssertEqual(o2.status, .suspended); XCTAssertFalse(o2.ndiEnabled); XCTAssertTrue(o2.entitlements.isEmpty); XCTAssertTrue(o2.ownerEmails.isEmpty)
    }

    func testDescribeAudit() throws {
        let names: (String) -> String = { $0.capitalized }
        func entry(_ action: String, _ detail: RawJSON) -> AuditEntry { AuditEntry(id: 1, at: now, action: action, detail: detail) }
        let upd = AdminLogic.describeAudit(entry("plan_update", .object(["module": .string("kids"), "from": .object(["status": .string("trialing"), "tv_limit": .number(1)]),
                                                                          "to": .object(["status": .string("active"), "tv_limit": .number(10)])])), moduleName: names)
        XCTAssertEqual(upd, "Kids: trialing 1 TV -> active 10 TVs")
        XCTAssertEqual(AdminLogic.describeAudit(entry("plan_delete", .object(["module": .string("slides"), "from": .object(["status": .string("active"), "tv_limit": .number(2)])])), moduleName: names), "Slides: removed (was active 2 TVs)")
        XCTAssertEqual(AdminLogic.describeAudit(entry("church_suspended", .object(["reason": .string("unpaid")])), moduleName: names), "Suspended: unpaid")
        XCTAssertEqual(AdminLogic.describeAudit(entry("church_suspended", .object([:])), moduleName: names), "Suspended")
        XCTAssertEqual(AdminLogic.describeAudit(entry("ndi_enabled", .object([:])), moduleName: names), "Experimental NDI sources switched ON")
        XCTAssertEqual(AdminLogic.describeAudit(entry("something_new", .null), moduleName: names), "something_new")
        XCTAssertEqual(AdminLogic.auditActions.count, 8)
    }

    func testDemoAdminConsole() async throws {
        let demo = MockService()
        var orgs = try await demo.adminListOrganizations()
        XCTAssertGreaterThanOrEqual(orgs.count, 6)
        let riverside = try XCTUnwrap(orgs.first { $0.slug == "riverside" })
        XCTAssertNil(riverside.reviewedAt)
        try await demo.adminUpdateOrganization(riverside.id, change: AdminOrgChange(reviewed: true))
        try await demo.adminUpdateOrganization(riverside.id, change: AdminOrgChange(status: .suspended, reason: "test"))
        orgs = try await demo.adminListOrganizations()
        let r = try XCTUnwrap(orgs.first { $0.id == riverside.id })
        XCTAssertNotNil(r.reviewedAt); XCTAssertEqual(r.status, .suspended); XCTAssertEqual(r.suspendedReason, "test")
        XCTAssertTrue(r.entitlements.allSatisfy { !$0.live })                          // suspended: nothing is live
        let row = try XCTUnwrap(AdminLogic.applyPreset(.standard, orgId: riverside.id, module: "kids", current: r.entitlements.first, now: Date()))
        try await demo.adminUpsertEntitlements([row])
        try await demo.adminDeleteEntitlement(organizationId: riverside.id, module: "slides")
        try await demo.adminUpdateOrganization(riverside.id, change: AdminOrgChange(status: .active))
        let after = try await demo.adminListOrganizations()
        let r2 = try XCTUnwrap(after.first { $0.id == riverside.id })
        XCTAssertEqual(r2.entitlements.map(\.module), ["kids"]); XCTAssertEqual(r2.entitlements.first?.tvLimit, 10); XCTAssertEqual(r2.entitlements.first?.live, true)
        let audit = try await demo.adminListAudit(organizationId: riverside.id, action: nil, page: 0, pageSize: 50)
        let actions = audit.map(\.action)
        XCTAssertTrue(actions.contains("church_suspended")); XCTAssertTrue(actions.contains("church_reactivated")); XCTAssertTrue(actions.contains("plan_update")); XCTAssertTrue(actions.contains("plan_delete"))
        let deletes = try await demo.adminListAudit(organizationId: riverside.id, action: "plan_delete", page: 0, pageSize: 50)
        XCTAssertEqual(deletes.count, 1)
        let screens = try await demo.adminListScreens(organizationId: riverside.id)
        XCTAssertEqual(screens.count, riverside.screenCount)
    }
}
