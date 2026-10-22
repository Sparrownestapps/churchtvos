import { useState, type FormEvent } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { locationLabel } from '../lib'
import { LocationOptions } from '../ui'
import { friendlyPairError } from '../pairLink'

/** Opened from the QR code on a TV (/pair?code=...): confirm the code, choose a location, claim it, then go to Screens. */
export default function PairPage({ initialCode, onDone }: { initialCode: string | null; onDone: () => void }) {
  const { isAdmin, locations, sites, org } = useApp()
  const [code, setCode] = useState(initialCode ?? '')
  const [locationId, setLocationId] = useState(locations.length === 1 ? locations[0].id : '')
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [paired, setPaired] = useState<string | null>(null)

  if (!isAdmin)
    return (
      <div className="card stack-sm">
        <h3>Pair a TV</h3>
        <p className="error">Only owners and admins of {org.name} can pair a TV. Ask one of them to scan the code, or to give you admin access.</p>
        <button className="btn" onClick={onDone}>Go to Screens</button>
      </div>
    )

  async function pair(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { error } = await supabase.rpc('claim_screen', {
      p_code: code.replace(/\s/g, ''),
      p_location_id: locationId,
      p_name: name.trim() || null,
    })
    setBusy(false)
    if (error) return setError(friendlyPairError(error.message))
    setPaired(locationLabel(locations.find((l) => l.id === locationId), sites))
    setTimeout(onDone, 1500)
  }

  if (paired)
    return (
      <div className="card stack-sm">
        <h3>Paired</h3>
        <p className="notice">The TV is paired with {paired}. It will update in a few seconds. Taking you to Screens…</p>
      </div>
    )

  return (
    <form className="card stack-sm" onSubmit={pair}>
      <h3>Pair a TV</h3>
      <p className="muted">Pairing with {org.name}. Check the code matches the one on the TV, choose where the TV is, and press Pair TV.</p>
      <div className="row wrap">
        <label className="field">
          <span>Code on the TV</span>
          <input className="code-input" value={code} maxLength={7} onChange={(e) => setCode(e.target.value.toUpperCase())} autoCapitalize="characters" autoComplete="off" required />
        </label>
        <label className="field grow">
          <span>Location</span>
          <select value={locationId} onChange={(e) => setLocationId(e.target.value)} required>
            <option value="">Choose…</option>
            <LocationOptions />
          </select>
        </label>
        <label className="field grow">
          <span>Name (optional)</span>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Lobby left" />
        </label>
      </div>
      {locations.length === 0 && <p className="muted">Add a location under Sites & Locations first.</p>}
      {error && <p className="error">{error}</p>}
      <div className="row">
        <button className="btn primary" disabled={busy}>{busy ? 'Pairing…' : 'Pair TV'}</button>
        <button type="button" className="btn" onClick={onDone}>Cancel</button>
      </div>
    </form>
  )
}
