<script setup lang="ts">
definePageMeta({ perm: 'dashboard.view' })

const sb = useSb()
const auth = useAuth()
const staff = useStaff()
const { show } = useToast()

const activeTab = ref<'members' | 'roles'>('members')
const canManage = computed(() => auth.can('users.manage'))
const canViewReal = computed(() => auth.can('users.view_real') || auth.can('users.manage'))

const users = ref<any[]>([])
const perms = ref<any[]>([])
const rolePerms = ref<any[]>([])
const overrides = ref<any[]>([])
const ticketStats = ref<Record<string, number>>({})
const sel = ref<any>(null)
const roles = ['admin', 'manager', 'teamlead', 'employee']

// Filters
const search = ref('')
const filterRole = ref('')

// Add User Modal State
const showAddUser = ref(false)
const addingUser = ref(false)
const showPassword = ref(false)
const userForm = reactive({
  email: '',
  password: '',
  real_name: '',
  pseudo_name: '',
  role: 'employee',
  email_confirm: true
})

async function load() {
  await staff.load()

  const [uRes, pRes, rpRes, upRes, tktRes] = await Promise.all([
    canViewReal.value
      ? sb.from('profiles').select('*').order('created_at')
      : sb.from('staff_public').select('*').order('created_at'),
    sb.from('permissions').select('*').order('key'),
    sb.from('role_permissions').select('*'),
    sb.from('user_permissions').select('*'),
    sb.from('tickets').select('claimed_by, status').neq('status', 'closed')
  ])

  users.value = (uRes.data || []).map((u: any) => ({ ...u }))
  perms.value = pRes.data || []
  rolePerms.value = rpRes.data || []
  overrides.value = upRes.data || []

  // Count active tickets per user
  const tMap: Record<string, number> = {}
  ;(tktRes.data || []).forEach((t: any) => {
    if (t.claimed_by) tMap[t.claimed_by] = (tMap[t.claimed_by] || 0) + 1
  })
  ticketStats.value = tMap

  if (sel.value) {
    sel.value = users.value.find(u => u.id === sel.value.id) || null
  }
}

onMounted(load)

