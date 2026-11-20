<script setup lang="ts">
const sb = useSb(), staff = useStaff(), auth = useAuth(), alarm = useAlarm(), { show } = useToast()
const rows = ref<any[]>([]), tab = ref('active'), q = ref(''), site = ref(''), error = ref('')

// Multi-select & Bulk Delete state
const canDelete = computed(() => {
  const r = auth.profile.value?.role
  return r === 'admin' || r === 'manager'
})
const selectedIds = ref<string[]>([])
const showDeleteModal = ref(false)
const isDeleting = ref(false)
const singleDeleteTarget = ref<any>(null)

async function load() {
  const { data, error: e } = await sb.from('tickets').select('*, sites(name)').order('updated_at', { ascending: false }).limit(300)
  if (e) error.value = e.message; else rows.value = data || []
}

let ch: any
onMounted(async () => {
  if (!Object.keys(staff.map.value).length) await staff.load()
  await load()
  
  if (ch) sb.removeChannel(ch)
  const token = auth.session.value?.access_token
  if (token && sb.realtime?.setAuth) {
    try { await sb.realtime.setAuth(token) } catch {}
  }
  const topic = 'tickets-list-' + (auth.session.value?.user?.id || 'staff')
  ch = sb.channel(topic)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' }, load)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'ticket_messages' }, load)
    .subscribe()
})
onBeforeUnmount(() => ch && sb.removeChannel(ch))

const me = computed(() => auth.session.value?.user.id)
const sitesList = computed(() => [...new Set(rows.value.map(r => r.sites?.name))].filter(Boolean))

const botChatCount = computed(() => rows.value.filter(t => t.status === 'bot').length)
const unclaimedCount = computed(() => rows.value.filter(t => t.status === 'open' || t.status === 'bot').length)

const shown = computed(() => rows.value.filter(t => {
  if (tab.value === 'active' && t.status === 'closed') return false
  if (tab.value === 'unclaimed' && (t.status !== 'open' && t.status !== 'bot')) return false
  if (tab.value === 'bot' && t.status !== 'bot') return false
  if (tab.value === 'mine' && t.claimed_by !== me.value) return false
  if (tab.value === 'closed' && t.status !== 'closed') return false
  if (site.value && t.sites?.name !== site.value) return false
  const s = q.value.toLowerCase()
  return !s || [t.subject, t.visitor_name, t.visitor_email, t.visitor_phone, 'uaa-' + t.ticket_no].some(v => String(v || '').toLowerCase().includes(s))
}))

const tabs = computed(() => [
  ['active', 'Active Queue'],
  ['bot', `🤖 Bot Chats (${botChatCount.value})`],
  ['unclaimed', `Unclaimed (${unclaimedCount.value})`],
  ['mine', 'My Tickets'],
  ['closed', 'Closed']
])

// Multi-select helpers
const isAllSelected = computed(() => shown.value.length > 0 && shown.value.every(t => selectedIds.value.includes(t.id)))
const isIndeterminate = computed(() => selectedIds.value.length > 0 && !isAllSelected.value)

function toggleSelect(id: string) {
  if (!canDelete.value) return
  if (selectedIds.value.includes(id)) {
    selectedIds.value = selectedIds.value.filter(x => x !== id)
  } else {
    selectedIds.value.push(id)
  }
}

function toggleSelectAll() {
  if (!canDelete.value) return
  if (isAllSelected.value) {
    selectedIds.value = []
  } else {
    selectedIds.value = [...new Set([...selectedIds.value, ...shown.value.map(t => t.id)])]
  }
}

function selectAllFiltered() {
  if (!canDelete.value) return
  selectedIds.value = shown.value.map(t => t.id)
}

function clearSelection() {
  selectedIds.value = []
}

function confirmSingleDelete(ticket: any) {
  if (!canDelete.value) {
    show('Only managers and admins can delete tickets.', 'err')
    return
  }
  singleDeleteTarget.value = ticket
  showDeleteModal.value = true
}

const targetDeleteCount = computed(() => singleDeleteTarget.value ? 1 : selectedIds.value.length)

