<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount, nextTick, watch } from 'vue'

const props = defineProps({
  siteKey: String,
  apiUrl: String,
  apiKey: String,
  botEnabled: [Boolean, String],
  bot: [Boolean, String],
  botMode: [Boolean, String],
  botChat: [Boolean, String]
})

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
    windowWidth: base.windowWidth || (base.windowSize === 'compact' ? '315px' : base.windowSize === 'large' ? '365px' : '330px'),
    windowHeight: base.windowHeight || (base.windowSize === 'compact' ? '440px' : base.windowSize === 'large' ? '530px' : '475px'),
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
  `--win-w:${th.value.windowWidth}`,
  `--win-h:${th.value.windowHeight}`,
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

const botChatEnabled = computed(() => {
  const checkVal = v => {
    if (v === true || v === 'true' || v === '1' || v === 1) return true
    if (v === false || v === 'false' || v === '0' || v === 0) return false
    return null
  }

  // 1. Host app explicit prop overrides
  const p1 = checkVal(props.botEnabled)
  if (p1 !== null) return p1
  const p2 = checkVal(props.bot)
  if (p2 !== null) return p2
  const p3 = checkVal(props.botMode)
  if (p3 !== null) return p3
  const p4 = checkVal(props.botChat)
  if (p4 !== null) return p4

  // 2. Global window configuration if app defined window.UAA_BOT_ENABLED or window.uaaBotEnabled
  if (typeof window !== 'undefined') {
    const w1 = checkVal(window.UAA_BOT_ENABLED)
    if (w1 !== null) return w1
    const w2 = checkVal(window.uaaBotEnabled)
    if (w2 !== null) return w2
    const w3 = checkVal(window.uaaBot)
    if (w3 !== null) return w3
  }

  // 3. Database site settings from widget_config RPC
  if (cfg.value?.bot_chat_enabled !== undefined && cfg.value?.bot_chat_enabled !== null) {
    return cfg.value.bot_chat_enabled === true
  }
  if (cfg.value?.theme?.bot_chat_enabled !== undefined && cfg.value?.theme?.bot_chat_enabled !== null) {
    return cfg.value.theme.bot_chat_enabled === true
  }
  return false
})

const buttons = computed(() => {
  const list = cfg.value?.rules || []
  return list.filter(r => r.button_label && r.button_label.trim() !== '')
})
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
  const siteRules = cfg.value?.rules || []
  for (const r of siteRules) {
    // 1. Match button label (e.g. "Terminal amenities")
    if (r.button_label) {
      const bl = norm(r.button_label)
      if (r.match_type === 'exact' ? n === bl : n.includes(bl)) return r
    }
    // 2. Match rule name
    if (r.name) {
      const nm = norm(r.name)
      if (r.match_type === 'exact' ? n === nm : n.includes(nm)) return r
    }
    // 3. Match keywords
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
  if (rule.action === 'handoff') {
    if (rule.response && !rule.response.toLowerCase().includes('could not find an answer') && !rule.response.toLowerCase().includes('find an answer')) {
      push('bot', rule.response, { handoff: true })
    }
    startForm(rule.button_label || rule.name)
    return
  }
  const link = rule.link_url || (rule.action === 'faq_link' ? cfg.value?.faq_url : null)
  push('bot', rule.response, link ? { link, label: rule.button_label || 'Open link' } : {})
}

function handlePillClick(rule) {
  if (!botChatEnabled.value) {
    // Bot mode is disabled: show form directly when clicked
    startForm(rule.button_label || rule.name)
    return
  }

  push('me', rule.button_label)

  if (rule.action === 'handoff') {
    if (rule.response && !rule.response.toLowerCase().includes('could not find an answer') && !rule.response.toLowerCase().includes('find an answer')) {
      push('bot', rule.response, { handoff: true })
    }
    startForm(rule.button_label || rule.name)
    return
  }

  // Immediate instant answer for visitor with zero lag or fallback glitch
  const link = rule.link_url || (rule.action === 'faq_link' ? cfg.value?.faq_url : null)
  push('bot', rule.response, link ? { link, label: rule.button_label || 'Open link' } : {})

  // Background sync with Supabase session & messages
  rpc('widget_bot_chat', {
    p_site_key: props.siteKey,
    p_token: token,
    p_query: rule.button_label
  }).then(res => {
    if (res?.token) {
      token = res.token
      localStorage.setItem(storeKey(), token)
      startPolling()
    }
  }).catch(() => {
    rpc('widget_log_query', {
      p_site_key: props.siteKey,
      p_query: rule.button_label,
      p_rule: rule.id || null,
      p_matched: true
    }).catch(() => {})
  })
}

