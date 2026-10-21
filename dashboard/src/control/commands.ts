import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'

export type CommandName = 'next' | 'previous' | 'jump' | 'blank' | 'stop' | 'start' | 'message' | 'clear_message'
export type Result = { ok: true; id: number } | { ok: false; error: string }

/** Sends one command through the server function. Never throws; errors come back readable. */
export async function sendCommand(screenId: string, command: CommandName, payload: Record<string, unknown> = {}): Promise<Result> {
  try {
    const { data, error } = await supabase.rpc('send_screen_command', { p_screen_id: screenId, p_command: command, p_payload: payload })
    if (error) return { ok: false, error: error.message }
    return { ok: true, id: Number(data) }
  } catch (e) {
    return { ok: false, error: (e as Error).message || 'Could not reach the server' }
  }
}

export type LogEntry = { id: number; at: Date; label: string; ok: boolean; error?: string }

/**
 * Sending for one open remote: one command at a time, a short pause after each (no double sends),
 * a log of recent commands, and a status refresh about 1.5 seconds later.
 */
export function useSender(screenId: string, refresh: () => void) {
  const [busy, setBusy] = useState<string | null>(null)
  const [cool, setCool] = useState(false)
  const [log, setLog] = useState<LogEntry[]>([])
  const seq = useRef(0)
  const timers = useRef<number[]>([])
  const lock = useRef(false)

  useEffect(
    () => () => {
      timers.current.forEach(clearTimeout)
    },
    [],
  )

  const run = useCallback(
    async (label: string, command: CommandName, payload: Record<string, unknown> = {}): Promise<boolean> => {
      if (lock.current) return false
      lock.current = true
      setBusy(label)
      const res = await sendCommand(screenId, command, payload)
      setBusy(null)
      setCool(true)
      timers.current.push(
        window.setTimeout(() => {
          lock.current = false
          setCool(false)
        }, 300),
        window.setTimeout(refresh, 1500),
      )
      setLog((l) => [{ id: ++seq.current, at: new Date(), label, ok: res.ok, error: res.ok ? undefined : res.error }, ...l].slice(0, 8))
      return res.ok
    },
    [screenId, refresh],
  )

  return { run, busy, disabled: !!busy || cool, log }
}
