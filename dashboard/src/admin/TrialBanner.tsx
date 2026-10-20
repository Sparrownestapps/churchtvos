import { useState } from 'react'
import { useApp } from '../context'
import { SUPPORT_EMAIL } from '../links'
import { entitled } from '../lib'
import './../admin.css'

const DAY = 86_400_000
const KEY = 'churchtvos.trialBannerDismissed'

/** Slim notice for church owners/admins (and the platform admin viewing as them) about a trial ending, an ended trial, or a paused account. */
export default function TrialBanner() {
  const { org, entitlements, isAdmin } = useApp()
  const [dismissed, setDismissed] = useState(() => {
    try {
      return sessionStorage.getItem(KEY) === org.id
    } catch {
      return false
    }
  })
  if (!isAdmin) return null

  const contact = (
    <>
      {' '}
      Contact <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> to continue.
    </>
  )

  if (org.status === 'suspended')
    return (
      <div className="adm-banner bad" role="status">
        This account is paused. Contact <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
      </div>
    )

  const live = entitlements.some((e) => entitled(e, org.status))
  const trials = entitlements.filter((e) => e.status === 'trialing')
  if (!live && trials.some((e) => e.current_period_end && new Date(e.current_period_end).getTime() <= Date.now()))
    return <div className="adm-banner bad" role="status">Your free trial has ended.{contact}</div>

  const ending = trials
    .filter((e) => entitled(e, org.status) && e.current_period_end && new Date(e.current_period_end).getTime() - Date.now() <= 7 * DAY)
    .map((e) => new Date(e.current_period_end as string))
    .sort((a, b) => a.getTime() - b.getTime())[0]
  if (!ending || dismissed) return null
  const n = Math.max(Math.ceil((ending.getTime() - Date.now()) / DAY), 0)
  return (
    <div className="adm-banner warn" role="status">
      <span>
        Your free trial ends in {n} day{n === 1 ? '' : 's'} ({ending.toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' })}).{contact}
      </span>
      <button
        className="link"
        aria-label="Dismiss"
        onClick={() => {
          setDismissed(true)
          try {
            sessionStorage.setItem(KEY, org.id)
          } catch {
            /* not remembered */
          }
        }}
      >
        ✕
      </button>
    </div>
  )
}
