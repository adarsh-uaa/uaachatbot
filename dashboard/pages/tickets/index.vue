<script setup lang="ts">
const sb = useSb(), staff = useStaff(), auth = useAuth(), { show } = useToast()
const rows = ref<any[]>([]), tab = ref('active'), q = ref(''), site = ref(''), error = ref('')

async function load() {
  const { data, error: e } = await sb.from('tickets').select('*, sites(name)').order('updated_at', { ascending: false }).limit(300)
  if (e) error.value = e.message; else rows.value = data || []
}

let ch: any
onMounted(async () => {
  if (!Object.keys(staff.map.value).length) await staff.load()
  await load()
  ch = sb.channel('tickets-list').on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' }, load).subscribe()
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

async function quickClaim(ticketId: string) {
  const { error: err } = await sb.rpc('claim_ticket', { p_ticket: ticketId })
  if (err) {
    show(err.message, 'err')
  } else {
    show('Chat claimed! Automated bot replies paused. You are now connected live.', 'ok')
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

  <div class="tabs" style="margin-bottom:1.25rem">
    <button v-for="t in tabs" :key="t[0]" class="tab" :class="{ on: tab === t[0] }" @click="tab = t[0]">
      {{ t[1] }}
    </button>
  </div>

  <p v-if="error" class="err">{{ error }}</p>

  <div class="card scroll" style="padding:0;overflow:hidden">
    <table>
      <thead>
        <tr>
          <th>Ticket</th>
          <th>Site</th>
          <th>Passenger</th>
          <th>Subject</th>
          <th>Status</th>
          <th>Owner</th>
          <th>Activity</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="t in shown" :key="t.id" class="click" @click="navigateTo('/tickets/' + t.id)">
          <td>
            <span v-if="t.unread_by_staff && t.status !== 'closed'" class="dot" title="Unread visitor message" />
            <strong>UAA-{{ t.ticket_no }}</strong>
          </td>
          <td><span class="sub" style="font-size:.85rem">{{ t.sites?.name || '—' }}</span></td>
          <td>
            <strong>{{ t.visitor_name || 'Anonymous Passenger' }}</strong>
            <small v-if="t.visitor_email" class="sub" style="display:block;font-size:.78rem">{{ t.visitor_email }}</small>
            <small v-if="t.visitor_phone" style="display:block;font-size:.78rem;color:var(--teal)">📞 {{ t.visitor_phone }}</small>
          </td>
          <td style="max-width:320px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
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
        </tr>
      </tbody>
    </table>
    <p v-if="!shown.length" class="empty">No tickets found matching your current filter.</p>
  </div>
</template>
