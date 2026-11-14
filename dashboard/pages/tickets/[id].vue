<script setup lang="ts">
const route = useRoute(), sb = useSb(), staff = useStaff(), auth = useAuth(), { show } = useToast()
const id = route.params.id as string
const t = ref<any>(null), msgs = ref<any[]>([]), canned = ref<any[]>([]), body = ref(''), note = ref(false), error = ref(''), assignTo = ref('')
const me = computed(() => auth.session.value?.user.id)
const mine = computed(() => t.value?.claimed_by === me.value)
const lead = computed(() => auth.can('tickets.reassign'))

async function load() {
  const a = await sb.from('tickets').select('*, sites(name)').eq('id', id).maybeSingle()
  if (!a.data) { error.value = 'Ticket not found, or you no longer have access to it.'; t.value = null; return }
  t.value = a.data
  msgs.value = (await sb.from('ticket_messages').select('*').eq('ticket_id', id).order('created_at')).data || []
  nextTick(() => { const el = document.getElementById('thread'); if (el) el.scrollTop = el.scrollHeight })
}
async function act(fn: string, args: any, ok: string) {
  error.value = ''
  const { error: e } = await sb.rpc(fn, args)
  if (e) { error.value = e.message; show(e.message, 'err') } else { show(ok); await load() }
}
async function send() {
  if (!body.value.trim()) return
  const text = body.value
  await act('staff_reply', { p_ticket: id, p_body: text, p_internal: note.value }, note.value ? 'Note saved' : 'Reply sent')
  if (!error.value) body.value = ''
}
async function copyTicket() {
  show((await copy(`UAA-${t.value.ticket_no} · ${t.value.visitor_name} <${t.value.visitor_email}>\n${msgs.value.filter(m => !m.is_internal).map(m => `${m.sender}: ${m.body}`).join('\n')}`)) ? 'Conversation copied' : 'Copy failed', 'ok')
}
function useCanned(e: any) { const c = canned.value.find(x => x.id === e.target.value); if (c) body.value = c.body; e.target.value = '' }
const who = (m: any) => m.sender === 'visitor' ? (t.value?.visitor_name || 'Passenger') : m.sender === 'staff' ? staff.label(m.author_id) : m.sender === 'bot' ? 'Bot Assistant' : 'System'

let ch: any
onMounted(async () => {
  if (!Object.keys(staff.map.value).length) await staff.load()
  await load()
  canned.value = (await sb.from('canned_replies').select('*').order('title')).data || []
  ch = sb.channel('t-' + id)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'ticket_messages', filter: `ticket_id=eq.${id}` }, load)
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'tickets', filter: `id=eq.${id}` }, load).subscribe()
})
onBeforeUnmount(() => ch && sb.removeChannel(ch))
</script>

