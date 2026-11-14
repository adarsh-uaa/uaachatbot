<script setup lang="ts">
definePageMeta({ perm: 'dashboard.view' })

const sb = useSb()
const auth = useAuth()
const staff = useStaff()
const teamsHook = useTeams()
const { show } = useToast()

const activeTab = ref<'all' | 'teams' | 'members' | 'roles'>('all')
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
const filterTeam = ref('')

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
  team_id: '',
  email_confirm: true
})

// Add/Edit Team Modal State
const showTeamModal = ref(false)
const editingTeam = ref<any>(null)
const teamForm = reactive({
  name: '',
  description: '',
  color: '#0f7c86',
  lead_id: ''
})

async function load() {
  await Promise.all([staff.load(), teamsHook.load()])

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
  userForm.team_id = teamsHook.teams.value[0]?.id || ''
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
    await teamsHook.createUser({
      email: userForm.email,
      password: userForm.password,
      real_name: userForm.real_name,
      pseudo_name: userForm.pseudo_name,
      role: userForm.role,
      team_id: userForm.team_id || null,
      email_confirm: userForm.email_confirm
    })
    show(`User "${userForm.pseudo_name}" created successfully (Email Verified)!`, 'ok')
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
    is_active: u.is_active,
    team_id: u.team_id || null
  }
  if (canViewReal.value && u.real_name) {
    payload.real_name = u.real_name
  }
  const { error } = await sb.from('profiles').update(payload).eq('id', u.id)
  if (error) {
    show(error.message.includes('unique') ? 'That pseudo name is already taken' : error.message, 'err')
  } else {
    show(`Saved changes for ${u.pseudo_name}`, 'ok')
    await load()
  }
}

function openTeamModal(t?: any) {
  if (t) {
    editingTeam.value = t
    teamForm.name = t.name
    teamForm.description = t.description || ''
    teamForm.color = t.color || '#0f7c86'
    teamForm.lead_id = t.lead_id || ''
  } else {
    editingTeam.value = null
    teamForm.name = ''
    teamForm.description = ''
    teamForm.color = '#0f7c86'
    teamForm.lead_id = ''
  }
  showTeamModal.value = true
}

async function submitTeam() {
  if (!teamForm.name.trim()) {
    show('Team name is required', 'err')
    return
  }
  try {
    if (editingTeam.value) {
      await teamsHook.updateTeam(editingTeam.value.id, {
        name: teamForm.name.trim(),
        description: teamForm.description.trim(),
        color: teamForm.color,
        lead_id: teamForm.lead_id || null
      })
      show('Team updated successfully', 'ok')
    } else {
      await teamsHook.createTeam(teamForm.name.trim(), teamForm.description.trim(), teamForm.color)
      show('Team created successfully', 'ok')
    }
    showTeamModal.value = false
    await load()
  } catch (err: any) {
    show(err.message || 'Error saving team', 'err')
  }
}