// Generator for strong temporary passwords
function generatePassword() {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#$%'
  let pw = ''
  for (let i = 0; i < 12; i++) {
    pw += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  userForm.password = pw
  showPassword.value = true
}

function autoFillPseudo() {
  if (userForm.real_name && !userForm.pseudo_name) {
    const parts = userForm.real_name.trim().split(/\s+/)
    if (parts.length > 1) {
      userForm.pseudo_name = `${parts[0]} ${parts[parts.length - 1][0]}.`
    } else {
      userForm.pseudo_name = parts[0] || ''
    }
  }
}

function openAddUser() {
  userForm.email = ''
  userForm.password = ''
  userForm.real_name = ''
  userForm.pseudo_name = ''
  userForm.role = 'employee'
  userForm.email_confirm = true
  generatePassword()
  showAddUser.value = true
}

async function submitAddUser() {
  if (!userForm.email || !userForm.password || !userForm.real_name || !userForm.pseudo_name) {
    show('Please fill in email, password, real name, and pseudo name', 'err')
    return
  }
  addingUser.value = true
  try {
    // 1. Call admin_create_user RPC
    const rpcRes = await sb.rpc('admin_create_user', {
      p_email: userForm.email,
      p_password: userForm.password,
      p_real_name: userForm.real_name,
      p_pseudo_name: userForm.pseudo_name,
      p_role: userForm.role,
      p_team_id: null,
      p_email_confirm: userForm.email_confirm
    })

    if (rpcRes.error) {
      // 2. Fallback to API route if running with service role key
      try {
        const session = auth.session.value
        await $fetch('/api/users/create', {
          method: 'POST',
          headers: session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {},
          body: {
            email: userForm.email,
            password: userForm.password,
            real_name: userForm.real_name,
            pseudo_name: userForm.pseudo_name,
            role: userForm.role,
            email_confirm: userForm.email_confirm
          }
        })
      } catch (apiErr: any) {
        throw new Error(rpcRes.error.message || apiErr?.data?.message || 'Failed to create user')
      }
    }

    show(`User "${userForm.pseudo_name}" created successfully with role ${userForm.role}! (Email Verified)`, 'ok')
    showAddUser.value = false
    await load()
  } catch (err: any) {
    show(err.message || 'Failed to create user', 'err')
  } finally {
    addingUser.value = false
  }
}

async function saveUser(u: any) {
  if (!canManage.value) return
  const payload: any = {
    pseudo_name: u.pseudo_name,
    role: u.role,
    is_active: u.is_active
  }
  if (canViewReal.value && u.real_name) {
    payload.real_name = u.real_name
  }
  const { error } = await sb.from('profiles').update(payload).eq('id', u.id)
  if (error) {
    show(error.message.includes('unique') ? 'That pseudo name is already taken' : error.message, 'err')
  } else {
    show(`Saved changes for ${u.pseudo_name} (Role: ${u.role})`, 'ok')
    await load()
  }
}

// Role and Permission overrides
const roleHas = (r: string, p: string) => rolePerms.value.some(x => x.role === r && x.permission === p)
async function toggleRole(r: string, p: string) {
  if (!canManage.value) return
  if (roleHas(r, p)) await sb.from('role_permissions').delete().eq('role', r).eq('permission', p)
  else await sb.from('role_permissions').insert({ role: r, permission: p })
  await load()
}

const ovr = (uid: string, p: string) => overrides.value.find(o => o.user_id === uid && o.permission === p)
const state = (uid: string, p: string) => {
  const o = ovr(uid, p)
  return o ? (o.granted ? 'allow' : 'deny') : 'default'
}
async function setOvr(uid: string, p: string, v: string) {
  if (!canManage.value) return
  if (v === 'default') await sb.from('user_permissions').delete().eq('user_id', uid).eq('permission', p)
  else await sb.from('user_permissions').upsert({ user_id: uid, permission: p, granted: v === 'allow' })
  await load()
}

// Filtered members list
const filteredUsers = computed(() => {
  return users.value.filter(u => {
    if (filterRole.value && u.role !== filterRole.value) return false
    if (search.value.trim()) {
      const q = search.value.toLowerCase()
      const matchPseudo = (u.pseudo_name || '').toLowerCase().includes(q)
      const matchReal = (u.real_name || '').toLowerCase().includes(q)
      const matchRole = (u.role || '').toLowerCase().includes(q)
      if (!matchPseudo && !matchReal && !matchRole) return false
    }
    return true
  })
})

// Delete User Modal State
const showDeleteModal = ref(false)
const userToDelete = ref<any>(null)
const isDeletingUser = ref(false)

function confirmDelete(u: any) {
  if (u.id === auth.session.value?.user?.id) {
    show('You cannot delete your own account.', 'err')
    return
  }
  userToDelete.value = u
  showDeleteModal.value = true
}

async function executeDeleteUser() {
  if (!userToDelete.value) return
  isDeletingUser.value = true
  const targetId = userToDelete.value.id
  const targetName = userToDelete.value.pseudo_name || userToDelete.value.real_name || 'Member'

  try {
    // Attempt 1: Call admin_delete_user RPC
    const { error: rpcErr } = await sb.rpc('admin_delete_user', { p_user_id: targetId })
    if (rpcErr) {
      // Attempt 2: Call server endpoint
      try {
        const session = auth.session.value
        await $fetch('/api/users/delete', {
          method: 'POST',
          headers: session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {},
          body: { user_id: targetId }
        })
      } catch (apiErr: any) {
        // Attempt 3: Direct profile delete if caller has direct RLS delete permission
        const { error: directErr } = await sb.from('profiles').delete().eq('id', targetId)
        if (directErr) {
          throw new Error(rpcErr.message || apiErr?.data?.message || directErr.message || 'Failed to delete user')
        }
      }
    }

    show(`Member "${targetName}" was permanently deleted.`, 'ok')
    showDeleteModal.value = false
    userToDelete.value = null
    await staff.load()
    await load()
  } catch (err: any) {
    show(err.message || 'Failed to delete user', 'err')
  } finally {
    isDeletingUser.value = false
  }
}
</script>

<template>
  <div class="team-page">
    <div class="row" style="justify-content:space-between;margin-bottom:1rem;flex-wrap:wrap;gap:.75rem">
      <div>
        <h1 style="margin:0 0 .25rem">Team Members & Roles</h1>
        <p class="sub" style="margin:0">
          Manage your support staff, assign access roles (Admin, Manager, Team Lead, Employee), and configure permissions. Visitors only see public pseudo names.
        </p>
      </div>
      <div v-if="canManage">
        <button class="btn amber" @click="openAddUser">
          <strong>+ Add Member (Email Verified)</strong>
        </button>
      </div>
    </div>

    <!-- Quick Stats Cards -->
    <div class="grid g4" style="margin-bottom:1.25rem">
      <div class="card stat">
        <small class="sub">Total Team Members</small>
        <b>{{ users.length }}</b>
      </div>
      <div class="card stat green">
        <small class="sub">Active Members</small>
        <b>{{ users.filter(u => u.is_active).length }}</b>
      </div>
      <div class="card stat amber">
        <small class="sub">Administrators</small>
        <b>{{ users.filter(u => u.role === 'admin').length }}</b>
      </div>
      <div class="card stat">
        <small class="sub">Tickets in Progress</small>
        <b>{{ Object.values(ticketStats).reduce((a, b) => a + b, 0) }}</b>
      </div>
    </div>

    <!-- Navigation Tabs: Members vs Roles -->
    <div class="tabs" style="margin-bottom:1.25rem">
      <button class="tab" :class="{ on: activeTab === 'members' }" @click="activeTab = 'members'">
        👥 Team Members ({{ filteredUsers.length }})
      </button>
      <button class="tab" :class="{ on: activeTab === 'roles' }" @click="activeTab = 'roles'">
        🔒 Roles & Permissions Matrix
      </button>
    </div>

    <!-- TAB 1: MEMBERS DIRECTORY -->
    <div v-if="activeTab === 'members'">
      <!-- Filter and Search Bar -->
      <div class="card row" style="gap:1rem;margin-bottom:1rem;padding:.75rem 1rem">
        <div class="grow" style="min-width:240px">
          <input
            v-model="search"
            placeholder="Search by pseudo name, real name, or role…"
            aria-label="Search members"
          >
        </div>
        <div style="width:180px">
          <select v-model="filterRole" aria-label="Filter by role">
            <option value="">All Roles</option>
            <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
          </select>
        </div>
        <button
          v-if="search || filterRole"
          class="btn sm alt"
          @click="search = ''; filterRole = ''"
        >
          Reset Filters
        </button>
      </div>

      <!-- Members Table -->
      <div class="card scroll" style="padding:0;overflow:hidden">
        <table>
          <thead>
            <tr>
              <th>Status</th>
              <th>Pseudo Name (Public)</th>
              <th v-if="canViewReal">Real Name (Private)</th>
              <th>Assigned Role</th>
              <th>Active Tickets</th>
              <th v-if="canManage">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="filteredUsers.length === 0">
              <td colspan="6" class="empty">No team members match your filter criteria.</td>
            </tr>
            <tr v-for="u in filteredUsers" :key="u.id">
              <td>
                <span
                  class="status-dot"
                  :class="u.is_active ? 'online' : 'offline'"
                  :title="u.is_active ? 'Active' : 'Inactive'"
                />
                <span style="font-size:.85rem;color:var(--muted)">{{ u.is_active ? 'Active' : 'Inactive' }}</span>
              </td>
              <td>
                <template v-if="canManage">
                  <input v-model="u.pseudo_name" style="min-width:140px">
                </template>
                <strong v-else>{{ u.pseudo_name }}</strong>
              </td>
              <td v-if="canViewReal">
                <template v-if="canManage">
                  <input v-model="u.real_name" style="min-width:140px">
                </template>
                <span v-else>{{ u.real_name || '—' }}</span>
              </td>
              <td>
                <template v-if="canManage">
                  <select v-model="u.role" style="min-width:120px">
                    <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
                  </select>
                </template>
                <span v-else class="chip role">{{ u.role }}</span>
              </td>
              <td>
                <span class="chip" :class="(ticketStats[u.id] || 0) > 0 ? 'claimed' : ''">
                  {{ ticketStats[u.id] || 0 }} tickets
                </span>
              </td>
              <td v-if="canManage" class="row" style="white-space:nowrap;gap:.4rem">
                <label style="margin:0;margin-right:.25rem;font-weight:400;display:inline-flex;align-items:center;gap:4px">
                  <input type="checkbox" v-model="u.is_active" style="width:auto"> Active
                </label>
                <button class="btn sm amber" @click="saveUser(u)">Save</button>
                <button class="btn sm alt" @click="sel = u">Permissions</button>
                <button
                  v-if="u.id !== auth.session.value?.user?.id"
                  class="btn sm danger"
                  @click="confirmDelete(u)"
                  title="Permanently delete user"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Specific User Permissions Override Drawer / Card -->
      <div v-if="sel" class="card" style="margin-top:1.5rem">
        <div class="row" style="justify-content:space-between">
          <h2>
            Permission Overrides for <strong>{{ sel.pseudo_name }}</strong>
            <span class="chip role" style="margin-left:.5rem">Role: {{ sel.role }}</span>
          </h2>
          <button class="btn sm alt" @click="sel = null">Close</button>
        </div>
        <p class="sub">
          "Role default" follows their role baseline. "Allow" explicitly grants it, and "Deny" revokes it specifically for this person.
        </p>
        <div class="scroll">
          <table>
            <thead>
              <tr>
                <th>Permission</th>
                <th>Role Baseline</th>
                <th>Custom Override</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in perms" :key="p.key">
                <td>
                  <b>{{ p.key }}</b><br>
                  <small class="sub">{{ p.description }}</small>
                </td>
                <td>
                  <span class="chip" :class="roleHas(sel.role, p.key) ? 'open' : ''">
                    {{ roleHas(sel.role, p.key) ? 'Granted by role' : 'Denied by role' }}
                  </span>
                </td>
                <td>
                  <select
                    :value="state(sel.id, p.key)"
                    style="width:auto"
                    :disabled="!canManage"
                    @change="setOvr(sel.id, p.key, ($event.target as HTMLSelectElement).value)"
                  >
                    <option value="default">Role default</option>
                    <option value="allow">Allow (Grant)</option>
                    <option value="deny">Deny (Revoke)</option>
                  </select>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- TAB 2: ROLES & PERMISSIONS MATRIX -->
    <div v-if="activeTab === 'roles'">
      <div class="card scroll" style="margin-bottom:1.25rem">
        <h2 style="margin:0 0 .25rem">Role Definitions & Access Levels</h2>
        <p class="sub" style="margin-bottom:1rem">
          Every team member is assigned one of four roles. Roles determine baseline capabilities across tickets, sites, users, and audit data.
        </p>

        <div class="grid g4" style="margin-bottom:1.5rem">
          <div class="card" style="background:#f8fafc;border-top:3px solid #0f172a">
            <h3 style="margin:0 0 .3rem">admin</h3>
            <p class="sub" style="font-size:.84rem;margin:0">
              Full administrative control. Can manage websites, bot rules, canned replies, users, and all tickets.
            </p>
          </div>
          <div class="card" style="background:#f8fafc;border-top:3px solid #2563eb">
            <h3 style="margin:0 0 .3rem">manager</h3>
            <p class="sub" style="font-size:.84rem;margin:0">
              Operations manager. Can view all tickets, reassign tickets, manage canned replies, view private real names.
            </p>
          </div>
          <div class="card" style="background:#f8fafc;border-top:3px solid #0f7c86">
            <h3 style="margin:0 0 .3rem">teamlead</h3>
            <p class="sub" style="font-size:.84rem;margin:0">
              Shift / team lead. Can claim, reassign, close tickets, and create canned replies and keyword rules.
            </p>
          </div>
          <div class="card" style="background:#f8fafc;border-top:3px solid #64748b">
            <h3 style="margin:0 0 .3rem">employee</h3>
            <p class="sub" style="font-size:.84rem;margin:0">
              Frontline assistance agent. Can claim open tickets, reply to visitors, and view their assigned tickets.
            </p>
          </div>
        </div>

        <h3 style="margin:0 0 .5rem">Global Permissions Matrix</h3>
        <p class="sub" style="margin-bottom:1rem">
          Check or uncheck boxes to adjust permissions for an entire role. Changes apply immediately to all users with that role.
        </p>

        <table>
          <thead>
            <tr>
              <th>Permission Key</th>
              <th>Description</th>
              <th v-for="r in roles" :key="r" style="text-align:center">{{ r }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in perms" :key="p.key">
              <td><code>{{ p.key }}</code></td>
              <td><small class="sub">{{ p.description }}</small></td>
              <td v-for="r in roles" :key="r" style="text-align:center">
                <input
                  type="checkbox"
                  :checked="roleHas(r, p.key)"
                  :disabled="!canManage || r === 'admin'"
                  :aria-label="`${r} ${p.key}`"
                  style="width:auto;cursor:pointer"
                  @change="toggleRole(r, p.key)"
                >
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- MODAL: ADD MEMBER (EMAIL VERIFIED DIRECTLY) -->
    <div v-if="showAddUser" class="modal-backdrop" @click.self="showAddUser = false">
      <div class="modal card" role="dialog" aria-modal="true" aria-labelledby="add-user-title">
        <div class="row" style="justify-content:space-between;margin-bottom:.75rem">
          <h2 id="add-user-title" style="margin:0">Add Team Member</h2>
          <button class="x-close" @click="showAddUser = false" aria-label="Close dialog">×</button>
        </div>

        <p class="sub" style="margin-bottom:1rem">
          Create a new staff account directly from the dashboard. The account is created with <strong>Email Verified</strong> status so they can sign in immediately without clicking any verification links.
        </p>

        <form @submit.prevent="submitAddUser">
          <div class="cols">
            <div>
              <label for="u-email">Email Address <span style="color:var(--red)">*</span></label>
              <input
                id="u-email"
                v-model="userForm.email"
                type="email"
                required
                placeholder="staff@airport-assistance.com"
                autocomplete="off"
              >
            </div>
            <div>
              <label for="u-role">Role <span style="color:var(--red)">*</span></label>
              <select id="u-role" v-model="userForm.role">
                <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
              </select>
            </div>
          </div>

          <div class="cols" style="margin-top:.75rem">
            <div>
              <label for="u-real">Real Name (Private) <span style="color:var(--red)">*</span></label>
              <input
                id="u-real"
                v-model="userForm.real_name"
                required
                placeholder="e.g. Sarah Jenkins"
                @input="autoFillPseudo"
              >
            </div>
            <div>
              <label for="u-pseudo">Pseudo Name (Public to Visitors) <span style="color:var(--red)">*</span></label>
              <input
                id="u-pseudo"
                v-model="userForm.pseudo_name"
                required
                placeholder="e.g. Sarah J."
              >
            </div>
          </div>

          <div style="margin-top:.75rem">
            <label for="u-pw">Temporary Password <span style="color:var(--red)">*</span></label>
            <div class="row" style="gap:.5rem">
              <input
                id="u-pw"
                :type="showPassword ? 'text' : 'password'"
                v-model="userForm.password"
                required
                style="flex:1"
                placeholder="At least 6 characters"
              >
              <button type="button" class="btn alt sm" @click="generatePassword">
                Generate
              </button>
              <button type="button" class="btn alt sm" @click="showPassword = !showPassword">
                {{ showPassword ? 'Hide' : 'Show' }}
              </button>
              <button type="button" class="btn alt sm" :disabled="!userForm.password" @click="copy(userForm.password).then(() => show('Password copied to clipboard!'))">
                Copy
              </button>
            </div>
          </div>

          <div class="card" style="background:#f0fdf4;border-color:#bbf7d0;margin-top:1rem;padding:.75rem 1rem">
            <label style="margin:0;font-weight:600;color:#166534;display:inline-flex;align-items:center;gap:.5rem;cursor:pointer">
              <input type="checkbox" v-model="userForm.email_confirm" style="width:auto;cursor:pointer">
              <span>Email Verified (Recommended: user can sign in immediately without confirmation email)</span>
            </label>
          </div>

          <div class="row" style="justify-content:flex-end;margin-top:1.25rem;gap:.5rem">
            <button type="button" class="btn alt" @click="showAddUser = false">Cancel</button>
            <button type="submit" class="btn amber" :disabled="addingUser">
              {{ addingUser ? 'Creating Member…' : 'Create Team Member' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- MODAL: DELETE USER CONFIRMATION -->
    <div v-if="showDeleteModal && userToDelete" class="modal-backdrop" @click="showDeleteModal = false">
      <div class="modal card" @click.stop style="max-width:480px;box-sizing:border-box">
        <div class="row" style="gap:.75rem;align-items:center;margin-bottom:1rem">
          <div class="del-user-icon">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
          </div>
          <div>
            <h2 style="margin:0;font-size:1.15rem;color:var(--red)">Delete Team Member?</h2>
            <p class="sub" style="margin:0;font-size:.82rem">{{ userToDelete.pseudo_name }} · Role: {{ userToDelete.role }}</p>
          </div>
        </div>

        <p style="font-size:.9rem;line-height:1.5;margin-bottom:1rem;color:var(--ink)">
          Are you sure you want to permanently delete <strong>{{ userToDelete.pseudo_name }}</strong><span v-if="userToDelete.real_name"> ({{ userToDelete.real_name }})</span>?
        </p>

        <div v-if="(ticketStats[userToDelete.id] || 0) > 0" style="background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:.75rem 1rem;margin-bottom:1rem">
          <strong style="color:#92400e;font-size:.84rem;display:block">⚠️ Active Tickets Notice</strong>
          <p style="margin:.2rem 0 0 0;font-size:.8rem;color:#78350f;line-height:1.4">
            This user currently has <strong>{{ ticketStats[userToDelete.id] }} active claimed ticket(s)</strong>. Deleting them will automatically unclaim these tickets and return them to the open queue.
          </p>
        </div>

        <div style="background:#fee2e2;border:1px solid #fca5a5;border-radius:8px;padding:.75rem 1rem;margin-bottom:1.5rem">
          <p style="margin:0;font-size:.82rem;color:#991b1b;line-height:1.4">
            ⛔ <strong>Warning:</strong> Their login credentials, access permissions, and account profile will be permanently removed. This action cannot be undone.
          </p>
        </div>

        <div class="row" style="justify-content:flex-end;gap:.6rem">
          <button class="btn alt" :disabled="isDeletingUser" @click="showDeleteModal = false">
            Cancel
          </button>
          <button class="btn danger" :disabled="isDeletingUser" @click="executeDeleteUser">
            {{ isDeletingUser ? 'Deleting…' : 'Yes, Permanently Delete' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.del-user-icon {
  width: 42px;
  height: 42px;
  border-radius: 50%;
  background: var(--red-soft);
  color: var(--red);
  display: grid;
  place-items: center;
  flex-shrink: 0;
}
.status-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-right: 6px;
}
.status-dot.online {
  background-color: var(--green);
  box-shadow: 0 0 0 2px var(--green-soft);
}
.status-dot.offline {
  background-color: var(--muted);
}
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(6px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 1rem;
}
.modal {
  max-width: 600px;
  width: 100%;
  max-height: 90vh;
  overflow-y: auto;
  border-radius: var(--r-lg);
  border: 1px solid var(--line);
  box-shadow: var(--shadow-xl);
  animation: modalIn .15s ease-out;
}
.x-close {
  background: none;
  border: 0;
  font-size: 1.5rem;
  line-height: 1;
  color: var(--muted);
  cursor: pointer;
}
.x-close:hover {
  color: var(--ink);
}
@keyframes modalIn {
  from { opacity: 0; transform: scale(0.97) translateY(8px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}
</style>
