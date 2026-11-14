<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount, nextTick, watch } from 'vue'

const props = defineProps({ siteKey: String, apiUrl: String, apiKey: String })

const open = ref(false), cfg = ref(null), failed = ref(false)
const mode = ref('bot')              // bot | form | chat
const msgs = ref([])                 // local bot conversation
const live = ref({ messages: [], status: 'open', agent: null })
const input = ref(''), busy = ref(false), error = ref(''), unread = ref(false)
const form = reactive({ name: '', email: '', phone: '', message: '', website: '' }) // website = honeypot
const box = ref(null)
const storeKey = () => `uaa:${props.siteKey}`
let token = null, timer = null, lastCount = 0

const t = computed(() => cfg.value?.texts || {})
const th = computed(() => {
  const base = cfg.value?.theme || {}
  const p = base.primary || '#0f172a'
  const a = base.accent || '#2563eb'
  const tx = base.text || '#0f172a'
  return {
    primary: p,
    accent: a,
    text: tx,
    radius: base.radius ?? 16,
    position: base.position || 'right',
    icon: base.icon || 'chat',
    iconUrl: base.iconUrl || '',
    headerBg: base.headerBg || p,
    headerText: base.headerText || '#ffffff',
    headerSubtext: base.headerSubtext || 'rgba(255,255,255,0.85)',
    headerBorder: base.headerBorder || a,
    windowBg: base.windowBg || '#ffffff',
    chatBg: base.chatBg || '#f8fafc',
    visitorBubbleBg: base.visitorBubbleBg || p,
    visitorBubbleText: base.visitorBubbleText || '#ffffff',
    visitorBubbleBorder: base.visitorBubbleBorder || p,
    botBubbleBg: base.botBubbleBg || '#ffffff',
    botBubbleText: base.botBubbleText || tx,
    botBubbleBorder: base.botBubbleBorder || '#e2e8f0',
    pillBg: base.pillBg || '#ffffff',
    pillText: base.pillText || p,
    pillBorder: base.pillBorder || '#cbd5e1',
    actionBtnBg: base.actionBtnBg || a,
    actionBtnText: base.actionBtnText || '#ffffff',
    footerBg: base.footerBg || '#ffffff',
    inputBg: base.inputBg || '#ffffff',
    inputText: base.inputText || '#0f172a',
    inputBorder: base.inputBorder || '#e2e8f0',
    sendBtnBg: base.sendBtnBg || p,
    sendBtnText: base.sendBtnText || '#ffffff',
    launcherBg: base.launcherBg || p,
    launcherIcon: base.launcherIcon || '#ffffff',
    badgeBg: base.badgeBg || '#e11d48',
    badgeBorder: base.badgeBorder || '#ffffff',
    systemText: base.systemText || '#64748b',
    linkText: base.linkText || a
  }
})

const style = computed(() => [
  `--p:${th.value.primary}`,
  `--a:${th.value.accent}`,
  `--t:${th.value.text}`,
  `--r:${th.value.radius}px`,
  `--hdr-bg:${th.value.headerBg}`,
  `--hdr-txt:${th.value.headerText}`,
  `--hdr-sub:${th.value.headerSubtext}`,
  `--hdr-bdr:${th.value.headerBorder}`,
  `--win-bg:${th.value.windowBg}`,
  `--chat-bg:${th.value.chatBg}`,
  `--v-bg:${th.value.visitorBubbleBg}`,
  `--v-txt:${th.value.visitorBubbleText}`,
  `--v-bdr:${th.value.visitorBubbleBorder}`,
  `--b-bg:${th.value.botBubbleBg}`,
  `--b-txt:${th.value.botBubbleText}`,
  `--b-bdr:${th.value.botBubbleBorder}`,
  `--pill-bg:${th.value.pillBg}`,
  `--pill-txt:${th.value.pillText}`,
  `--pill-bdr:${th.value.pillBorder}`,
  `--act-bg:${th.value.actionBtnBg}`,
  `--act-txt:${th.value.actionBtnText}`,
  `--ftr-bg:${th.value.footerBg}`,
  `--in-bg:${th.value.inputBg}`,
  `--in-txt:${th.value.inputText}`,
  `--in-bdr:${th.value.inputBorder}`,
  `--send-bg:${th.value.sendBtnBg}`,
  `--send-txt:${th.value.sendBtnText}`,
  `--fab-bg:${th.value.launcherBg}`,
  `--fab-txt:${th.value.launcherIcon}`,
  `--badge-bg:${th.value.badgeBg}`,
  `--badge-bdr:${th.value.badgeBorder}`,
  `--sys-txt:${th.value.systemText}`,
  `--lnk-txt:${th.value.linkText}`
].join(';'))

