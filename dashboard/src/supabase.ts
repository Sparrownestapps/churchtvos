import { createClient } from '@supabase/supabase-js'

export const SUPABASE_URL: string = import.meta.env.VITE_SUPABASE_URL || 'https://gqkefjngblgomuovaivj.supabase.co'
// Publishable key: safe in the browser; row-level security decides what each login can do.
export const SUPABASE_KEY: string =
  import.meta.env.VITE_SUPABASE_KEY || 'sb_publishable_NdKbJRGxQykmJuV9OTLdXg_qkKSwlQy'

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)
