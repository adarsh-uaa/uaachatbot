import { createClient } from '@supabase/supabase-js'

export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const { user_id } = body || {}

  if (!user_id) {
    throw createError({ statusCode: 400, message: 'Missing user_id parameter' })
  }

  const config = useRuntimeConfig()
  const supabaseUrl = config.public.supabaseUrl || process.env.NUXT_PUBLIC_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NUXT_SUPABASE_SERVICE_ROLE_KEY

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

  // Get caller user ID to prevent self-deletion
  const { data: userData } = await callerClient.auth.getUser()
  if (userData?.user?.id === user_id) {
    throw createError({ statusCode: 400, message: 'You cannot delete your own account' })
  }

  // If service role key is available, perform full admin delete
  if (serviceKey) {
    const adminClient = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    })

    // Unclaim active tickets
    await adminClient.from('tickets')
      .update({ claimed_by: null, claimed_at: null, status: 'open' })
      .eq('claimed_by', user_id)
      .neq('status', 'closed')

    // Delete permissions
    await adminClient.from('user_permissions').delete().eq('user_id', user_id)

    // Unassign team lead
    await adminClient.from('teams').update({ lead_id: null }).eq('lead_id', user_id)

    // Delete profile
    await adminClient.from('profiles').delete().eq('id', user_id)

    // Delete auth user
    const { error: authErr } = await adminClient.auth.admin.deleteUser(user_id)
    if (authErr) {
      throw createError({ statusCode: 400, message: authErr.message })
    }

    return { success: true, user_id }
  }

  // Fallback: call admin_delete_user RPC through callerClient
  const { data, error } = await callerClient.rpc('admin_delete_user', { p_user_id: user_id })
  if (error) {
    throw createError({ statusCode: 400, message: error.message })
  }

  return { success: true, data }
})

