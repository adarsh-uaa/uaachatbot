<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount, nextTick, watch } from 'vue'

const props = defineProps({ siteKey: String, apiUrl: String, apiKey: String })

const open = ref(false), cfg = ref(null), failed = ref(false)
const mode = ref('bot')              // bot | form | chat
const msgs = ref([])                 // local bot conversation
const live = ref({ messages: [], status: 'open', agent: null })
const input = ref(''), busy = ref(false), error = ref(''), unread = ref(false)
const form = reactive({ name: '', email: '', phone: '', message: '', website: '' }) // website = honeypot
const countryCode = ref('+1')
const phoneNumber = ref('')

const COUNTRY_CODES = [
  { code: '+1', flag: '🇺🇸', label: 'US/CA (+1)' },
  { code: '+44', flag: '🇬🇧', label: 'UK (+44)' },
  { code: '+91', flag: '🇮🇳', label: 'India (+91)' },
  { code: '+971', flag: '🇦🇪', label: 'UAE (+971)' },
  { code: '+966', flag: '🇸🇦', label: 'Saudi (+966)' },
  { code: '+974', flag: '🇶🇦', label: 'Qatar (+974)' },
  { code: '+61', flag: '🇦🇺', label: 'Australia (+61)' },
  { code: '+65', flag: '🇸🇬', label: 'Singapore (+65)' },
  { code: '+49', flag: '🇩🇪', label: 'Germany (+49)' },
  { code: '+33', flag: '🇫🇷', label: 'France (+33)' },
  { code: '+34', flag: '🇪🇸', label: 'Spain (+34)' },
  { code: '+39', flag: '🇮🇹', label: 'Italy (+39)' },
  { code: '+31', flag: '🇳🇱', label: 'Netherlands (+31)' },
  { code: '+41', flag: '🇨🇭', label: 'Switzerland (+41)' },
  { code: '+353', flag: '🇮🇪', label: 'Ireland (+353)' },
  { code: '+81', flag: '🇯🇵', label: 'Japan (+81)' },
  { code: '+82', flag: '🇰🇷', label: 'South Korea (+82)' },
  { code: '+86', flag: '🇨🇳', label: 'China (+86)' },
  { code: '+852', flag: '🇭🇰', label: 'Hong Kong (+852)' },
  { code: '+60', flag: '🇲🇾', label: 'Malaysia (+60)' },
  { code: '+66', flag: '🇹🇭', label: 'Thailand (+66)' },
  { code: '+62', flag: '🇮🇩', label: 'Indonesia (+62)' },
  { code: '+63', flag: '🇵🇭', label: 'Philippines (+63)' },
  { code: '+84', flag: '🇻🇳', label: 'Vietnam (+84)' },
  { code: '+64', flag: '🇳🇿', label: 'New Zealand (+64)' },
  { code: '+27', flag: '🇿🇦', label: 'South Africa (+27)' },
  { code: '+20', flag: '🇪🇬', label: 'Egypt (+20)' },
  { code: '+90', flag: '🇹🇷', label: 'Turkey (+90)' },
  { code: '+55', flag: '🇧🇷', label: 'Brazil (+55)' },
  { code: '+52', flag: '🇲🇽', label: 'Mexico (+52)' }
]
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

const buttons = computed(() => {
  const list = (cfg.value?.rules?.length) ? cfg.value.rules : DEFAULT_RULES
  return list.filter(r => r.button_label && r.button_label !== 'Hello')
})

