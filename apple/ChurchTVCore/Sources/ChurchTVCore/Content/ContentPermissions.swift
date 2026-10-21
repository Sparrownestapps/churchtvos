import Foundation

/// Who may create and edit content. Mirrors the database rules `can_edit_content`, `has_module` and `in_site_scope`
/// (supabase/migrations/20261013000001_foundation.sql) and App.tsx on the website.
///  - Owners, admins and editors may edit; operators may only control screens.
///  - Owners and admins have every module and every site; an editor needs the module in `modules`.
///  - Site scope: `siteIds == nil` means all sites; otherwise only those sites. Church-wide content (site nil) needs all sites.
public enum ContentPermissions {
    public static func canEditRole(_ role: Role) -> Bool { role == .owner || role == .admin || role == .editor }
    public static func isAdmin(_ role: Role) -> Bool { role == .owner || role == .admin }

    /// May this member edit content of `module` (ignoring site scope)? `modules` is the member's module list.
    public static func canEditContent(role: Role, modules: [AppModule], module: AppModule) -> Bool {
        canEditRole(role) && (isAdmin(role) || modules.contains(module))
    }

    /// The modules a member can create content in. `modules` should already be limited to what the church has live
    /// (that is what `ChurchAccess.modules` is). Order: Kids, Signage, Slides.
    public static func editableModules(role: Role, modules: [AppModule]) -> [AppModule] {
        guard canEditRole(role) else { return [] }
        return AppModule.allCases.filter { modules.contains($0) }
    }

    /// Does the member work with all sites (so "All sites" may be offered)? Admins and owners always do.
    public static func hasAllSites(role: Role, siteIds: [UUID]?) -> Bool { isAdmin(role) || siteIds == nil }

    /// May the member edit content that belongs to `siteId` (nil = church-wide)? Same as `in_site_scope`.
    public static func inSiteScope(role: Role, siteIds: [UUID]?, siteId: UUID?) -> Bool {
        if hasAllSites(role: role, siteIds: siteIds) { return true }
        guard let siteId, let siteIds else { return false }
        return siteIds.contains(siteId)
    }

    /// Full check for one item (role, module and site).
    public static func canEditContent(role: Role, modules: [AppModule], siteIds: [UUID]?, module: AppModule, siteId: UUID?) -> Bool {
        canEditContent(role: role, modules: modules, module: module) && inSiteScope(role: role, siteIds: siteIds, siteId: siteId)
    }

    /// The sites the member can pick from: all of them for "all sites" members, otherwise only their own.
    public static func selectableSites(role: Role, siteIds: [UUID]?, allSites: [Site]) -> [Site] {
        if hasAllSites(role: role, siteIds: siteIds) { return allSites }
        return allSites.filter { siteIds?.contains($0.id) ?? false }
    }

    /// The scope a new item starts with: church-wide for "all sites" members, otherwise the member's first site (`useDefaultScope`).
    public static func defaultSiteId(role: Role, siteIds: [UUID]?, allSites: [Site]) -> UUID? {
        if hasAllSites(role: role, siteIds: siteIds) { return nil }
        return selectableSites(role: role, siteIds: siteIds, allSites: allSites).first?.id
    }
}

public extension ChurchAccess {
    /// Modules this member can create content in (empty for operators).
    var editableModules: [AppModule] { ContentPermissions.editableModules(role: role, modules: modules) }
    func canEditContent(_ module: AppModule) -> Bool { ContentPermissions.canEditContent(role: role, modules: modules, module: module) }
    /// The "Create" section is shown only when this is true: an editor or above in a church with Kids, Signage or Slides live.
    var showsCreateSection: Bool { !editableModules.isEmpty }
    var hasAllSites: Bool { ContentPermissions.hasAllSites(role: role, siteIds: siteIds) }
    func selectableSites(from all: [Site]) -> [Site] { ContentPermissions.selectableSites(role: role, siteIds: siteIds, allSites: all) }
    func defaultSiteId(from all: [Site]) -> UUID? { ContentPermissions.defaultSiteId(role: role, siteIds: siteIds, allSites: all) }
}