async function ask(text, rule) {
  push('me', text)
  busy.value = true

  // Check client rule match first for instant, accurate reply
  const matched = rule || (botChatEnabled.value ? match(text) : null)
  if (matched) {
    answer(matched)
    // Sync with backend
    rpc('widget_bot_chat', {
      p_site_key: props.siteKey,
      p_token: token,
      p_query: text
    }).then(res => {
      if (res?.token) {
        token = res.token
        localStorage.setItem(storeKey(), token)
        startPolling()
      }
    }).catch(() => {})
    busy.value = false
    return
  }

  try {
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
      mode.value = 'chat'
      live.value.agent = res.agent
      await poll()
      return
    }

    const isFallback = res?.handoff && (
      !res?.reply ||
      res?.reply.toLowerCase().includes('could not find an answer') ||
      res?.reply === t.value.fallback
    )

    if (isFallback) {
      // Direct form without unwanted text
      startForm(text)
    } else if (res?.reply) {
      const link = res.link_url || null
      push('bot', res.reply, link ? { link, label: res.button_label || 'Open link' } : {})
      if (res.handoff) {
        startForm('Visitor requested team: ' + text)
      }
    }
  } catch {
    startForm(text)
  } finally {
    busy.value = false
  }
}
function startForm(reason = 'Passenger requested live assistance') {
  mode.value = 'form'
  const chosenTopic = (typeof reason === 'string' && reason.trim()) ? reason.trim() : ''
  if (chosenTopic && !chosenTopic.startsWith('Passenger requested') && !chosenTopic.startsWith('Visitor requested') && !chosenTopic.startsWith('Passenger clicked') && !chosenTopic.startsWith('No matching')) {
    form.message = chosenTopic
  } else if (!form.message) {
    const lastUserMsg = [...msgs.value].reverse().find(m => m.from === 'me')?.text || ''
    form.message = lastUserMsg
  }
  scroll()
}

function cancelForm() {
  if (!botChatEnabled.value) return
  mode.value = 'bot'
  form.message = ''
  error.value = ''
}

async function startLiveChat(text) {
  push('me', text)
  busy.value = true
  try {
    const res = await rpc('widget_escalate_to_team', {
      p_site_key: props.siteKey,
      p_token: token,
      p_reason: text
    })
    if (res?.token) {
      token = res.token
      localStorage.setItem(storeKey(), token)
      mode.value = 'chat'
      await poll()
      startPolling()
    }
  } catch {
    try {
      const fallbackTicket = await createTicketWithFallback(
        'Passenger',
        'anonymous@uaa.chat',
        null,
        text
      )
      if (fallbackTicket?.token) {
        token = fallbackTicket.token
        localStorage.setItem(storeKey(), token)
        mode.value = 'chat'
        await poll()
        startPolling()
      }
    } catch (e) {
      error.value = e?.message || 'Failed to send message'
      input.value = text
    }
  } finally {
    busy.value = false
  }
}

