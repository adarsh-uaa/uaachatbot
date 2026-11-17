import { createClient } from '@supabase/supabase-js'

export default defineNuxtPlugin(() => {
  const cfg = useRuntimeConfig().public
  const supabase = createClient(cfg.supabaseUrl as string, cfg.supabaseKey as string, {
    auth: { persistSession: true, autoRefreshToken: true },
    realtime: {
      params: {
        eventsPerSecond: 10
      }
    }
  })

  // Whenever auth state changes (login, token refresh), immediately authenticate Realtime socket
  supabase.auth.onAuthStateChange(async (_event, session) => {
    if (session?.access_token && supabase.realtime) {
      try {
        await supabase.realtime.setAuth(session.access_token)
      } catch {}
    }
  })

  return { provide: { supabase } }
})
