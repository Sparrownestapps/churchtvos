# Room create while pairing: contract

Shared by the web dashboard (`dashboard/src/pairRoom.ts`, `PairRoomFields.tsx`) and the Apple app. No new RPC or migration: it uses plain inserts under the existing RLS policies.

## Who may do it
Owners and admins only (`is_org_admin(organization_id)`; platform admins count). RLS: policies "admins manage sites" and "admins manage locations" (`for all`, using and with check). Editors, operators and non-members are refused (verified in a rolled-back transaction). Admins always see all sites, so site scope never blocks them. Pairing itself (`claim_screen`) is also admin-only.

## UI
Location picker gets a final option "+ New room...". If no locations exist it is preselected. Fields: Room name, Site (existing sites, final option "+ New site..."; preselected if only one site, or "new" if none), and if new site: Site name and Time zone. "Used by" module chips. Plus the existing Code and screen Name.

## Sequence
1. Validate (below). Nothing is written if invalid.
2. If new site: insert `sites`.
3. Insert `locations`.
4. `claim_screen(p_code, p_location_id, p_name)` with the new location id.
If step 4 fails, KEEP the site and room, select the new room in the picker, and show: "<Site> · <Room> was created, but the TV was not paired: <reason> The room is selected, so press Pair TV again once that is fixed." A retry must skip steps 2-3 (the picker now holds the existing location id). If step 3 fails after step 2, keep the site and select it, so a retry does not create it twice.

## Rows
`sites` insert: `organization_id` = current church, `name` = trimmed with inner whitespace collapsed, `timezone` = chosen IANA zone (trimmed). Other columns default: `id` uuid, `created_at` now().
`locations` insert: `organization_id`, `site_id`, `name` (trimmed, whitespace collapsed), `modules` = text[] of de-duplicated module ids. `id`, `created_at` default.

## Module tags
Offer the modules in the `modules` registry that are `available` and switched on for this member and church (`moduleOn`: member has it AND entitlement is active/trialing/in grace). If none are on, offer all available ones. Default selection = all the ones that are on (new churches: kids, signage; slides when entitled). Tags may be empty (the room then shows as Unassigned under Sites). Valid ids are enforced by `locations_modules_check` (`valid_modules`).

## Time zone (new site only)
Default: the church's first site's `timezone`; else the device/browser zone; else `America/Toronto` (the column default). Must be a valid IANA identifier. Existing sites keep their zone.

## Uniqueness and validation
- Room name required after trim. Unique per site, compared case-insensitively after trim/collapse (database constraint `unique (site_id, name)` is case-sensitive; the client is stricter). Same name at another site is fine.
- Site name required for a new site, unique per church, case-insensitive (db: `unique (organization_id, name)`).
- Postgres error 23505 maps to "A room with that name already exists at this site." / "A site with that name already exists. Choose it from the list."; 42501 maps to "Only owners and admins can add rooms/sites."