async function executeDelete() {
  if (!canDelete.value) {
    show('Only managers and admins can delete tickets.', 'err')
    return
  }
  const ids = singleDeleteTarget.value ? [singleDeleteTarget.value.id] : [...selectedIds.value]
  if (!ids.length) return

  isDeleting.value = true
  try {
    // 1. Try calling delete_tickets RPC
    const { error: rpcErr } = await sb.rpc('delete_tickets', { p_tickets: ids })
    if (rpcErr) {
      // 2. Fallback to direct supabase delete query
      const { error: dirErr } = await sb.from('tickets').delete().in('id', ids)
      if (dirErr) throw dirErr
    }

    show(`Deleted ${ids.length} chat${ids.length > 1 ? 's' : ''} successfully`, 'ok')
    selectedIds.value = selectedIds.value.filter(x => !ids.includes(x))
    showDeleteModal.value = false
    singleDeleteTarget.value = null
    await load()
  } catch (err: any) {
    show('Failed to delete: ' + (err?.message || 'Database error'), 'err')
  } finally {
    isDeleting.value = false
  }
}

async function quickClaim(ticketId: string) {
  const { error: err } = await sb.rpc('claim_ticket', { p_ticket: ticketId })
  if (err) {
    show(err.message, 'err')
  } else {
    show('Chat claimed! Automated bot replies paused. You are now connected live.', 'ok')
    alarm.broadcastTicketClaimed(ticketId)
    await load()
  }
}
</script>
<template>
  <div class="row" style="justify-content:space-between;margin-bottom:1rem">
    <div>
      <h1>Support Tickets</h1>
      <p class="sub" style="margin:0">Live queue of passenger inquiries and assistance requests.</p>
    </div>
  </div>

  <div class="row" style="margin-bottom:1rem;gap:.75rem">
    <div class="grow">
      <input v-model="q" placeholder="Search ticket #, passenger name, email, or subject…" aria-label="Search tickets">
    </div>
    <div style="width:200px">
      <select v-model="site" aria-label="Filter by site">
        <option value="">All Sites</option>
        <option v-for="s in sitesList" :key="s">{{ s }}</option>
      </select>
    </div>
  </div>

  <div class="tabs" style="margin-bottom:1rem">
    <button v-for="t in tabs" :key="t[0]" class="tab" :class="{ on: tab === t[0] }" @click="tab = t[0]">
      {{ t[1] }}
    </button>
  </div>

  <!-- Bulk Selection Toolbar -->
  <div v-if="canDelete && selectedIds.length > 0" class="bulk-toolbar card">
    <div class="row" style="gap:.75rem;align-items:center;flex-wrap:wrap">
      <span class="bulk-pill">
        ✓ {{ selectedIds.length }} chat{{ selectedIds.length > 1 ? 's' : '' }} selected
      </span>
      <button class="btn alt sm" @click="selectAllFiltered">
        Select all {{ shown.length }} shown
      </button>
      <button class="btn alt sm" @click="clearSelection">
        Clear selection
      </button>
    </div>
    <button class="btn danger sm" @click="singleDeleteTarget = null; showDeleteModal = true">
      <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
      <span>Delete Selected ({{ selectedIds.length }})</span>
    </button>
  </div>

  <p v-if="error" class="err">{{ error }}</p>

  <div class="card scroll" style="padding:0;overflow:hidden">
    <table>
      <thead>
        <tr>
          <th v-if="canDelete" style="width:38px;padding-left:14px;padding-right:4px">
            <input
              type="checkbox"
              :checked="isAllSelected"
              :indeterminate="isIndeterminate"
              @change="toggleSelectAll"
              title="Select all tickets"
              class="cb-select"
            >
          </th>
          <th>Ticket</th>
          <th>Site</th>
          <th>Passenger</th>
          <th>Subject</th>
          <th>Status</th>
          <th>Owner</th>
          <th>Activity</th>
          <th v-if="canDelete" style="width:38px"></th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="t in shown"
          :key="t.id"
          class="click"
          :class="{ 'row-highlight': canDelete && selectedIds.includes(t.id) }"
          @click="navigateTo('/tickets/' + t.id)"
        >
          <td v-if="canDelete" style="padding-left:14px;padding-right:4px" @click.stop>
            <input
              type="checkbox"
              :checked="selectedIds.includes(t.id)"
              @change="toggleSelect(t.id)"
              class="cb-select"
            >
          </td>
          <td>
            <span v-if="t.unread_by_staff && t.status !== 'closed'" class="dot" title="Unread visitor message" />
            <strong>UAA-{{ t.ticket_no }}</strong>
          </td>
          <td><span class="sub" style="font-size:.85rem">{{ t.sites?.name || '-' }}</span></td>
          <td>
            <strong>{{ t.visitor_name || 'Anonymous Passenger' }}</strong>
            <small v-if="t.visitor_email" class="sub" style="display:block;font-size:.78rem">{{ t.visitor_email }}</small>
            <small v-if="t.visitor_phone" style="display:block;font-size:.78rem;color:var(--teal)">📞 {{ t.visitor_phone }}</small>
          </td>
          <td style="max-width:300px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
            {{ t.subject }}
          </td>
          <td>
            <span class="chip" :class="t.status">
              {{ t.status === 'bot' ? '🤖 Bot Chat' : t.status }}
            </span>
          </td>
          <td>
            <div v-if="t.claimed_by" style="font-weight:500">{{ staff.label(t.claimed_by) }}</div>
            <div v-else class="row" style="gap:.4rem;flex-wrap:nowrap">
              <span class="sub" style="font-style:italic">Unassigned</span>
              <button
                v-if="(t.status === 'bot' || t.status === 'open') && auth.can('tickets.claim')"
                class="btn sm amber"
                style="padding:2px 7px;font-size:.72rem"
                @click.stop="quickClaim(t.id)"
                title="Take over conversation and disable automated bot replies"
              >
                ⚡ Claim
              </button>
            </div>
          </td>
          <td>
            <span class="sub" style="font-size:.82rem">{{ ago(t.updated_at) }}</span>
          </td>
          <td v-if="canDelete" @click.stop>
            <button
              class="btn-row-del"
              @click.stop="confirmSingleDelete(t)"
              title="Delete chat conversation"
            >
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-if="!shown.length" class="empty">No tickets found matching your current filter.</p>
  </div>

  <!-- Delete Confirmation Modal -->
  <div v-if="canDelete && showDeleteModal" class="delete-modal-backdrop" @click="showDeleteModal = false">
    <div class="delete-modal card" @click.stop>
      <div class="row" style="gap:.75rem;align-items:center;margin-bottom:1rem">
        <div class="del-modal-icon">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
        </div>
        <div>
          <h2 style="margin:0;font-size:1.15rem">
            Delete {{ targetDeleteCount }} Chat Conversation{{ targetDeleteCount > 1 ? 's' : '' }}?
          </h2>
          <p class="sub" style="margin:0;font-size:.82rem">
            {{ targetDeleteCount > 1 ? `Permanently remove ${targetDeleteCount} selected conversations.` : `Delete UAA-${singleDeleteTarget?.ticket_no || ''}.` }}
          </p>
        </div>
      </div>
      <p style="font-size:.9rem;line-height:1.5;margin-bottom:1.5rem;color:var(--ink)">
        This will permanently delete the ticket{{ targetDeleteCount > 1 ? 's' : '' }} and all related visitor messages. This action cannot be reversed.
      </p>
      <div class="row" style="justify-content:flex-end;gap:.6rem">
        <button class="btn alt" :disabled="isDeleting" @click="showDeleteModal = false">
          Cancel
        </button>
        <button class="btn danger" :disabled="isDeleting" @click="executeDelete">
          {{ isDeleting ? 'Deleting…' : `Yes, Delete ${targetDeleteCount} Chat${targetDeleteCount > 1 ? 's' : ''}` }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.bulk-toolbar {
  background: #f8fafc;
  border: 1px solid #cbd5e1;
  padding: 10px 14px;
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.04);
}
.bulk-pill {
  font-weight: 700;
  font-size: 0.88rem;
  color: var(--ink);
  background: #e2e8f0;
  padding: 4px 10px;
  border-radius: 99px;
}
.cb-select {
  width: 16px;
  height: 16px;
  cursor: pointer;
  accent-color: var(--accent, #f59e0b);
}
.row-highlight {
  background: rgba(245, 158, 11, 0.08) !important;
}
.btn-row-del {
  background: none;
  border: 0;
  color: #94a3b8;
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
  display: grid;
  place-items: center;
  transition: color 0.15s ease, background 0.15s ease;
}
.btn-row-del:hover {
  color: #ef4444;
  background: rgba(239, 68, 68, 0.1);
}
.delete-modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(9, 13, 22, 0.6);
  backdrop-filter: blur(4px);
  z-index: 250;
  display: grid;
  place-items: center;
  padding: 1rem;
}
.delete-modal {
  width: 100%;
  max-width: 460px;
  border-radius: 12px;
  background: #ffffff;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
  padding: 20px;
}
.del-modal-icon {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: #fee2e2;
  color: #ef4444;
  display: grid;
  place-items: center;
  flex-shrink: 0;
}
</style>
