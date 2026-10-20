import { useEffect } from 'react'

// A tiny shared flag so the nav (App.tsx) can ask "discard your unsaved changes?" before leaving an editor.
let dirty = false

export function setUnsaved(v: boolean) {
  dirty = v
}

/** True when it is fine to leave the current page (nothing unsaved, or the person agreed to discard). */
export function canLeave(): boolean {
  if (!dirty) return true
  if (confirm('You have unsaved changes. Leave without saving?')) {
    dirty = false
    return true
  }
  return false
}

/** While `isDirty`: the nav asks before leaving and closing the tab asks the browser. Cleared on unmount. */
export function useUnsavedGuard(isDirty: boolean) {
  useEffect(() => {
    setUnsaved(isDirty)
    if (!isDirty) return
    const warn = (e: BeforeUnloadEvent) => (e.preventDefault(), (e.returnValue = ''))
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [isDirty])
  useEffect(() => () => setUnsaved(false), [])
}