async function removeTeam(team: any) {
  if (!confirm(`Delete team "${team.name}"? Members will be unassigned from this team.`)) return
  try {
    await teamsHook.deleteTeam(team.id)
    show('Team deleted', 'ok')
    await load()
  } catch (err: any) {
    show(err.message || 'Error deleting team', 'err')
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
    if (filterTeam.value && (u.team_id || '') !== filterTeam.value) return false
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

const getTeamName = (teamId?: string | null) => {
  if (!teamId) return 'Unassigned'
  const found = teamsHook.teams.value.find(t => t.id === teamId)
  return found ? found.name : 'Unassigned'
}

const getTeamColor = (teamId?: string | null) => {
  if (!teamId) return '#5d6b76'
  const found = teamsHook.teams.value.find(t => t.id === teamId)
  return found?.color || '#0f7c86'
}

const membersInTeam = (teamId: string) => {
  return users.value.filter(u => u.team_id === teamId)
}

const totalActiveTicketsInTeam = (teamId: string) => {
  const memberIds = users.value.filter(u => u.team_id === teamId).map(u => u.id)
  return memberIds.reduce((sum, id) => sum + (ticketStats.value[id] || 0), 0)
}
</script>

<template>
  <div class="teams-page">
    <div class="row" style="justify-content:space-between;margin-bottom:1rem">
      <div>
        <h1>Teams & Staff</h1>
        <p class="sub">
          Manage support teams, staff accounts, roles, and permissions. Visitors and customers only ever see public pseudo names.
        </p>
      </div>
      <div class="row" v-if="canManage">
        <button class="btn amber" @click="openAddUser">
          <strong>+ Add User (Email Verified)</strong>
        </button>
        <button class="btn alt" @click="openTeamModal()">
          + New Team
        </button>
      </div>
    </div>

    <!-- Quick Stats Cards -->
    <div class="grid g4" style="margin-bottom:1.25rem">
      <div class="card stat">
        <small class="sub">Total Staff</small>
        <b>{{ users.length }}</b>
      </div>
      <div class="card stat green">
        <small class="sub">Active Members</small>
        <b>{{ users.filter(u => u.is_active).length }}</b>
      </div>
      <div class="card stat amber">
        <small class="sub">Support Teams</small>
        <b>{{ teamsHook.teams.value.length }}</b>
      </div>
      <div class="card stat">
        <small class="sub">Tickets in Progress</small>
        <b>{{ Object.values(ticketStats).reduce((a, b) => a + b, 0) }}</b>
      </div>
    </div>

    <!-- Navigation Tabs -->
    <div class="tabs" style="margin-bottom:1.25rem">
      <button class="tab" :class="{ on: activeTab === 'all' }" @click="activeTab = 'all'">
        🏢 All Overview (Teams & Directory)
      </button>
      <button class="tab" :class="{ on: activeTab === 'teams' }" @click="activeTab = 'teams'">
        🏬 Teams & Departments ({{ teamsHook.teams.value.length }})
      </button>
      <button class="tab" :class="{ on: activeTab === 'members' }" @click="activeTab = 'members'">
        👥 Members Directory ({{ filteredUsers.length }})
      </button>
      <button class="tab" :class="{ on: activeTab === 'roles' }" @click="activeTab = 'roles'">
        🔒 Roles & Permissions Matrix
      </button>
    </div>

    <!-- SECTION: TEAMS & DEPARTMENTS (Shown in 'all' and 'teams' tabs) -->
    <div v-if="activeTab === 'all' || activeTab === 'teams'" style="margin-bottom:2rem">
      <div class="row" style="justify-content:space-between;margin-bottom:1rem">
        <div>
          <h2 style="margin:0 0 .2rem">Support Teams & Departments</h2>
          <p class="sub" style="margin:0">
            Functional airport units with dedicated leads and member assignments. Click a department card to filter members below.
          </p>
        </div>
        <button v-if="canManage" class="btn amber" @click="openTeamModal()">
          + New Team
        </button>
      </div>

      <div class="grid g2">
        <div
          v-for="team in teamsHook.teams.value"
          :key="team.id"
          class="card team-card"
          :class="{ 'team-active-filter': filterTeam === team.id }"
          :style="{ borderTop: `4px solid ${team.color || '#0f7c86'}` }"
          @click="filterTeam = (filterTeam === team.id ? '' : team.id)"
          style="cursor:pointer"
        >
          <div class="row" style="justify-content:space-between;align-items:flex-start">
            <div>
              <h3 style="margin:0 0 .3rem;display:flex;align-items:center;gap:.5rem">
                <span class="team-color-dot" :style="{ backgroundColor: team.color || '#0f7c86' }" />
                {{ team.name }}
                <span v-if="filterTeam === team.id" class="chip" style="background:#0f7c86;color:#ffffff;font-size:.7rem">Active Filter</span>
              </h3>
              <p class="sub" style="margin:0">{{ team.description || 'No description provided.' }}</p>
            </div>
            <div class="row" v-if="canManage" @click.stop>
              <button class="btn sm alt" @click="openTeamModal(team)">Edit</button>
              <button class="btn sm danger" @click="removeTeam(team)">Delete</button>
            </div>
          </div>

          <hr style="border:0;border-top:1px solid var(--line);margin:.75rem 0">

          <div class="cols" style="font-size:.9rem;margin-bottom:.75rem">
            <div>
              <small class="sub">Team Lead:</small><br>
              <strong>{{ team.lead_id ? staff.label(team.lead_id) : 'Not assigned' }}</strong>
            </div>
            <div>
              <small class="sub">Team Members:</small><br>
              <strong>{{ membersInTeam(team.id).length }} staff</strong>
            </div>
            <div>
              <small class="sub">Active Tickets:</small><br>
              <strong>{{ totalActiveTicketsInTeam(team.id) }} open/claimed</strong>
            </div>
          </div>

          <div>
            <small class="sub" style="display:block;margin-bottom:.3rem">Assigned Members:</small>
            <div class="row" style="gap:.4rem;flex-wrap:wrap">
              <span
                v-for="m in membersInTeam(team.id)"
                :key="m.id"
                class="chip"
                style="background:var(--paper);border:1px solid var(--line)"
              >
                {{ m.pseudo_name }} <small>({{ m.role }})</small>
              </span>
              <span v-if="membersInTeam(team.id).length === 0" class="sub" style="font-size:.85rem">
                No members assigned yet.
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- SECTION: MEMBERS & DIRECTORY (Shown in 'all' and 'members' tabs) -->
    <div v-if="activeTab === 'all' || activeTab === 'members'" style="margin-bottom:2rem">
      <div class="row" style="justify-content:space-between;margin-bottom:1rem">
        <div>
          <h2 style="margin:0 0 .2rem">Staff Directory & Team Assignments</h2>
          <p class="sub" style="margin:0">
            Assign staff members to support departments, configure public pseudo names, and manage access roles.
          </p>
        </div>
        <div v-if="canManage">
          <button class="btn amber" @click="openAddUser">
            <strong>+ Add User (Email Verified)</strong>
          </button>
        </div>
      </div>

      <!-- Filter and Search Bar -->
      <div class="card row" style="gap:1rem;margin-bottom:1rem;padding:.75rem 1rem">
        <div class="grow" style="min-width:240px">
          <input
            v-model="search"
            placeholder="Search by pseudo name, real name, or role…"
            aria-label="Search members"
          >
        </div>
        <div style="width:160px">
          <select v-model="filterRole" aria-label="Filter by role">
            <option value="">All Roles</option>
            <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
          </select>
        </div>
        <div style="width:220px">
          <select v-model="filterTeam" aria-label="Filter by team">
            <option value="">All Support Teams</option>
            <option v-for="t in teamsHook.teams.value" :key="t.id" :value="t.id">{{ t.name }}</option>
          </select>
        </div>
        <button
          v-if="search || filterRole || filterTeam"
          class="btn sm alt"
          @click="search = ''; filterRole = ''; filterTeam = ''"
        >
          Reset Filters
        </button>
      </div>

      <!-- Members Table -->
      <div class="card scroll">
        <table>
          <thead>
            <tr>
              <th>Status</th>
              <th>Pseudo Name (Public)</th>
              <th v-if="canViewReal">Real Name (Private)</th>
              <th>Role</th>
              <th>Assigned Team</th>
              <th>Active Tickets</th>
              <th v-if="canManage">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="filteredUsers.length === 0">
              <td colspan="7" class="empty">No team members match your filter criteria.</td>
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
                  <select v-model="u.role" style="min-width:110px">
                    <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
                  </select>
                </template>
                <span v-else class="chip role">{{ u.role }}</span>
              </td>
              <td>
                <template v-if="canManage">
                  <select v-model="u.team_id" style="min-width:170px">
                    <option :value="null">Unassigned</option>
                    <option v-for="t in teamsHook.teams.value" :key="t.id" :value="t.id">{{ t.name }}</option>
                  </select>
                </template>
                <span
                  v-else
                  class="chip team-chip"
                  :style="{ borderColor: getTeamColor(u.team_id), color: getTeamColor(u.team_id) }"
                >
                  {{ getTeamName(u.team_id) }}
                </span>
              </td>
              <td>
                <span class="chip" :class="(ticketStats[u.id] || 0) > 0 ? 'claimed' : ''">
                  {{ ticketStats[u.id] || 0 }} tickets
                </span>
              </td>
              <td v-if="canManage" class="row" style="white-space:nowrap">
                <label style="margin:0;margin-right:.4rem;font-weight:400;display:inline-flex;align-items:center;gap:4px">
                  <input type="checkbox" v-model="u.is_active" style="width:auto"> Active
                </label>
                <button class="btn sm amber" @click="saveUser(u)">Save</button>
                <button class="btn sm alt" @click="sel = u">Permissions</button>
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
            <span class="chip role" style="margin-left:.5rem">{{ sel.role }}</span>
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
                <th>Description</th>
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

    <!-- TAB 3: ROLES & PERMISSIONS MATRIX -->
    <div v-if="activeTab === 'roles'">
      <div class="card scroll">
        <h2>Global Role Capabilities</h2>
        <p class="sub">
          Control what each role can access across the dashboard. Changes apply to all users with that role who do not have an individual override.
        </p>
        <table>
          <thead>
            <tr>
              <th>Permission</th>
              <th>Description</th>
              <th v-for="r in roles" :key="r" style="text-align:center">{{ r }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in perms" :key="p.key">
              <td><b>{{ p.key }}</b></td>
              <td><small class="sub">{{ p.description }}</small></td>
              <td v-for="r in roles" :key="r" style="text-align:center">
                <input
                  type="checkbox"
                  :checked="roleHas(r, p.key)"
                  :disabled="!canManage || r === 'admin'"
                  :aria-label="`${r} ${p.key}`"
                  style="width:auto"
                  @change="toggleRole(r, p.key)"
                >
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- MODAL: ADD USER (EMAIL VERIFIED DIRECTLY) -->
    <div v-if="showAddUser" class="modal-backdrop" @click.self="showAddUser = false">
      <div class="modal card" role="dialog" aria-modal="true" aria-labelledby="add-user-title">
        <div class="row" style="justify-content:space-between;margin-bottom:.75rem">
          <h2 id="add-user-title" style="margin:0">Add User Directly</h2>
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
              <label for="u-pw">Password <span style="color:var(--red)">*</span></label>
              <div class="row" style="gap:4px">
                <input
                  id="u-pw"
                  v-model="userForm.password"
                  :type="showPassword ? 'text' : 'password'"
                  required
                  minlength="6"
                  placeholder="Min 6 characters"
                  autocomplete="new-password"
                  class="grow"
                >
                <button type="button" class="btn sm alt" @click="showPassword = !showPassword">
                  {{ showPassword ? 'Hide' : 'Show' }}
                </button>
                <button type="button" class="btn sm alt" title="Generate random password" @click="generatePassword">
                  Generate
                </button>
              </div>
            </div>
          </div>

          <div class="cols" style="margin-top:.75rem">
            <div>
              <label for="u-real">Real Name (Private) <span style="color:var(--red)">*</span></label>
              <input
                id="u-real"
                v-model="userForm.real_name"
                required
                placeholder="Sarah Jenkins"
                @blur="autoFillPseudo"
              >
              <small class="sub">Visible only to admins and managers.</small>
            </div>
            <div>
              <label for="u-pseudo">Pseudo Name (Public) <span style="color:var(--red)">*</span></label>
              <input
                id="u-pseudo"
                v-model="userForm.pseudo_name"
                required
                placeholder="Sarah J."
              >
              <small class="sub">Seen by passengers in the chat and on tickets.</small>
            </div>
          </div>

          <div class="cols" style="margin-top:.75rem">
            <div>
              <label for="u-role">Role</label>
              <select id="u-role" v-model="userForm.role">
                <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
              </select>
            </div>
            <div>
              <label for="u-team">Support Team / Department</label>
              <select id="u-team" v-model="userForm.team_id">
                <option :value="null">Unassigned</option>
                <option v-for="t in teamsHook.teams.value" :key="t.id" :value="t.id">{{ t.name }}</option>
              </select>
            </div>
          </div>

          <!-- Email Verified Switch / Checkbox -->
          <div class="card email-verified-box" style="margin-top:1rem;background:#f0fbf6;border-color:#b8ebd0">
            <label style="margin:0;font-weight:700;display:flex;align-items:center;gap:.6rem;cursor:pointer">
              <input
                type="checkbox"
                v-model="userForm.email_confirm"
                style="width:18px;height:18px;accent-color:var(--green)"
              >
              <span>
                <strong style="color:var(--green)">Email Verified (Instant Sign-In)</strong>
                <small style="display:block;font-weight:400;color:var(--ink2)">
                  Bypasses email verification. The user can sign in immediately at <code>/login</code> with the email and password specified above.
                </small>
              </span>
            </label>
          </div>

          <div class="row" style="justify-content:flex-end;margin-top:1.25rem">
            <button type="button" class="btn alt" @click="showAddUser = false">Cancel</button>
            <button type="submit" class="btn amber" :disabled="addingUser">
              {{ addingUser ? 'Creating User…' : 'Create & Verify User' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- MODAL: CREATE / EDIT TEAM -->
    <div v-if="showTeamModal" class="modal-backdrop" @click.self="showTeamModal = false">
      <div class="modal card" role="dialog" aria-modal="true" aria-labelledby="team-modal-title">
        <div class="row" style="justify-content:space-between;margin-bottom:.75rem">
          <h2 id="team-modal-title" style="margin:0">{{ editingTeam ? 'Edit Team' : 'Create Support Team' }}</h2>
          <button class="x-close" @click="showTeamModal = false" aria-label="Close dialog">×</button>
        </div>

        <form @submit.prevent="submitTeam">
          <label for="t-name">Team Name <span style="color:var(--red)">*</span></label>
          <input
            id="t-name"
            v-model="teamForm.name"
            required
            placeholder="e.g. Passenger Assistance (PRM)"
          >

          <label for="t-desc">Description</label>
          <textarea
            id="t-desc"
            v-model="teamForm.description"
            rows="2"
            placeholder="Special assistance, mobility, wheelchair service, etc."
          />

          <div class="cols" style="margin-top:.75rem">
            <div>
              <label for="t-color">Theme Color</label>
              <div class="row" style="gap:.5rem">
                <input id="t-color" type="color" v-model="teamForm.color" style="width:45px;height:38px;padding:2px">
                <input v-model="teamForm.color" style="width:120px">
              </div>
            </div>
            <div v-if="editingTeam">
              <label for="t-lead">Team Lead</label>
              <select id="t-lead" v-model="teamForm.lead_id">
                <option value="">No Team Lead</option>
                <option v-for="u in users" :key="u.id" :value="u.id">{{ u.pseudo_name }} ({{ u.role }})</option>
              </select>
            </div>
          </div>

          <div class="row" style="justify-content:flex-end;margin-top:1.25rem">
            <button type="button" class="btn alt" @click="showTeamModal = false">Cancel</button>
            <button type="submit" class="btn amber">Save Team</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
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
.team-chip {
  background: #fff;
  border: 1px solid currentColor;
  font-weight: 600;
}
.team-color-dot {
  display: inline-block;
  width: 12px;
  height: 12px;
  border-radius: 3px;
}
.team-card {
  transition: transform .15s ease, box-shadow .15s ease;
}
.team-card:hover {
  transform: translateY(-2px);
  box-shadow: var(--shadow-md);
}
.team-active-filter {
  outline: 2px solid #0f7c86;
  background: #f0fdfa !important;
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
  max-width: 620px;
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