const buttons = computed(() => (cfg.value?.rules || []).filter(r => r.button_label))
const ICONS = {
  chat: 'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z',
  plane: 'M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z',
  help: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 16h-2v-2h2zm2.1-7.8-.9.9c-.7.7-1.2 1.3-1.2 2.9h-2v-.5c0-1.1.5-2.1 1.2-2.8l1.2-1.3a2 2 0 1 0-3.4-1.4H8a4 4 0 1 1 7.1 2.2z',
  headset: 'M12 2a8 8 0 0 0-8 8v7a3 3 0 0 0 3 3h2v-8H6v-2a6 6 0 0 1 12 0v2h-3v8h4v1h-5v2h5a2 2 0 0 0 2-2V10a8 8 0 0 0-8-8z'
}

async function rpc(name, args) {
  const headers = { 'Content-Type': 'application/json', apikey: props.apiKey }
  if (props.apiKey?.startsWith('eyJ')) headers.Authorization = `Bearer ${props.apiKey}`
  const r = await fetch(`${props.apiUrl}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(args) })
  const j = await r.json().catch(() => null)
  if (!r.ok) throw new Error(j?.message || 'Something went wrong')
  return j
}
const norm = s => ' ' + s.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim() + ' '
function match(text) {
  const n = norm(text)
  for (const r of cfg.value.rules) {
    for (const k of r.keywords) {
      const kk = norm(k)
      if (r.match_type === 'exact' ? n === kk : n.includes(kk)) return r
    }
  }
  return null
}
const scroll = () => nextTick(() => { if (box.value) box.value.scrollTop = box.value.scrollHeight })
const push = (from, text, extra = {}) => { msgs.value.push({ from, text, ...extra }); scroll() }

function answer(rule) {
  if (rule.action === 'handoff') { push('bot', rule.response); startForm(); return }
  const link = rule.link_url || (rule.action === 'faq_link' ? cfg.value.faq_url : null)
  push('bot', rule.response, link ? { link, label: rule.button_label || 'Open link' } : {})
}
async function ask(text, rule) {
  push('me', text)
  busy.value = true
  try {
    // 1. Send query to backend bot chat RPC (which creates/tracks bot chat session)
    const res = await rpc('widget_bot_chat', {
      p_site_key: props.siteKey,
      p_token: token,
      p_query: text
    })
    if (res?.token) {
      token = res.token
      localStorage.setItem(storeKey(), token)
      startPolling()
    }
    if (res?.claimed) {
      // Human agent has taken over this chat! Automated replies stop!
      mode.value = 'chat'
      live.value.agent = res.agent
      await poll()
      return
    }
    // Display bot reply
    if (res?.reply) {
      const link = res.link_url || null
      push('bot', res.reply, {
        ...(link ? { link, label: res.button_label || 'Open link' } : {}),
        ...(res.handoff ? { handoff: true } : {})
      })
    }
  } catch {
    // Fallback to client-side rule matching if offline or before migration
    const r = rule || match(text)
    rpc('widget_log_query', { p_site_key: props.siteKey, p_query: text, p_rule: r?.id || null, p_matched: !!r }).catch(() => {})
    if (r) answer(r)
    else push('bot', t.value.fallback, { handoff: true })
  } finally {
    busy.value = false
  }
}
function startForm() { mode.value = 'form'; if (!form.message) form.message = [...msgs.value].reverse().find(m => m.from === 'me')?.text || ''; scroll() }

async function send() {
  const text = input.value.trim(); if (!text) return
  input.value = ''; error.value = ''
  if (mode.value === 'chat') {
    try { await rpc('widget_send', { p_token: token, p_body: text }); await poll() }
    catch (e) { error.value = e.message === 'closed' ? t.value.closed : e.message; input.value = text }
  } else if (mode.value === 'bot') await ask(text)
}
async function submitForm() {
  error.value = ''
  if (form.website) return                       // bots fill the hidden field
  busy.value = true
  try {
    let r
    if (token) {
      // Update existing bot chat ticket with visitor details
      r = await rpc('widget_update_visitor_info', {
        p_token: token,
        p_name: form.name,
        p_email: form.email,
        p_phone: form.phone || null,
        p_message: form.message
      }).catch(async () => {
        // Fallback to create ticket if function not present
        return await rpc('widget_create_ticket', {
          p_site_key: props.siteKey,
          p_name: form.name,
          p_email: form.email,
          p_phone: form.phone || null,
          p_message: form.message
        })
      })
    } else {
      r = await rpc('widget_create_ticket', {
        p_site_key: props.siteKey,
        p_name: form.name,
        p_email: form.email,
        p_phone: form.phone || null,
        p_message: form.message
      })
    }
    token = r.token; localStorage.setItem(storeKey(), token)
    mode.value = 'chat'; await poll(); startPolling()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}
async function poll() {
  if (!token) return
  try {
    const r = await rpc('widget_messages', { p_token: token })
    live.value = r
    // If ticket was claimed while visitor was in bot mode, automatically switch to live agent chat!
    if (r.status === 'claimed' && mode.value === 'bot') {
      mode.value = 'chat'
    }
    const staffCount = r.messages.filter(m => m.from === 'staff').length
    if (!open.value && staffCount > lastCount) unread.value = true
    lastCount = staffCount
    if (r.status === 'closed') stopPolling()
    scroll()
  } catch { token = null; localStorage.removeItem(storeKey()); stopPolling(); mode.value = 'bot' }
}
function startPolling() { stopPolling(); timer = setInterval(poll, 4000) }
function stopPolling() { clearInterval(timer); timer = null }
function newChat() { localStorage.removeItem(storeKey()); token = null; live.value = { messages: [], status: 'open' }; mode.value = 'bot'; lastCount = 0; form.message = '' }
function toggle() { open.value = !open.value; if (open.value) { unread.value = false; scroll() } }

onMounted(async () => {
  try {
    cfg.value = await rpc('widget_config', { p_site_key: props.siteKey })
    msgs.value.push({ from: 'bot', text: cfg.value.texts.greeting })
  } catch { failed.value = true; return }
  token = localStorage.getItem(storeKey())
  if (token) {
    try {
      const r = await rpc('widget_messages', { p_token: token })
      live.value = r
      if (r.status === 'claimed' || (r.messages && r.messages.some(m => m.from === 'staff'))) {
        mode.value = 'chat'
      }
      if (r.status !== 'closed') startPolling()
    } catch {
      token = null
      localStorage.removeItem(storeKey())
    }
  }
})
onBeforeUnmount(stopPolling)
watch(open, v => v && scroll())
</script>

<template>
  <div v-if="cfg && !failed" class="uaa" :class="th.position" :style="style">
    <section v-if="open" class="win" role="dialog" aria-label="Support chat">
      <header>
        <div class="hdr-info">
          <div class="hdr-title-row">
            <span class="online-dot" />
            <b>{{ t.title }}</b>
          </div>
          <small>{{ mode === 'chat' && live.agent ? `${live.agent} is assisting you` : t.subtitle }}</small>
        </div>
        <button class="x" aria-label="Close chat" @click="toggle">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </header>
      <div ref="box" class="body" aria-live="polite">
        <template v-if="mode !== 'chat'">
          <div v-for="(m, i) in msgs" :key="i" class="m" :class="m.from">
            {{ m.text }}
            <a v-if="m.link" :href="m.link" target="_blank" rel="noopener" class="lnk">{{ m.label }} →</a>
            <button v-if="m.handoff" class="pill solid" @click="startForm">{{ t.handoff }}</button>
          </div>
          <div v-if="msgs.length < 2 && buttons.length" class="chips">
            <button v-for="b in buttons" :key="b.id" class="pill" @click="ask(b.button_label, b)">
              {{ b.button_label }}
            </button>
          </div>
          <button v-if="msgs.length > 1 && mode === 'bot'" class="pill solid" @click="startForm">
            {{ t.handoff }}
          </button>
          <form v-if="mode === 'form'" class="form" @submit.prevent="submitForm">
            <label>Your full name<input v-model="form.name" required maxlength="80" autocomplete="name" placeholder="Alex Morgan"></label>
            <label>Email address<input v-model="form.email" type="email" required maxlength="160" autocomplete="email" placeholder="alex@example.com"></label>
            <label>Phone number<input v-model="form.phone" type="tel" maxlength="40" autocomplete="tel" placeholder="+1 (555) 000-0000"></label>
            <label>How can our team help?<textarea v-model="form.message" required maxlength="4000" rows="3" placeholder="Flight details, assistance required…" /></label>
            <input v-model="form.website" class="hp" tabindex="-1" autocomplete="off" aria-hidden="true">
            <p v-if="error" class="err">{{ error }}</p>
            <button class="pill solid" :disabled="busy" style="width:100%;text-align:center;margin-top:.4rem;padding:9px 16px">
              {{ busy ? 'Submitting…' : 'Send to our team' }}
            </button>
          </form>
        </template>
        <template v-else>
          <div
            v-for="(m, i) in live.messages"
            :key="i"
            class="m"
            :class="m.from === 'visitor' ? 'me' : m.from === 'system' ? 'sys' : 'bot'"
          >
            {{ m.text }}
          </div>
          <p v-if="live.messages.length === 1" class="sys">{{ t.ticketCreated }}</p>
          <div v-if="live.status === 'closed'" class="sys">
            {{ t.closed }}
            <button class="pill solid" style="margin-top:.4rem" @click="newChat">Start a new conversation</button>
          </div>
        </template>
      </div>
      <footer v-if="mode !== 'form' && live.status !== 'closed'">
        <p v-if="error && mode !== 'form'" class="err">{{ error }}</p>
        <div class="send-bar">
          <input
            v-model="input"
            :placeholder="t.placeholder || 'Type your message…'"
            maxlength="1000"
            aria-label="Message"
            @keyup.enter="send"
          >
          <button class="send-btn" aria-label="Send message" @click="send">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
          </button>
        </div>
      </footer>
    </section>

    <!-- Floating Action Button (FAB) -->
    <button class="fab" :aria-label="open ? 'Close chat' : 'Open chat'" @click="toggle">
      <img v-if="th.icon === 'custom' && th.iconUrl" :src="th.iconUrl" alt="">
      <svg v-else viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true">
        <path :d="ICONS[th.icon] || ICONS.chat" />
      </svg>
      <i v-if="unread" class="badge" />
    </button>
  </div>
</template>

<style>
.uaa {
  position: fixed;
  bottom: 24px;
  z-index: 2147483000;
  font-family: 'Plus Jakarta Sans', system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  font-size: 14px;
  line-height: 1.5;
  color: var(--t);
  -webkit-font-smoothing: antialiased;
}
.uaa.right { right: 24px; }
.uaa.left { left: 24px; }
.uaa * { box-sizing: border-box; }

/* Floating Action Button (FAB) */
.fab {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: 0;
  background: var(--fab-bg);
  color: var(--fab-txt);
  cursor: pointer;
  display: grid;
  place-items: center;
  box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.25), 0 8px 10px -6px rgba(0, 0, 0, 0.12);
  position: relative;
  float: right;
  transition: transform 0.2s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}
.left .fab { float: left; }
.fab:hover {
  transform: scale(1.06);
  box-shadow: 0 14px 28px -4px rgba(0, 0, 0, 0.3);
}
.fab:active {
  transform: scale(0.95);
}
.fab img {
  width: 26px;
  height: 26px;
  object-fit: contain;
}
.fab:focus-visible, .uaa button:focus-visible, .uaa input:focus-visible, .uaa textarea:focus-visible {
  outline: 2px solid var(--a);
  outline-offset: 2px;
}
.badge {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: var(--badge-bg);
  border: 2px solid var(--badge-bdr);
  animation: badgePulse 2s infinite;
}
@keyframes badgePulse {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.15); }
}

/* Chat Window Frame */
.win {
  position: absolute;
  bottom: 74px;
  width: min(380px, calc(100vw - 32px));
  height: min(580px, calc(100vh - 110px));
  background: var(--win-bg);
  border-radius: var(--r);
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.22), 0 0 0 1px rgba(0, 0, 0, 0.06);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border: 1px solid rgba(0, 0, 0, 0.05);
}
.right .win { right: 0; }
.left .win { left: 0; }

/* Modern Header */
header {
  background: var(--hdr-bg);
  color: var(--hdr-txt);
  padding: 14px 16px;
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-bottom: 3px solid var(--hdr-bdr);
}
.hdr-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.hdr-title-row {
  display: flex;
  align-items: center;
  gap: 6px;
}
.online-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #22c55e;
  box-shadow: 0 0 0 2px rgba(34, 197, 94, 0.25);
  display: inline-block;
}
header b {
  font-size: 15px;
  font-weight: 700;
  letter-spacing: -0.01em;
}
header small {
  display: block;
  color: var(--hdr-sub);
  font-size: 12px;
  font-weight: 500;
  opacity: 0.9;
}
.x {
  background: rgba(255, 255, 255, 0.1);
  border: 0;
  color: var(--hdr-txt);
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  cursor: pointer;
  transition: background .15s ease, transform .15s ease;
  padding: 0;
}
.x:hover {
  background: rgba(255, 255, 255, 0.22);
  transform: scale(1.05);
}

/* Chat Body & Messages */
.body {
  flex: 1;
  overflow-y: auto;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  background: var(--chat-bg);
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 0, 0, 0.15) transparent;
}
.m {
  max-width: 82%;
  padding: 9px 13px;
  border-radius: var(--r);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  background: var(--b-bg);
  color: var(--b-txt);
  border: 1px solid var(--b-bdr);
  font-size: 13.5px;
  line-height: 1.5;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}
.m.bot {
  align-self: flex-start;
  border-bottom-left-radius: 4px;
}
.m.me {
  align-self: flex-end;
  background: var(--v-bg);
  color: var(--v-txt);
  border-color: var(--v-bdr);
  border-bottom-right-radius: 4px;
}
.sys {
  align-self: center;
  text-align: center;
  color: var(--sys-txt);
  font-size: 12px;
  font-weight: 500;
  margin: 4px 0;
  line-height: 1.4;
}
.lnk {
  display: inline-block;
  margin-top: 6px;
  color: var(--lnk-txt);
  font-weight: 600;
  font-size: 12.5px;
  text-decoration: none;
}
.lnk:hover {
  text-decoration: underline;
}

/* Interactive Chips & Pills */
.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.pill {
  border: 1px solid var(--pill-bdr);
  background: var(--pill-bg);
  color: var(--pill-txt);
  border-radius: 99px;
  padding: 6px 13px;
  cursor: pointer;
  font: inherit;
  font-size: 13px;
  font-weight: 500;
  align-self: flex-start;
  transition: all .15s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}
.pill:hover {
  transform: translateY(-1px);
  box-shadow: 0 3px 6px rgba(0, 0, 0, 0.08);
}
.pill.solid {
  background: var(--act-bg);
  border-color: var(--act-bg);
  color: var(--act-txt);
  font-weight: 600;
}
.chips .pill {
  margin: 0;
}

/* Ticket Form Inside Widget */
.form {
  display: flex;
  flex-direction: column;
  gap: 8px;
  background: var(--win-bg);
  border: 1px solid var(--b-bdr);
  border-radius: var(--r);
  padding: 12px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.04);
}
.form label {
  display: flex;
  flex-direction: column;
  font-size: 12px;
  font-weight: 600;
  gap: 3px;
  color: var(--t);
}
.form input, .form textarea {
  font: inherit;
  font-size: 13px;
  border: 1px solid var(--in-bdr);
  border-radius: 8px;
  padding: 7px 10px;
  color: var(--in-txt);
  background: var(--in-bg);
  width: 100%;
  transition: border-color .15s ease;
}
.form input:focus, .form textarea:focus {
  outline: none;
  border-color: var(--a);
}
.hp {
  position: absolute !important;
  left: -9999px;
  width: 1px;
  height: 1px;
  opacity: 0;
}
.err {
  color: #e11d48;
  font-weight: 600;
  font-size: 12px;
  margin: 2px 0;
}

/* Modern Compose Bar */
footer {
  border-top: 1px solid var(--b-bdr);
  padding: 10px 14px;
  background: var(--ftr-bg);
}
.send-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  border: 1px solid var(--in-bdr);
  border-radius: 24px;
  background: var(--in-bg);
  padding: 3px 4px 3px 12px;
  transition: border-color .15s ease, box-shadow .15s ease;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
}
.send-bar:focus-within {
  border-color: var(--a);
  box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.12);
}
.send-bar input {
  flex: 1;
  border: 0;
  background: transparent;
  color: var(--in-txt);
  font: inherit;
  font-size: 13.5px;
  padding: 6px 0;
  min-width: 0;
}
.send-bar input:focus {
  outline: none;
}
.send-btn {
  border: 0;
  background: var(--send-bg);
  color: var(--send-txt);
  border-radius: 50%;
  width: 32px;
  height: 32px;
  display: grid;
  place-items: center;
  cursor: pointer;
  flex-shrink: 0;
  transition: transform .15s ease, opacity .15s ease;
}
.send-btn:hover {
  transform: scale(1.06);
  opacity: 0.95;
}
.send-btn:active {
  transform: scale(0.94);
}

@media (prefers-reduced-motion: no-preference) {
  .win {
    animation: uaaIn 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  }
}
@keyframes uaaIn {
  from {
    opacity: 0;
    transform: scale(0.96) translateY(12px);
  }
  to {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}
</style>
