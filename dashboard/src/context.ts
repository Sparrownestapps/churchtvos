import { createContext, useContext } from 'react'
import type { Entitlement, Location, Membership, Module, ModuleDef, Organization, Role, Site } from './types'

export type AppState = {
  userId: string
  email: string
  org: Organization
  orgs: Organization[]
  switchOrg: (id: string) => void
  startCreateOrg: () => void
  /** Reloads organizations (e.g. after a name or branding change). */
  reloadOrgs: () => void
  isPlatformAdmin: boolean
  membership: Membership | null
  /** Effective role (platform admins count as owners). */
  role: Role
  /** Owner / admin (or platform admin): manages people, sites, screens. */
  isAdmin: boolean
  /** Owner / admin / editor: may edit content. */
  canEditRole: boolean
  entitlements: Entitlement[]
  /** Available applications from the `modules` registry (static fallback if it can't be read). */
  modules: ModuleDef[]
  /** Display name of an application id. */
  moduleName: (id: string) => string
  /** The member has been given this module. */
  hasModule: (m: Module) => boolean
  /** The member has it AND the church's plan enables it. */
  moduleOn: (m: Module) => boolean
  /** Member can see/edit all sites. */
  allSites: boolean
  /** Sites this member can work in. */
  mySites: Site[]
  /** Can edit this module's content for this site (null = shared with all sites)? */
  canEditContent: (m: Module, siteId: string | null) => boolean
  sites: Site[]
  locations: Location[]
  reloadOrg: () => void
  signOut: () => void
}

export const AppContext = createContext<AppState>(null!)
export const useApp = () => useContext(AppContext)
