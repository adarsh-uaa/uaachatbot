export const useSb = () => useNuxtApp().$supabase as any

export const useAuth = () => {
  const sb = useSb()
  const session = useState<any>('session', () => null)
  const profile = useState<any>('profile', () => null)
  const perms = useState<string[]>('perms', () => [])
  const ready = useState<boolean>('authReady', () => false)

  async function load() {
    const { data } = await sb.auth.getSession()
    session.value = data.session
    if (data.session) {
      const uid = data.session.user.id
      const [p, pm, me] = await Promise.all([
        sb.from('staff_public').select('*').eq('id', uid).maybeSingle(),
        sb.rpc('my_permissions'),
        sb.from('profiles').select('real_name, team_id').eq('id', uid).maybeSingle()
      ])
      profile.value = p.data ? { ...p.data, real_name: me.data?.real_name, team_id: me.data?.team_id || p.data.team_id } : null
      perms.value = pm.data || []
    } else { profile.value = null; perms.value = [] }
    ready.value = true
  }
  async function login(email: string, password: string) {
    const { error } = await sb.auth.signInWithPassword({ email, password })
    if (error) throw error
    await load()
  }
  async function logout() {
    await sb.auth.signOut()
    session.value = null; profile.value = null; perms.value = []
    navigateTo('/login')
  }
  const can = (p: string) => perms.value.includes(p)
  return { session, profile, perms, ready, load, login, logout, can }
}

// pseudo names for everyone; "pseudo (real)" for people with users.view_real
export const useStaff = () => {
  const sb = useSb()
  const { can } = useAuth()
  const map = useState<Record<string, any>>('staffMap', () => ({}))
  async function load() {
    const { data } = await sb.from('staff_public').select('*')
    const m: Record<string, any> = {}
    ;(data || []).forEach((s: any) => (m[s.id] = { ...s }))
    if (can('users.view_real')) {
      const r = await sb.from('profiles').select('id,real_name,team_id')
      ;(r.data || []).forEach((p: any) => {
        if (m[p.id]) {
          m[p.id].real_name = p.real_name
          if (p.team_id) m[p.id].team_id = p.team_id
        }
      })
    }
    map.value = m
  }
  const label = (id?: string | null) => {
    const s = id ? map.value[id] : null
    if (!s) return '—'
    return s.real_name ? `${s.pseudo_name} (${s.real_name})` : s.pseudo_name
  }
  const list = computed(() => Object.values(map.value).filter((s: any) => s.is_active))
  return { map, load, label, list }
}