async function send() {
  const text = input.value.trim(); if (!text) return
  input.value = ''; error.value = ''
  if (mode.value === 'chat') {
    try { await rpc('widget_send', { p_token: token, p_body: text }); await poll() }
    catch (e) { error.value = e.message === 'closed' ? t.value.closed : e.message; input.value = text }
  } else if (mode.value === 'bot') {
    await ask(text)
  }
}
async function createTicketWithFallback(name = form.name, email = form.email, phone = null, message = form.message) {
  const finalName = name || 'Passenger'
  const finalEmail = email || 'anonymous@uaa.chat'
  const finalMsg = message || 'Assistance requested'
  try {
    return await rpc('widget_create_ticket', {
      p_site_key: props.siteKey,
      p_name: finalName,
      p_email: finalEmail,
      p_phone: phone || null,
      p_message: finalMsg
    })
  } catch (err) {
    const msg = String(err?.message || '')
    // Fallback if database has 4-arg function signature in PostgREST schema cache
    if (msg.includes('schema cache') || msg.includes('Could not find the function') || msg.includes('widget_create_ticket')) {
      const combinedMsg = phone ? `${finalMsg}\n\n[Contact Phone: ${phone}]` : finalMsg
      return await rpc('widget_create_ticket', {
        p_site_key: props.siteKey,
        p_name: finalName,
        p_email: finalEmail,
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
      // Avoid inserting duplicate message if form.message was already sent as a visitor message in this ticket
      const lastUserMsg = [...msgs.value].reverse().find(m => m.from === 'me')?.text?.trim()
      const alreadySent = lastUserMsg && lastUserMsg === form.message.trim()
      const messagePayload = alreadySent ? '' : form.message.trim()

      // Update existing bot chat ticket with visitor details
      r = await rpc('widget_update_visitor_info', {
        p_token: token,
        p_name: form.name,
        p_email: form.email,
        p_phone: fullPhone || null,
        p_message: messagePayload
      }).catch(async () => {
        // Fallback to widget_create_ticket with schema cache fallback
        return await createTicketWithFallback(form.name, form.email, fullPhone, form.message)
      })
    } else {
      r = await createTicketWithFallback(form.name, form.email, fullPhone, form.message)
    }
    token = r.token; localStorage.setItem(storeKey(), token)
    mode.value = 'chat'; await poll(); startPolling()
  } catch (e) {
    const raw = String(e?.message || '')
    if (raw.toLowerCase().includes('origin not allowed')) {
      error.value = 'Domain origin not permitted. In your Support Dashboard, please add this domain (or leave Allowed Domain Origins blank / set "*") in Site Settings.'
    } else {
      error.value = raw || 'Failed to submit form'
    }
  }
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
  } catch {
    token = null
    localStorage.removeItem(storeKey())
    stopPolling()
    setInitialMode()
  }
}
function setInitialMode() {
  mode.value = 'bot'
}
function startPolling() {
  stopPolling()
  timer = setInterval(poll, 4000)
}
function stopPolling() {
  if (timer) {
    clearInterval(timer)
    timer = null
  }
}
function handleVisibility() {
  if (typeof document === 'undefined') return
  if (!token || live.value?.status === 'closed') return
  if (document.hidden) {
    stopPolling()
    timer = setInterval(poll, 15000)
  } else {
    poll()
    startPolling()
  }
}
function newChat() {
  localStorage.removeItem(storeKey())
  token = null
  live.value = { messages: [], status: 'open' }
  setInitialMode()
  lastCount = 0
  form.message = ''
  phoneNumber.value = ''
  error.value = ''
}
function toggle() { open.value = !open.value; if (open.value) { unread.value = false; scroll() } }

onMounted(async () => {
  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', handleVisibility, { passive: true })
  }
  try {
    cfg.value = await rpc('widget_config', { p_site_key: props.siteKey })
    if (cfg.value?.texts?.greeting) {
      msgs.value.push({ from: 'bot', text: cfg.value.texts.greeting })
    }
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
  if (!token) {
    setInitialMode()
  }
})
function setBodyScrollLock(locked) {
  if (typeof document === 'undefined') return
  const host = box.value?.getRootNode()?.host || document.querySelector('uaa-chat')
  if (locked) {
    document.documentElement.classList.add('uaa-chat-open')
    document.body.classList.add('uaa-chat-open')
    document.body.style.overflow = 'hidden'
    if (host) host.setAttribute('data-chat-open', 'true')
  } else {
    document.documentElement.classList.remove('uaa-chat-open')
    document.body.classList.remove('uaa-chat-open')
    document.body.style.overflow = ''
    if (host) host.removeAttribute('data-chat-open')
  }
}

onBeforeUnmount(() => {
  if (typeof document !== 'undefined') {
    document.removeEventListener('visibilitychange', handleVisibility)
  }
  setBodyScrollLock(false)
  stopPolling()
})
watch(open, v => {
  setBodyScrollLock(v)
  if (v) scroll()
})
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
        <!-- 1. Bot Mode: Automated answers and suggestion pills -->
        <template v-if="mode === 'bot'">
          <div v-for="(m, i) in msgs" :key="i" class="m" :class="m.from">
            {{ m.text }}
            <a v-if="m.link" :href="m.link" target="_blank" rel="noopener" class="lnk">{{ m.label }} →</a>
          </div>
          <div v-if="msgs.length < 2 && buttons.length" class="chips">
            <button v-for="b in buttons" :key="b.id || b.button_label" class="pill" @click="handlePillClick(b)">
              {{ b.button_label }}
            </button>
          </div>
        </template>

        <!-- 2. Form Mode: Direct assistance contact form -->
        <template v-else-if="mode === 'form'">
          <form class="form" @submit.prevent="submitForm">
            <div class="form-intro">
              <b>Connect with our Support Team</b>
              <p class="sub">Please share your contact details below so our airport team can assist you.</p>
            </div>
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
            <button
              v-if="botChatEnabled && !token && buttons.length"
              type="button"
              class="cancel-btn"
              @click="cancelForm"
            >
              ← Choose another topic
            </button>
          </form>
        </template>

        <!-- 3. Live Chat Mode: Active agent conversation -->
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

/* Chat Window Frame - Sleek, Compact Minimal Footprint */
.win {
  position: absolute;
  bottom: 66px;
  width: min(var(--win-w, 325px), calc(100vw - 20px));
  height: min(var(--win-h, 460px), calc(100vh - 84px));
  background: var(--win-bg);
  border-radius: var(--r);
  box-shadow: 0 18px 40px -12px rgba(0, 0, 0, 0.2), 0 0 0 1px rgba(0, 0, 0, 0.06);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border: 1px solid rgba(0, 0, 0, 0.05);
  overscroll-behavior: contain;
}
.right .win { right: 0; }
.left .win { left: 0; }

/* Modern Header */
header {
  background: var(--hdr-bg);
  color: var(--hdr-txt);
  padding: 10px 13px;
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-bottom: 2px solid var(--hdr-bdr);
}
.hdr-info {
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.hdr-title-row {
  display: flex;
  align-items: center;
  gap: 6px;
}
.online-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #22c55e;
  box-shadow: 0 0 0 2px rgba(34, 197, 94, 0.25);
  display: inline-block;
}
header b {
  font-size: 13.5px;
  font-weight: 700;
  letter-spacing: -0.01em;
}
header small {
  display: block;
  color: var(--hdr-sub);
  font-size: 11px;
  font-weight: 500;
  opacity: 0.9;
}
.x {
  background: rgba(255, 255, 255, 0.1);
  border: 0;
  color: var(--hdr-txt);
  width: 24px;
  height: 24px;
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
  overscroll-behavior: contain;
  padding: 10px 11px;
  display: flex;
  flex-direction: column;
  gap: 7px;
  background: var(--chat-bg);
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 0, 0, 0.15) transparent;
}
.m {
  max-width: 85%;
  padding: 7px 11px;
  border-radius: var(--r);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  background: var(--b-bg);
  color: var(--b-txt);
  border: 1px solid var(--b-bdr);
  font-size: 12.5px;
  line-height: 1.42;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
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
  font-size: 11.5px;
  font-weight: 500;
  margin: 3px 0;
  line-height: 1.35;
}
.lnk {
  display: inline-block;
  margin-top: 5px;
  color: var(--lnk-txt);
  font-weight: 600;
  font-size: 12px;
  text-decoration: none;
}
.lnk:hover {
  text-decoration: underline;
}

