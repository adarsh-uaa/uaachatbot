<script setup lang="ts">
const route = useRoute(), sb = useSb(), staff = useStaff(), auth = useAuth(), alarm = useAlarm(), { show } = useToast()
const id = route.params.id as string
const t = ref<any>(null), msgs = ref<any[]>([]), canned = ref<any[]>([]), body = ref(''), note = ref(false), error = ref(''), assignTo = ref('')
const me = computed(() => auth.session.value?.user.id)
const mine = computed(() => t.value?.claimed_by === me.value)
const lead = computed(() => auth.can('tickets.reassign'))

// Form submission check & reply warning state
const showUnfilledWarningModal = ref(false)
const acknowledgedUnfilled = ref(false)
const showClaimWarningModal = ref(false)

const isFormSubmitted = computed(() => {
  if (!t.value) return false
  if (t.value.form_submitted === true) return true
  const email = String(t.value.visitor_email || '').trim().toLowerCase()
  const name = String(t.value.visitor_name || '').trim()
  const phone = String(t.value.visitor_phone || '').trim()

  const hasRealEmail = email.length > 0 && !email.includes('@uaa.chat') && !email.includes('anonymous')
  const hasRealName = name.length > 0 && !name.startsWith('Passenger #') && name !== 'Passenger' && name !== 'Visitor'
  const hasPhone = phone.length > 0

  return (hasRealEmail && hasRealName) || (hasPhone && hasRealName)
})

function handleClaim() {
  if (!isFormSubmitted.value) {
    showClaimWarningModal.value = true
    return
  }
  confirmClaim()
}

function confirmClaim() {
  showClaimWarningModal.value = false
  act('claim_ticket', { p_ticket: id }, t.value?.status === 'bot' ? 'You took over this chat! Automated bot replies are now disabled.' : 'You claimed this ticket')
}

async function load() {
  // The moment ANY staff member opens this ticket, immediately silence alarm across all devices
  alarm.broadcastTicketOpened(id)

  const a = await sb.from('tickets').select('*, sites(name)').eq('id', id).maybeSingle()
  if (!a.data) { error.value = 'Ticket not found, or you no longer have access to it.'; t.value = null; return }
  t.value = a.data
  msgs.value = (await sb.from('ticket_messages').select('*').eq('ticket_id', id).order('created_at')).data || []
  if (a.data.unread_by_staff) {
    const { error: rpcErr } = await sb.rpc('mark_ticket_read', { p_ticket: id })
    if (rpcErr) {
      await sb.from('tickets').update({ unread_by_staff: false }).eq('id', id)
    }
    if (t.value) t.value.unread_by_staff = false
    alarm.broadcastTicketOpened(id)
  }
  nextTick(() => { const el = document.getElementById('thread'); if (el) el.scrollTop = el.scrollHeight })
}
async function act(fn: string, args: any, ok: string) {
  error.value = ''
  const { error: e } = await sb.rpc(fn, args)
  if (e) {
    error.value = e.message
    show(e.message, 'err')
  } else {
    show(ok)
    if (fn === 'claim_ticket' || fn === 'close_ticket' || fn === 'staff_reply') {
      alarm.broadcastTicketClaimed(id)
    }
    await load()
  }
}
async function send() {
  if (!body.value.trim()) return
  // If passenger has NOT filled form data, warn the team before sending live reply
  if (!note.value && !isFormSubmitted.value && !acknowledgedUnfilled.value) {
    showUnfilledWarningModal.value = true
    return
  }
  await doSend()
}
async function doSend() {
  const text = body.value
  await act('staff_reply', { p_ticket: id, p_body: text, p_internal: note.value }, note.value ? 'Note saved' : 'Reply sent')
  if (!error.value) {
    body.value = ''
    alarm.broadcastTicketClaimed(id)
    sb.rpc('mark_ticket_read', { p_ticket: id }).catch(() => {
      sb.from('tickets').update({ unread_by_staff: false }).eq('id', id).catch(() => {})
    })
  }
  showUnfilledWarningModal.value = false
}
function confirmSendUnfilled() {
  acknowledgedUnfilled.value = true
  doSend()
}
async function copyTicket() {
  show((await copy(`UAA-${t.value.ticket_no} · ${t.value.visitor_name} <${t.value.visitor_email}>\n${msgs.value.filter(m => !m.is_internal).map(m => `${m.sender}: ${m.body}`).join('\n')}`)) ? 'Conversation copied' : 'Copy failed', 'ok')
}

const confirmDeleteModal = ref(false)
const isDeleting = ref(false)
const canDelete = computed(() => {
  const r = auth.profile.value?.role
  return r === 'admin' || r === 'manager'
})