export const useTeams = () => {
  const sb = useSb()
  const auth = useAuth()
  const teams = useState<any[]>('teamsList', () => [])

  const DEFAULT_TEAMS = [
    { id: '11111111-1111-4111-8111-111111111111', name: 'Passenger Assistance (PRM)', description: 'Wheelchair, mobility and dedicated passenger assistance services', color: '#0f7c86' },
    { id: '22222222-2222-4222-8222-222222222222', name: 'Customer Care & Enquiries', description: 'General airport enquiries, flight info, check-in, and lost property', color: '#1f7a4d' },
    { id: '33333333-3333-4333-8333-333333333333', name: 'Operations & Dispatch', description: 'Airside coordination, terminal dispatch, and escalation handling', color: '#b45309' },
    { id: '44444444-4444-4444-8444-444444444444', name: 'Baggage & Lost Property', description: 'Luggage retrieval, delayed baggage, and items lost in terminal', color: '#6366f1' }
  ]

  async function load() {
    try {
      const { data, error } = await sb.from('teams').select('*').order('name')
      if (!error && data && data.length > 0) {
        teams.value = data
        return
      }
      if (!error && data && data.length === 0) {
        // Seed default teams if table exists but empty
        await sb.from('teams').insert(DEFAULT_TEAMS.map(t => ({ name: t.name, description: t.description, color: t.color })))
        const reloaded = await sb.from('teams').select('*').order('name')
        if (reloaded.data && reloaded.data.length > 0) {
          teams.value = reloaded.data
          return
        }
      }
    } catch {
      // Table may not exist yet
    }
    // Fallback to default airport teams so dropdowns and views are never empty
    if (teams.value.length === 0) {
      teams.value = DEFAULT_TEAMS
    }
  }

  async function createTeam(name: string, description: string, color = '#0f7c86') {
    const { data, error } = await sb.from('teams').insert({ name, description, color }).select().single()
    if (error) {
      // If table doesn't exist yet, add locally
      const local = { id: 'team-' + Date.now(), name, description, color }
      teams.value = [...teams.value, local]
      return local
    }
    await load()
    return data
  }

  async function updateTeam(id: string, updates: Partial<{ name: string, description: string, color: string, lead_id: string | null }>) {
    const { data, error } = await sb.from('teams').update(updates).eq('id', id).select().single()
    if (error) {
      teams.value = teams.value.map(t => t.id === id ? { ...t, ...updates } : t)
      return { id, ...updates }
    }
    await load()
    return data
  }

  async function deleteTeam(id: string) {
    const { error } = await sb.from('teams').delete().eq('id', id)
    if (error) {
      teams.value = teams.value.filter(t => t.id !== id)
      return
    }
    await load()
  }

  async function createUser(payload: {
    email: string
    password: string
    real_name: string
    pseudo_name: string
    role?: string
    team_id?: string | null
    email_confirm?: boolean
  }) {
    const { email, password, real_name, pseudo_name, role = 'employee', team_id = null, email_confirm = true } = payload

    // 1. First attempt: call Supabase RPC admin_create_user
    const rpcRes = await sb.rpc('admin_create_user', {
      p_email: email,
      p_password: password,
      p_real_name: real_name,
      p_pseudo_name: pseudo_name,
      p_role: role,
      p_team_id: team_id,
      p_email_confirm: email_confirm
    })

    if (!rpcRes.error) {
      return rpcRes.data
    }

    // 2. Second attempt: if RPC not found or failed, try server API route (if running SSR/Node)
    try {
      const session = auth.session.value
      const token = session?.access_token
      const res = await $fetch<any>('/api/users/create', {
        method: 'POST',
        headers: token ? { Authorization: `Bearer ${token}` } : {},
        body: { email, password, real_name, pseudo_name, role, team_id, email_confirm }
      })
      if (res?.user) return res.user
    } catch (apiErr: any) {
      // If both fail, throw the original or most relevant error
      const msg = rpcRes.error?.message || apiErr?.data?.message || apiErr?.message
      if (msg?.includes('function admin_create_user') || msg?.includes('404')) {
        throw new Error('Database function "admin_create_user" not found. Please run migration 005_admin_create_user.sql in the Supabase SQL Editor.')
      }
      throw new Error(msg || 'Failed to create user')
    }

    throw new Error(rpcRes.error?.message || 'Failed to create user')
  }

  return { teams, load, createTeam, updateTeam, deleteTeam, createUser }
}

export const useToast = () => {
  const toast = useState<{ msg: string, kind: string } | null>('toast', () => null)
  let t: any
  const show = (msg: string, kind = 'ok') => {
    toast.value = { msg, kind }
    clearTimeout(t); t = setTimeout(() => (toast.value = null), 4000)
  }
  return { toast, show }
}

export const fmt = (d?: string | null) => d ? new Date(d).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—'
export const ago = (d: string) => {
  const m = Math.round((Date.now() - new Date(d).getTime()) / 60000)
  if (m < 1) return 'just now'
  if (m < 60) return `${m} min ago`
  if (m < 1440) return `${Math.round(m / 60)} h ago`
  return `${Math.round(m / 1440)} d ago`
}
export const copy = async (text: string) => { try { await navigator.clipboard.writeText(text); return true } catch { return false } }
