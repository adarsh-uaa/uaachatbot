<script setup lang="ts">
definePageMeta({ perm: 'dashboard.view' })
const sb = useSb(), auth = useAuth(), alarm = useAlarm(), { show } = useToast()
const days = ref(30), site = ref<string>(''), sites = ref<any[]>([]), s = ref<any>(null), error = ref('')
const liveChats = ref<any[]>([])

const claimWarningTarget = ref<any>(null)
const showClaimWarningModal = ref(false)

function isFormSubmitted(ticket: any): boolean {
  if (!ticket) return false
  if (ticket.form_submitted === true) return true
  const email = String(ticket.visitor_email || '').trim().toLowerCase()
  const name = String(ticket.visitor_name || '').trim()
  const phone = String(ticket.visitor_phone || '').trim()

  const hasRealEmail = email.length > 0 && !email.includes('@uaa.chat') && !email.includes('anonymous')
  const hasRealName = name.length > 0 && !name.startsWith('Passenger #') && name !== 'Passenger' && name !== 'Visitor'
  const hasPhone = phone.length > 0

  return (hasRealEmail && hasRealName) || (hasPhone && hasRealName)
}

function handleTakeOver(ticket: any) {
  if (!isFormSubmitted(ticket)) {
    claimWarningTarget.value = ticket
    showClaimWarningModal.value = true
    return
  }
  executeTakeOver(ticket.id)
}

function confirmTakeOver() {
  if (!claimWarningTarget.value) return
  const id = claimWarningTarget.value.id
  showClaimWarningModal.value = false
  claimWarningTarget.value = null
  executeTakeOver(id)
}

async function executeTakeOver(ticketId: string) {
  const { error: err } = await sb.rpc('claim_ticket', { p_ticket: ticketId })
  if (err) {
    show(err.message, 'err')
  } else {
    show('Conversation claimed! Automated bot replies paused.', 'ok')
    alarm.broadcastTicketClaimed(ticketId)
    navigateTo('/tickets/' + ticketId)
  }
}

async function loadStats() {
  const { data, error: e } = await sb.rpc('dashboard_stats', { p_days: days.value, p_site: site.value || null })
  if (e) error.value = e.message; else { error.value = ''; s.value = data }
}

async function loadLiveChats() {
  let q = sb.from('tickets').select('*, sites(name)').in('status', ['bot', 'open']).order('updated_at', { ascending: false }).limit(10)
  if (site.value) q = q.eq('site_id', site.value)
  const { data } = await q
  liveChats.value = data || []
}

async function load() {
  await Promise.all([loadStats(), loadLiveChats()])
}

let ticketChannel: any
onMounted(async () => {
  sites.value = (await sb.from('sites').select('id,name').order('name')).data || []
  await load()
  if (ticketChannel) sb.removeChannel(ticketChannel)
  const token = auth.session.value?.access_token
  if (token && sb.realtime?.setAuth) {
    try { await sb.realtime.setAuth(token) } catch {}
  }
  const topic = 'dashboard-live-tickets-' + (auth.session.value?.user?.id || 'staff')
  ticketChannel = sb.channel(topic)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' }, loadLiveChats)
    .subscribe()
})

onBeforeUnmount(() => {
  if (ticketChannel) sb.removeChannel(ticketChannel)
})

