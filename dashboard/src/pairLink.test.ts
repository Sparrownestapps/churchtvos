import { describe, expect, it } from 'vitest'
import { friendlyPairError, isPairPath, pairCodeFromSearch } from './pairLink'

describe('pair link', () => {
  it('reads and normalises the code', () => {
    expect(pairCodeFromSearch('?code=TFWK5H')).toBe('TFWK5H')
    expect(pairCodeFromSearch('?code=tfw%20k5h')).toBe('TFWK5H')
    expect(pairCodeFromSearch('?code=abc')).toBeNull()
    expect(pairCodeFromSearch('')).toBeNull()
  })
  it('matches the path', () => {
    expect(isPairPath('/pair')).toBe(true)
    expect(isPairPath('/pair/')).toBe(true)
    expect(isPairPath('/')).toBe(false)
  })
  it('explains unknown codes', () => {
    expect(friendlyPairError('No TV is showing code ABC123')).toMatch(/isn't showing/)
  })
})
