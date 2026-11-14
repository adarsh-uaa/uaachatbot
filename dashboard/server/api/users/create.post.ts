import { createClient } from '@supabase/supabase-js'

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const { email, password, real_name, pseudo_name, role, team_id, email_confirm = true } = body || {}

  if (!email || !password || !real_name || !pseudo_name) {
    throw createError({ statusCode: 400, message: 'Missing required fields: email, password, real name, and pseudo name are required.' })
  }

  const config = useRuntimeConfig()
  const supabaseUrl = config.public.supabaseUrl || process.env.NUXT_PUBLIC_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NUXT_SUPABASE_SERVICE_ROLE_KEY

  if (!serviceKey) {
    throw createError({
      statusCode: 501,
      message: 'SUPABASE_SERVICE_ROLE_KEY is not set on the server. Please run migration 005 and use direct database RPC or configure the service role key.'
    })
  }

  // Get caller's token from Authorization header to verify permissions
  const authHeader = getHeader(event, 'authorization')
  if (!authHeader) {
    throw createError({ statusCode: 401, message: 'Unauthorized' })
  }

  const callerClient = createClient(supabaseUrl, config.public.supabaseKey || process.env.NUXT_PUBLIC_SUPABASE_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } }
  })

  // Verify caller has users.manage permission
  const { data: hasManage } = await callerClient.rpc('has_perm', { p: 'users.manage' })
  if (!hasManage) {
    throw createError({ statusCode: 403, message: 'You do not have permission (users.manage)' })
  }

  // Admin client with service role
  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })

  const { data: authData, error: authErr } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: !!email_confirm,
    user_metadata: { name: real_name }
  })

  if (authErr) {
    throw createError({ statusCode: 400, message: authErr.message })
  }

  const userId = authData.user.id

  // Upsert profile
  const { error: profErr } = await adminClient.from('profiles').upsert({
    id: userId,
    real_name,
    pseudo_name,
    role: role || 'employee',
    team_id: team_id || null,
    is_active: true
  })

  if (profErr) {
    throw createError({ statusCode: 400, message: profErr.message })
  }

  return {
    success: true,
    user: {
      id: userId,
      email,
      real_name,
      pseudo_name,
      role: role || 'employee',
      team_id: team_id || null,
      email_confirmed: !!email_confirm
    }
  }
})