async function deleteChat() {
  if (!canDelete.value) {
    show('Only managers and admins can delete conversations.', 'err')
    return
  }
  isDeleting.value = true
  try {
    const { error: rpcErr } = await sb.rpc('delete_ticket', { p_ticket: id })
    if (rpcErr) {
      const { error: dirErr } = await sb.from('tickets').delete().eq('id', id)
      if (dirErr) throw dirErr
    }
    show(`Ticket UAA-${t.value.ticket_no} deleted successfully`, 'ok')
    navigateTo('/tickets')
  } catch (err: any) {
    show('Failed to delete: ' + (err?.message || 'Database error'), 'err')
  } finally {
    isDeleting.value = false
    confirmDeleteModal.value = false
  }
}
function useCanned(e: any) { const c = canned.value.find(x => x.id === e.target.value); if (c) body.value = c.body; e.target.value = '' }
const who = (m: any) => m.sender === 'visitor' ? (t.value?.visitor_name || 'Passenger') : m.sender === 'staff' ? staff.label(m.author_id) : m.sender === 'bot' ? 'Bot Assistant' : 'System'

let ch: any
onMounted(async () => {
  if (!Object.keys(staff.map.value).length) await staff.load()
  await load()
  canned.value = (await sb.from('canned_replies').select('*').order('title')).data || []
  
  if (ch) sb.removeChannel(ch)
  const token = auth.session.value?.access_token
  if (token && sb.realtime?.setAuth) {
    try { await sb.realtime.setAuth(token) } catch {}
  }
  const topic = 't-' + id + '-' + (auth.session.value?.user?.id || 'staff')
  ch = sb.channel(topic)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'ticket_messages', filter: `ticket_id=eq.${id}` }, load)
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'tickets', filter: `id=eq.${id}` }, load)
    .subscribe()
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
          @click="handleClaim"
        >
          ⚡ Take Over & Claim Chat
        </button>
      </div>
    </div>

    <!-- Warning Banner when Contact Form is Not Submitted -->
    <div v-if="!isFormSubmitted" class="card" style="background:#fffbeb;border:1px solid #fde68a;margin-bottom:1.25rem;padding:.85rem 1.25rem">
      <div class="row" style="gap:.75rem;align-items:center">
        <span style="font-size:1.4rem">⚠️</span>
        <div>
          <strong style="color:#92400e;font-size:1rem">Contact Form Not Submitted</strong>
          <p class="sub" style="margin:0;color:#b45309;font-size:.84rem">
            This passenger has not submitted their verified contact details yet (name, email, or phone are unverified).
            Live replies will only reach them while their browser chat tab is currently active.
          </p>
        </div>
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
            <span v-if="!isFormSubmitted" class="chip" style="background:#fef3c7;color:#92400e;border:1px solid #fde68a" title="Passenger has not submitted the contact form">
              ⚠️ Form Not Submitted
            </span>
            <span v-else class="chip" style="background:#dcfce7;color:#166534;border:1px solid #bbf7d0">
              ✓ Form Data Submitted
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
          @click="handleClaim"
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
            <option v-for="s in staff.list.value" :key="s.id" :value="s.id">{{ staff.label(s.id) }} ({{ s.role }})</option>
          </select>
          <button class="btn alt" :disabled="!assignTo" @click="act('assign_ticket', { p_ticket: id, p_user: assignTo }, 'Ticket assigned')">
            Assign
          </button>
        </template>

        <div class="row" style="gap:.5rem;margin-left:auto">
          <button class="btn alt sm" @click="copyTicket">
            Copy transcript
          </button>
          <button v-if="canDelete" class="btn danger sm" @click="confirmDeleteModal = true" title="Delete conversation">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            <span>Delete chat</span>
          </button>
        </div>
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

      <!-- Warning if passenger has not submitted contact form -->
      <div
        v-if="!isFormSubmitted && !note"
        class="unfilled-warning-banner"
      >
        <span class="warning-icon">⚠️</span>
        <div class="warning-content">
          <strong>Live Chat Only · Contact Form Not Submitted</strong>
          <p>
            No email or phone on file. Replies only reach passengers while their chat window is active.
          </p>
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

    <!-- Delete Ticket Modal -->
    <div v-if="canDelete && confirmDeleteModal" class="delete-modal-backdrop" @click="confirmDeleteModal = false">
      <div class="delete-modal card" @click.stop>
        <div class="row" style="gap:.75rem;align-items:center;margin-bottom:1rem">
          <div class="del-modal-icon">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
          </div>
          <div>
            <h2 style="margin:0;font-size:1.15rem">Delete Ticket UAA-{{ t.ticket_no }}?</h2>
            <p class="sub" style="margin:0;font-size:.82rem">Passenger: {{ t.visitor_name || 'Anonymous' }}</p>
          </div>
        </div>
        <p style="font-size:.9rem;line-height:1.5;margin-bottom:1.5rem;color:var(--ink)">
          This will permanently delete this conversation and all {{ msgs.length }} recorded messages. This action cannot be reversed.
        </p>
        <div class="row" style="justify-content:flex-end;gap:.6rem">
          <button class="btn alt" :disabled="isDeleting" @click="confirmDeleteModal = false">
            Cancel
          </button>
          <button class="btn danger" :disabled="isDeleting" @click="deleteChat">
            {{ isDeleting ? 'Deleting…' : 'Yes, Delete Ticket' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Claim Warning Confirmation Modal -->
    <div v-if="showClaimWarningModal" class="delete-modal-backdrop" @click="showClaimWarningModal = false">
      <div class="delete-modal card" @click.stop style="max-width:480px;box-sizing:border-box">
        <div style="display:flex;gap:.75rem;align-items:center;margin-bottom:1rem">
          <div class="del-modal-icon" style="background:#fef3c7;color:#d97706;flex-shrink:0">
            <span style="font-size:1.3rem">⚠️</span>
          </div>
          <div style="flex:1 1 0%;min-width:0">
            <h2 style="margin:0;font-size:1.15rem;color:#92400e;word-break:break-word">Passenger Form Not Submitted</h2>
            <p class="sub" style="margin:0;font-size:.82rem;word-break:break-word">Ticket UAA-{{ t.ticket_no }} · {{ t.visitor_name || 'Anonymous' }}</p>
          </div>
        </div>
        <p style="font-size:.9rem;line-height:1.5;margin-bottom:1.25rem;color:var(--ink);word-break:break-word;overflow-wrap:anywhere">
          This passenger has <strong>not submitted their contact form</strong> yet. Verified contact details (name, email, or phone) are missing.
        </p>
        <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:.75rem 1rem;margin-bottom:1.5rem">
          <p style="margin:0;font-size:.84rem;color:#92400e;line-height:1.45;word-break:break-word;overflow-wrap:anywhere">
            ⚠️ <strong>Notice:</strong> Your live responses will only be visible while the passenger remains in their active browser chat session. They will <strong>not receive an email or SMS notification</strong>.
          </p>
        </div>
        <div class="row" style="justify-content:flex-end;gap:.6rem;flex-wrap:wrap">
          <button class="btn alt" @click="showClaimWarningModal = false">
            Cancel
          </button>
          <button class="btn amber" @click="confirmClaim">
            Yes, Claim Conversation
          </button>
        </div>
      </div>
    </div>

    <!-- Unfilled Form Warning Confirmation Modal -->
    <div v-if="showUnfilledWarningModal" class="delete-modal-backdrop" @click="showUnfilledWarningModal = false">
      <div class="delete-modal card" @click.stop style="max-width:480px;box-sizing:border-box">
        <div style="display:flex;gap:.75rem;align-items:center;margin-bottom:1rem">
          <div class="del-modal-icon" style="background:#fef3c7;color:#d97706;flex-shrink:0">
            <span style="font-size:1.3rem">⚠️</span>
          </div>
          <div style="flex:1 1 0%;min-width:0">
            <h2 style="margin:0;font-size:1.15rem;color:#92400e;word-break:break-word">Passenger Data Not Filled</h2>
            <p class="sub" style="margin:0;font-size:.82rem;word-break:break-word">Ticket UAA-{{ t.ticket_no }} · {{ t.visitor_name || 'Anonymous' }}</p>
          </div>
        </div>
        <p style="font-size:.9rem;line-height:1.5;margin-bottom:1.25rem;color:var(--ink);word-break:break-word;overflow-wrap:anywhere">
          This visitor has <strong>not submitted their contact information</strong> (name, email, or phone number).
        </p>
        <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:.75rem 1rem;margin-bottom:1.5rem">
          <p style="margin:0;font-size:.84rem;color:#92400e;line-height:1.45;word-break:break-word;overflow-wrap:anywhere">
            ⚠️ <strong>Notice:</strong> Your reply will be sent to the visitor's live chat session. However, if the passenger has closed their browser tab, they will <strong>not receive an email or SMS notification</strong>.
          </p>
        </div>
        <div class="row" style="justify-content:flex-end;gap:.6rem;flex-wrap:wrap">
          <button class="btn alt" @click="showUnfilledWarningModal = false">
            Cancel
          </button>
          <button class="btn amber" @click="confirmSendUnfilled">
            Send Reply to Active Session
          </button>
        </div>
      </div>
    </div>
  </template>
</template>

<style scoped>
.unfilled-warning-banner {
  background: #fffbeb;
  border: 1px solid #fde68a;
  border-radius: 8px;
  padding: 0.65rem 0.9rem;
  margin-bottom: 0.75rem;
  display: flex;
  gap: 0.65rem;
  align-items: center;
  width: 100%;
  max-width: 100%;
  box-sizing: border-box;
  overflow: hidden;
}
.warning-icon {
  font-size: 1.15rem;
  flex-shrink: 0;
  line-height: 1;
}
.warning-content {
  flex: 1 1 0%;
  min-width: 0;
  white-space: normal;
  word-wrap: break-word;
  overflow-wrap: break-word;
}
.warning-content strong {
  display: block;
  font-size: 0.84rem;
  color: #92400e;
  line-height: 1.35;
}
.warning-content p {
  margin: 2px 0 0;
  font-size: 0.8rem;
  color: #78350f;
  line-height: 1.4;
  white-space: normal;
  word-wrap: break-word;
  overflow-wrap: break-word;
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
  max-width: 440px;
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