watch([days, site], load)
const max = (a: any[], k: string) => Math.max(1, ...(a || []).map(x => x[k]))
</script>
<template>
  <div class="row" style="justify-content:space-between;align-items:flex-start;margin-bottom:1.5rem">
    <div>
      <h1>Dashboard Overview</h1>
      <p class="sub" style="margin:0">Live metrics on visitor enquiries, response performance, and team resolution.</p>
    </div>
    <div class="row">
      <select v-model="days" style="width:auto">
        <option :value="7">Last 7 days</option>
        <option :value="30">Last 30 days</option>
        <option :value="90">Last 90 days</option>
      </select>
      <select v-model="site" style="width:auto">
        <option value="">All sites</option>
        <option v-for="x in sites" :key="x.id" :value="x.id">{{ x.name }}</option>
      </select>
    </div>
  </div>

  <p v-if="error" class="err">{{ error }}</p>

  <template v-if="s">
    <div class="grid g4" style="margin-bottom:1.5rem">
      <div class="card stat" style="border-left-color: var(--red);">
        <small>Unclaimed</small>
        <b>{{ s.open }}</b>
        <span class="sub" style="font-size:.78rem">Needs attention</span>
      </div>
      <div class="card stat amber">
        <small>In Progress</small>
        <b>{{ s.claimed }}</b>
        <span class="sub" style="font-size:.78rem">Currently claimed</span>
      </div>
      <div class="card stat green">
        <small>Resolved</small>
        <b>{{ s.closed }}</b>
        <span class="sub" style="font-size:.78rem">Closed in period</span>
      </div>
      <div class="card stat" style="border-left-color: var(--accent);">
        <small>Avg First Reply</small>
        <b>{{ s.avg_first_response_min != null ? `${s.avg_first_response_min}m` : '-' }}</b>
        <span class="sub" style="font-size:.78rem">Response time</span>
      </div>
    </div>

    <!-- Live Ongoing Chats & Quick Replies Section -->
    <div class="card" style="margin-bottom:1.5rem">
      <div class="row" style="justify-content:space-between;align-items:center;margin-bottom:.5rem">
        <div class="row" style="gap:.5rem">
          <span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#22c55e;box-shadow:0 0 0 3px rgba(34,197,94,0.25)" />
          <h2 style="margin:0;font-size:1.1rem">Ongoing Live Chats & Quick Replies</h2>
          <span class="chip" style="font-size:.75rem">{{ liveChats.length }} active</span>
        </div>
        <NuxtLink to="/tickets" class="btn sm alt">View All Tickets →</NuxtLink>
      </div>
      <p class="sub" style="margin-bottom:1rem">Passengers currently interacting with quick replies or asking questions at assistance desks.</p>

      <div v-if="!liveChats.length" class="empty" style="padding:1.5rem 0">
        No active chats at the moment. All passenger inquiries have been resolved or claimed.
      </div>

      <div v-else class="scroll" style="overflow-x:auto">
        <table style="width:100%;margin:0">
          <thead>
            <tr>
              <th>Ticket</th>
              <th>Airport Site</th>
              <th>Passenger</th>
              <th>Inquiry / Quick Reply</th>
              <th>Mode</th>
              <th>Active</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="t in liveChats" :key="t.id" class="click" @click="navigateTo('/tickets/' + t.id)">
              <td>
                <span v-if="t.unread_by_staff" class="dot" title="Unread visitor message" />
                <strong>UAA-{{ t.ticket_no }}</strong>
              </td>
              <td><span class="sub" style="font-size:.85rem">{{ t.sites?.name || '-' }}</span></td>
              <td>
                <div class="row" style="gap:.4rem;align-items:center;flex-wrap:wrap">
                  <strong>{{ t.visitor_name || 'Passenger' }}</strong>
                  <span v-if="!isFormSubmitted(t)" class="chip" style="background:#fef3c7;color:#92400e;border:1px solid #fde68a;font-size:.7rem;padding:1px 6px" title="Passenger has not submitted the contact form yet">
                    ⚠️ Form Not Submitted
                  </span>
                  <span v-else class="chip" style="background:#dcfce7;color:#166534;border:1px solid #bbf7d0;font-size:.7rem;padding:1px 6px" title="Passenger submitted verified contact form">
                    ✓ Form Submitted
                  </span>
                </div>
                <small v-if="t.visitor_phone" style="display:block;font-size:.76rem;color:var(--teal)">📞 {{ t.visitor_phone }}</small>
              </td>
              <td style="max-width:280px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
                {{ t.subject }}
              </td>
              <td>
                <span class="chip" :class="t.status === 'bot' ? 'bot' : 'open'">
                  {{ t.status === 'bot' ? '🤖 Quick Reply / Bot' : 'Passenger Waiting' }}
                </span>
              </td>
              <td><span class="sub" style="font-size:.82rem">{{ ago(t.updated_at) }}</span></td>
              <td>
                <button
                  v-if="auth.can('tickets.claim')"
                  class="btn sm amber"
                  style="padding:3px 9px;font-size:.75rem;white-space:nowrap"
                  @click.stop="handleTakeOver(t)"
                  title="Claim chat and stop automated bot responses"
                >
                  ⚡ Take Over
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="grid g2">
      <div class="card">
        <h2>Top Bot Inquiries</h2>
        <p class="sub">Frequent questions successfully resolved by automatic keyword rules.</p>
        <p v-if="!s.top_rules.length" class="empty">No bot questions recorded yet.</p>
        <div v-for="r in s.top_rules" :key="r.name" class="bar">
          <span>{{ r.name }}</span>
          <i :style="{ width: (r.hits / max(s.top_rules,'hits')) * 50 + '%' }" />
          <b style="font-size:.85rem;color:var(--muted)">{{ r.hits }}</b>
        </div>
      </div>

      <div class="card">
        <h2>Unanswered Questions</h2>
        <p class="sub">Questions visitors typed where no automated answer was matched.</p>
        <p v-if="!s.unmatched.length" class="empty">All visitor questions matched existing rules.</p>
        <div v-for="r in s.unmatched" :key="r.query" class="row" style="justify-content:space-between;border-bottom:1px solid var(--line-subtle);padding:.5rem 0">
          <span class="grow" style="font-size:.9rem">
            {{ r.query }} <span class="chip" style="margin-left:.4rem">{{ r.hits }} hits</span>
          </span>
          <NuxtLink v-if="useAuth().can('rules.manage')" class="btn sm alt" :to="{ path: '/rules', query: { kw: r.query } }">
            + Create rule
          </NuxtLink>
        </div>
      </div>

      <div class="card">
        <h2>Ticket Volume Over Time</h2>
        <p class="sub">Number of support tickets opened per day in the selected period.</p>
        <p v-if="!s.per_day.length" class="empty">No tickets created in this period.</p>
        <div class="spark">
          <i
            v-for="d in s.per_day"
            :key="d.d"
            :title="`${d.d}: ${d.n} tickets`"
            :style="{ height: Math.max(10, (d.n / max(s.per_day,'n')) * 100) + '%' }"
          />
        </div>
      </div>

      <div class="card">
        <h2>Tickets by Website</h2>
        <p class="sub">Breakdown of assistance tickets across connected properties.</p>
        <div v-for="r in s.by_site" :key="r.name" class="bar">
          <span>{{ r.name }}</span>
          <i :style="{ width: (r.tickets / max(s.by_site,'tickets')) * 50 + '%', backgroundColor: 'var(--teal)' }" />
          <b style="font-size:.85rem;color:var(--muted)">{{ r.tickets }}</b>
        </div>
      </div>
    </div>
  </template>

  <!-- Claim Warning Modal for Unsubmitted Form on Dashboard -->
  <div v-if="showClaimWarningModal && claimWarningTarget" class="delete-modal-backdrop" @click="showClaimWarningModal = false">
    <div class="delete-modal card" @click.stop style="max-width:480px;box-sizing:border-box">
      <div style="display:flex;gap:.75rem;align-items:center;margin-bottom:1rem">
        <div class="del-modal-icon" style="background:#fef3c7;color:#d97706;flex-shrink:0">
          <span style="font-size:1.3rem">⚠️</span>
        </div>
        <div style="flex:1 1 0%;min-width:0">
          <h2 style="margin:0;font-size:1.15rem;color:#92400e">Passenger Form Not Submitted</h2>
          <p class="sub" style="margin:0;font-size:.82rem">Ticket UAA-{{ claimWarningTarget.ticket_no }} · {{ claimWarningTarget.visitor_name || 'Anonymous' }}</p>
        </div>
      </div>
      <p style="font-size:.9rem;line-height:1.5;margin-bottom:1.25rem;color:var(--ink)">
        This passenger has <strong>not submitted their contact information</strong> (name, email, or phone number).
      </p>
      <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:.75rem 1rem;margin-bottom:1.5rem">
        <p style="margin:0;font-size:.84rem;color:#92400e;line-height:1.45">
          ⚠️ <strong>Notice:</strong> Your live responses will only be delivered if the visitor still has their browser chat window open. If they have closed their browser tab, they will <strong>not receive an email or SMS notification</strong>.
        </p>
      </div>
      <div class="row" style="justify-content:flex-end;gap:.6rem;flex-wrap:wrap">
        <button class="btn alt" @click="showClaimWarningModal = false">
          Cancel
        </button>
        <button class="btn amber" @click="confirmTakeOver">
          Yes, Take Over Chat
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.delete-modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(9, 13, 22, 0.6);
  backdrop-filter: blur(2px);
  z-index: 100;
  display: grid;
  place-items: center;
  padding: 1rem;
}
.delete-modal {
  width: 100%;
  max-width: 480px;
  animation: modalIn .15s ease-out;
}
@keyframes modalIn {
  from { opacity: 0; transform: scale(.96); }
  to { opacity: 1; transform: scale(1); }
}
.del-modal-icon {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: grid;
  place-items: center;
}
</style>