/* Interactive Chips & Pills */
.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
}
.pill {
  border: 1px solid var(--pill-bdr);
  background: var(--pill-bg);
  color: var(--pill-txt);
  border-radius: 99px;
  padding: 4px 9px;
  cursor: pointer;
  font: inherit;
  font-size: 11.5px;
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
  margin-top: 7px;
  width: auto;
}
.form-intro {
  margin-bottom: 4px;
  padding-bottom: 6px;
  border-bottom: 1px solid var(--b-bdr);
}
.form-intro b {
  font-size: 12px;
  color: var(--t);
  display: block;
}
.form-intro .sub {
  margin: 2px 0 0 0;
  font-size: 11px;
  color: var(--sys-txt);
  line-height: 1.35;
}
.cancel-btn {
  background: none;
  border: none;
  color: var(--lnk-txt);
  font-size: 11.5px;
  cursor: pointer;
  padding: 4px;
  text-align: center;
  margin-top: 2px;
  opacity: 0.85;
  transition: opacity 0.15s ease;
}
.cancel-btn:hover {
  opacity: 1;
  text-decoration: underline;
}

/* Ticket Form Inside Widget */
.form {
  display: flex;
  flex-direction: column;
  gap: 6px;
  background: var(--win-bg);
  border: 1px solid var(--b-bdr);
  border-radius: var(--r);
  padding: 9px 10px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.04);
}
.form label {
  display: flex;
  flex-direction: column;
  font-size: 11px;
  font-weight: 600;
  gap: 2px;
  color: var(--t);
}
.form input, .form textarea, .form select {
  font: inherit;
  font-size: 12px;
  border: 1px solid var(--in-bdr);
  border-radius: 6px;
  padding: 5px 8px;
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
  gap: 5px;
  width: 100%;
}
.phone-code-select {
  width: 98px !important;
  min-width: 90px !important;
  flex-shrink: 0 !important;
  cursor: pointer;
  padding: 5px 4px !important;
  font-size: 11.5px !important;
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
  font-size: 11.5px;
  margin: 2px 0;
}

/* Modern Compose Bar */
footer {
  border-top: 1px solid var(--b-bdr);
  padding: 7px 10px;
  background: var(--ftr-bg);
}
.send-bar {
  display: flex;
  align-items: center;
  gap: 5px;
  border: 1px solid var(--in-bdr);
  border-radius: 20px;
  background: var(--in-bg);
  padding: 2px 3px 2px 10px;
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
  font-size: 12.5px;
  padding: 4px 0;
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
  width: 26px;
  height: 26px;
  display: grid;
  place-items: center;
  cursor: pointer;
  flex-shrink: 0;
  transition: transform .15s ease, opacity .15s ease;
}
.send-btn svg {
  width: 13px;
  height: 13px;
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
