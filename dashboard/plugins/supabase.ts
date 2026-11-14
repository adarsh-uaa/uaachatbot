import { createClient } from '@supabase/supabase-js'

export default defineNuxtPlugin(() => {
  const cfg = useRuntimeConfig().public
  const supabase = createClient(cfg.supabaseUrl as string, cfg.supabaseKey as string, {
    auth: { persistSession: true, autoRefreshToken: true }
  })
  return { provide: { supabase } }
})