const DEFAULT_RULES = [
  {
    name: 'Greetings & Welcome',
    keywords: ['hello', 'hi', 'hey', 'good morning', 'good afternoon', 'good evening', 'start', 'greetings', 'help', 'howdy'],
    match_type: 'contains',
    action: 'reply',
    response: 'Hello! Welcome to our airport assistance desk. How can we help you today? You can ask about wheelchair assistance, baggage, flight details, or connect directly with our team.',
    button_label: 'Hello'
  },
  {
    name: 'Wheelchair & Mobility (PRM)',
    keywords: ['wheelchair', 'mobility', 'prm', 'disabled', 'disability', 'handicap', 'walking', 'elderly', 'senior', 'stretcher', 'ramp', 'special assistance', 'escort', 'buggy', 'electric cart', 'accessible'],
    match_type: 'contains',
    action: 'reply',
    response: 'We provide dedicated assistance for passengers with reduced mobility (PRM) free of charge. Our team can meet you at terminal entry, assist through check-in, security, and boarding. Please book at least 48 hours in advance for priority scheduling.',
    button_label: 'Wheelchair assistance'
  },
  {
    name: 'Baggage & Lost Items',
    keywords: ['baggage', 'luggage', 'bags', 'bag', 'suitcase', 'lost bag', 'lost luggage', 'delayed baggage', 'damaged bag', 'carousel', 'lost property', 'lost and found', 'lost item', 'lost my', 'left behind', 'left luggage'],
    match_type: 'contains',
    action: 'reply',
    response: 'For baggage retrieval, delayed luggage, or items left inside the terminal, our Lost Property & Baggage desk is located in the Arrivals Hall near Carousel 3. Would you like to connect with our team to report a lost item?',
    button_label: 'Lost baggage & items'
  },
  {
    name: 'Flight & Gate Info',
    keywords: ['flight', 'gate', 'terminal', 'boarding', 'check in', 'checkin', 'check-in', 'delay', 'departure', 'arrival', 'boarding pass', 'counter', 'security', 'fast track', 'customs', 'passport'],
    match_type: 'contains',
    action: 'reply',
    response: 'Check-in desks open 3 hours prior to international flights and 2 hours for domestic flights. Live gate assignments and flight schedules are displayed on terminal screens throughout the airport.',
    button_label: 'Flight & Gate info'
  },
  {
    name: 'Terminal Amenities & Wi-Fi',
    keywords: ['wifi', 'wi-fi', 'internet', 'restroom', 'restrooms', 'toilet', 'toilets', 'bathroom', 'washroom', 'food', 'restaurant', 'cafe', 'coffee', 'lounge', 'lounges', 'atm', 'cash', 'money', 'charging', 'charger', 'parking', 'taxi', 'cab', 'bus', 'train', 'water', 'smoking', 'prayer'],
    match_type: 'contains',
    action: 'reply',
    response: 'Free high-speed airport Wi-Fi is available across all terminals. Restrooms, charging stations, prayer rooms, dining, and airline lounges are located along the central concourses.',
    button_label: 'Terminal amenities'
  },
  {
    name: 'Talk to Support Team',
    keywords: ['human', 'agent', 'person', 'staff', 'representative', 'talk to someone', 'speak to someone', 'talk to team', 'connect', 'live agent', 'operator', 'call me', 'urgent', 'real person', 'help me'],
    match_type: 'contains',
    action: 'handoff',
    response: 'I would be happy to connect you with our assistance team. Please fill in your details below so an agent can assist you right away:',
    button_label: 'Talk to our team'
  }
]

const showEscalateOption = computed(() => mode.value === 'bot' && msgs.value.length > 1 && !msgs.value.some(m => m.handoff))
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
  const rules = (cfg.value?.rules?.length) ? cfg.value.rules : DEFAULT_RULES
  for (const r of rules) {
    for (const k of (r.keywords || [])) {
      const kk = norm(k)
      if (r.match_type === 'exact' ? n === kk : n.includes(kk)) return r
    }
  }
  return null
}
const scroll = () => nextTick(() => { if (box.value) box.value.scrollTop = box.value.scrollHeight })
const push = (from, text, extra = {}) => { msgs.value.push({ from, text, ...extra }); scroll() }