<template>
  <div style="margin-bottom:1rem">
    <NuxtLink to="/tickets" style="display:inline-flex;align-items:center;gap:4px;font-size:.88rem;color:var(--muted)">
      ← Back to all tickets
    </NuxtLink>
  </div>

  <p v-if="!t" class="err">{{ error || 'Loading ticket…' }}</p>

  <template v-else>
    <!-- Live Bot Chat Banner if visitor is currently chatting with bot -->
    <div v-if="t.status === 'bot'" class="card" style="background:#f0fdf4;border-color:#bbf7d0;margin-bottom:1.25rem;padding:.85rem 1.25rem">
      <div class="row" style="justify-content:space-between;flex-wrap:wrap;gap:.75rem">
        <div class="row" style="gap:.75rem">
          <span style="font-size:1.4rem">🤖</span>
          <div>
            <strong style="color:#166534;font-size:1rem">Live Bot Chat in Progress</strong>
            <p class="sub" style="margin:0;color:#15803d;font-size:.84rem">
              The visitor is currently receiving automated keyword responses. Claiming this conversation disables automated bot replies so you can assist them live.
            </p>
          </div>
        </div>
        <button
          v-if="auth.can('tickets.claim')"
          class="btn amber"
          @click="act('claim_ticket', { p_ticket: id }, 'You took over this chat! Automated bot replies are now disabled.')"
        >
          ⚡ Take Over & Claim Chat
        </button>
      </div>
    </div>

    <!-- Ticket Summary Card -->
    <div class="card" style="margin-bottom:1.25rem">
      <div class="row" style="justify-content:space-between;align-items:flex-start">
        <div>
          <div class="row" style="gap:.6rem;margin-bottom:.35rem">
            <h1 style="margin:0;font-size:1.6rem">UAA-{{ t.ticket_no }}</h1>
            <span class="chip" :class="t.status">
              {{ t.status === 'bot' ? '🤖 Bot Chat' : t.status }}
            </span>
          </div>
          <p class="sub" style="margin:0">
            <strong>{{ t.visitor_name || 'Anonymous Passenger' }}</strong>
            <template v-if="t.visitor_email">
              · <a :href="'mailto:' + t.visitor_email">{{ t.visitor_email }}</a>
            </template>
            <template v-if="t.visitor_phone">
              · <a :href="'tel:' + t.visitor_phone" style="font-weight:600;color:var(--teal)">📞 {{ t.visitor_phone }}</a>
            </template>
            · Site: <span>{{ t.sites?.name || 'General' }}</span> · 
            Opened {{ fmt(t.created_at) }}
          </p>
        </div>
        <div style="text-align:right">
          <small class="sub" style="display:block">Claimed by</small>
          <strong style="color:var(--ink)">{{ t.claimed_by ? staff.label(t.claimed_by) : 'Nobody yet' }}</strong>
          <small v-if="t.claimed_at" class="sub" style="display:block;font-size:.78rem">since {{ fmt(t.claimed_at) }}</small>
        </div>
      </div>

      <!-- Action Toolbar -->
      <div class="row" style="margin-top:1rem;padding-top:1rem;border-top:1px solid var(--line-subtle);gap:.5rem">
        <button
          v-if="(t.status === 'open' || t.status === 'bot') && auth.can('tickets.claim')"
          class="btn amber"
          @click="act('claim_ticket', { p_ticket: id }, t.status === 'bot' ? 'You claimed this chat! Automated replies disabled.' : 'You claimed this ticket')"
        >
          {{ t.status === 'bot' ? '⚡ Take Over & Claim' : 'Claim ticket' }}
        </button>
        <button v-if="t.status === 'claimed' && (mine || lead)" class="btn alt" @click="act('release_ticket', { p_ticket: id }, 'Ticket released')">
          Release
        </button>
        <button v-if="t.status === 'claimed' && (mine || lead) && auth.can('tickets.close')" class="btn danger" @click="act('close_ticket', { p_ticket: id }, 'Ticket closed')">
          Close ticket
        </button>
        <button v-if="t.status === 'closed' && auth.can('tickets.reply')" class="btn alt" @click="act('reopen_ticket', { p_ticket: id }, 'Ticket reopened')">
          Reopen ticket
        </button>

        <template v-if="lead && t.status !== 'closed'">
          <select v-model="assignTo" style="width:auto" aria-label="Assign to">
            <option value="">Reassign to…</option>
            <option v-for="s in staff.list.value" :key="s.id" :value="s.id">{{ s.pseudo_name }} ({{ s.role }})</option>
          </select>
          <button class="btn alt" :disabled="!assignTo" @click="act('assign_ticket', { p_ticket: id, p_user: assignTo }, 'Ticket assigned')">
            Assign
          </button>
        </template>

        <button class="btn alt sm" style="margin-left:auto" @click="copyTicket">
          Copy transcript
        </button>
      </div>
    </div>

    <p v-if="error" class="err">{{ error }}</p>

    <!-- Conversation Thread -->
    <div class="card" style="margin-bottom:1.25rem">
      <div class="row" style="justify-content:space-between;margin-bottom:.75rem;padding-bottom:.6rem;border-bottom:1px solid var(--line-subtle)">
        <h2 style="margin:0;font-size:1.05rem">Conversation History</h2>
        <small class="sub" style="margin:0">{{ msgs.length }} messages recorded</small>
      </div>

      <div id="thread" class="thread">
        <div
          v-for="m in msgs"
          :key="m.id"
          class="msg"
          :class="m.is_internal ? 'note' : m.sender"
        >
          <div v-if="m.sender !== 'system'" style="display:flex;justify-content:space-between;align-items:center;margin-bottom:.35rem">
            <span style="display:inline-flex;align-items:center;gap:.4rem">
              <strong>{{ who(m) }}</strong>
              <span v-if="m.is_internal" class="chip" style="background:#fef3c7;color:#b45309;font-size:.7rem">INTERNAL NOTE</span>
              <span v-else-if="m.sender === 'visitor'" class="chip" style="background:#e2e8f0;color:#334155;font-size:.7rem">PASSENGER</span>
              <span v-else-if="m.sender === 'bot'" class="chip" style="background:#f0fdf4;color:#166534;font-size:.7rem">BOT ASSISTANT</span>
              <span v-else-if="m.sender === 'staff'" class="chip" style="background:#eff6ff;color:#2563eb;font-size:.7rem">STAFF</span>
            </span>
            <small style="margin:0;font-size:.78rem;color:var(--muted)">{{ fmt(m.created_at) }}</small>
          </div>
          <div style="font-size:.9rem;line-height:1.55">{{ m.body }}</div>
        </div>
      </div>
    </div>

    <!-- Reply / Internal Note Composer -->
    <div v-if="t.status !== 'closed'" class="card">
      <div class="row" style="justify-content:space-between;margin-bottom:.75rem">
        <div class="row">
          <select style="width:auto" @change="useCanned" aria-label="Insert saved reply">
            <option value="">Insert saved reply…</option>
            <option v-for="c in canned" :key="c.id" :value="c.id">{{ c.title }}</option>
          </select>
          <label style="margin:0;font-weight:500;display:inline-flex;align-items:center;gap:.4rem;cursor:pointer">
            <input type="checkbox" v-model="note" style="width:auto;cursor:pointer">
            <span>Internal staff note <small class="sub">(visitor will not see this)</small></span>
          </label>
        </div>
      </div>

      <textarea
        v-model="body"
        :placeholder="note ? 'Write an internal note for staff…' : (mine || lead ? 'Type your reply to the passenger…' : 'Claim this ticket to reply')"
        @keydown.ctrl.enter="send"
        style="margin-bottom:.75rem"
      />

      <div class="row" style="justify-content:space-between">
        <button class="btn amber" :disabled="!body.trim()" @click="send">
          {{ note ? 'Save Internal Note' : 'Send Reply to Passenger' }}
        </button>
        <small class="sub" style="margin:0">Press <strong>Ctrl + Enter</strong> to send</small>
      </div>
    </div>
  </template>
</template>