function answer(rule) {
  if (rule.action === 'handoff') { push('bot', rule.response, { handoff: true }); startForm(); return }
  const link = rule.link_url || (rule.action === 'faq_link' ? cfg.value?.faq_url : null)
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

    // Check if backend returned a fallback response
    const isFallback = res?.handoff && (
      !res?.reply ||
      res?.reply.toLowerCase().includes('could not find an answer') ||
      res?.reply === t.value.fallback
    )

    // If server fell back, check client-side default keyword rules before presenting fallback
    if (isFallback) {
      const clientRule = rule || match(text)
      if (clientRule) {
        if (clientRule.action === 'handoff') {
          push('bot', clientRule.response, { handoff: true })
          startForm()
        } else {
          const link = clientRule.link_url || (clientRule.action === 'faq_link' ? cfg.value?.faq_url : null)
          push('bot', clientRule.response, link ? { link, label: clientRule.button_label || 'Open link' } : {})
        }
        return
      }
    }

    // Display bot reply
    if (res?.reply) {
      const link = res.link_url || null
      const replyMsg = isFallback
        ? (t.value.fallback || 'I could not find an automated answer for that. Would you like to connect with our support team? Please share your details below.')
        : res.reply
      push('bot', replyMsg, {
        ...(link ? { link, label: res.button_label || 'Open link' } : {}),
        ...(res.handoff ? { handoff: true } : {})
      })
    }
  } catch {
    // Fallback to client-side rule matching if offline or before migration
    const r = rule || match(text)
    rpc('widget_log_query', { p_site_key: props.siteKey, p_query: text, p_rule: r?.id || null, p_matched: !!r }).catch(() => {})
    if (r) answer(r)
    else {
      const fallbackMsg = t.value.fallback || 'I could not find an automated answer for that. Would you like to connect with our support team? Please share your details below.'
      push('bot', fallbackMsg, { handoff: true })
    }
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
async function createTicketWithFallback(phone) {
  try {
    return await rpc('widget_create_ticket', {
      p_site_key: props.siteKey,
      p_name: form.name,
      p_email: form.email,
      p_phone: phone || null,
      p_message: form.message
    })
  } catch (err) {
    const msg = String(err?.message || '')
    // Fallback if database has 4-arg function signature in PostgREST schema cache
    if (msg.includes('schema cache') || msg.includes('Could not find the function') || msg.includes('widget_create_ticket')) {
      const combinedMsg = phone ? `${form.message}\n\n[Contact Phone: ${phone}]` : form.message
      return await rpc('widget_create_ticket', {
        p_site_key: props.siteKey,
        p_name: form.name,
        p_email: form.email,
        p_message: combinedMsg
      })
    }
    throw err
  }
}

async function submitForm() {
  error.value = ''
  if (form.website) return                       // bots fill the hidden field
  busy.value = true
  try {
    const fullPhone = phoneNumber.value.trim() ? `${countryCode.value} ${phoneNumber.value.trim()}` : ''
    form.phone = fullPhone
    let r
    if (token) {
      // Update existing bot chat ticket with visitor details
      r = await rpc('widget_update_visitor_info', {
        p_token: token,
        p_name: form.name,
        p_email: form.email,
        p_phone: fullPhone || null,
        p_message: form.message
      }).catch(async () => {
        // Fallback to widget_create_ticket with schema cache fallback
        return await createTicketWithFallback(fullPhone)
      })
    } else {
      r = await createTicketWithFallback(fullPhone)
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
function newChat() { localStorage.removeItem(storeKey()); token = null; live.value = { messages: [], status: 'open' }; mode.value = 'bot'; lastCount = 0; form.message = ''; phoneNumber.value = '' }
function toggle() { open.value = !open.value; if (open.value) { unread.value = false; scroll() } }

onMounted(async () => {
  try {
    cfg.value = await rpc('widget_config', { p_site_key: props.siteKey })
    msgs.value.push({ from: 'bot', text: cfg.value.texts.greeting })
    if (cfg.value?.theme?.defaultCountryCode) {
      countryCode.value = cfg.value.theme.defaultCountryCode
    }
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
            <button
              v-if="m.handoff && i === msgs.length - 1"
              class="pill solid handoff-btn"
              @click="startForm"
            >
              {{ t.handoff || 'Connect with our team' }}
            </button>
          </div>
          <div v-if="msgs.length < 2 && buttons.length" class="chips">
            <button v-for="b in buttons" :key="b.id || b.button_label" class="pill" @click="ask(b.button_label, b)">
              {{ b.button_label }}
            </button>
          </div>
          <div v-if="showEscalateOption" class="escalate-row">
            <button class="txt-btn" @click="startForm">
              Need live assistance? Connect with our team →
            </button>
          </div>
          <form v-if="mode === 'form'" class="form" @submit.prevent="submitForm">
            <label>Your full name<input v-model="form.name" required maxlength="80" autocomplete="name" placeholder="Alex Morgan"></label>
            <label>Email address<input v-model="form.email" type="email" required maxlength="160" autocomplete="email" placeholder="alex@example.com"></label>
            <label>Phone number
              <div class="phone-row">
                <select v-model="countryCode" class="phone-code-select" aria-label="Country dial code">
                  <option v-for="c in COUNTRY_CODES" :key="c.code" :value="c.code">
                    {{ c.flag }} {{ c.code }}
                  </option>
                </select>
                <input
                  v-model="phoneNumber"
                  type="tel"
                  maxlength="25"
                  autocomplete="tel-national"
                  placeholder="555-0199"
                  class="phone-national-input"
                >
              </div>
            </label>
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
.handoff-btn {
  display: block;
  margin-top: 8px;
  width: auto;
}
.escalate-row {
  display: flex;
  justify-content: center;
  padding: 4px 0;
}
.txt-btn {
  background: none;
  border: none;
  color: var(--sys-txt);
  font-size: 12px;
  cursor: pointer;
  padding: 4px 8px;
  text-decoration: underline;
  opacity: 0.85;
  transition: opacity 0.15s ease, color 0.15s ease;
}
.txt-btn:hover {
  opacity: 1;
  color: var(--a);
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
.form input, .form textarea, .form select {
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
.form input:focus, .form textarea:focus, .form select:focus {
  outline: none;
  border-color: var(--a);
}
.phone-row {
  display: flex !important;
  flex-direction: row !important;
  align-items: center;
  gap: 6px;
  width: 100%;
}
.phone-code-select {
  width: 105px !important;
  min-width: 95px !important;
  flex-shrink: 0 !important;
  cursor: pointer;
  padding: 7px 6px !important;
}
.phone-national-input {
  flex: 1 !important;
  min-width: 0 !important;
  width: auto !important;
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
