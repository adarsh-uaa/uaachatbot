<script setup lang="ts">
definePageMeta({ perm: 'sites.manage' })
const sb = useSb(), { show } = useToast()
const sites = ref<any[]>([]), f = ref<any>(null), secrets = ref<any>({ webhook_url: '', dashboard_url: '' }), copyFrom = ref('')
const cfg = useRuntimeConfig().public
const icons = ['chat', 'plane', 'help', 'headset']
const textFields: [string, string][] = [
  ['title', 'Window title'],
  ['subtitle', 'Subtitle'],
  ['greeting', 'Greeting message'],
  ['placeholder', 'Input placeholder'],
  ['fallback', 'When the bot has no answer'],
  ['handoff', 'Talk-to-team button'],
  ['ticketCreated', 'After ticket is created'],
  ['closed', 'Closed conversation note']
]

const previewMode = ref<'bot' | 'chat' | 'form'>('bot')
const activeColorSection = ref<'all' | 'header' | 'bubbles' | 'buttons' | 'input' | 'launcher'>('all')
const mobileTab = ref<'editor' | 'preview'>('editor')

// Delete site modal state
const confirmDeleteModal = ref(false)
const deletingSite = ref(false)

const presets = [
  {
    name: 'Airport Classic Navy',
    desc: 'Deep navy brand with amber accents and clean light surfaces',
    theme: {
      primary: '#0f172a',
      accent: '#f59e0b',
      text: '#0f172a',
      headerBg: '#0f172a',
      headerText: '#ffffff',
      headerSubtext: 'rgba(255,255,255,0.85)',
      headerBorder: '#f59e0b',
      windowBg: '#ffffff',
      chatBg: '#f8fafc',
      visitorBubbleBg: '#0f172a',
      visitorBubbleText: '#ffffff',
      visitorBubbleBorder: '#0f172a',
      botBubbleBg: '#ffffff',
      botBubbleText: '#0f172a',
      botBubbleBorder: '#e2e8f0',
      pillBg: '#ffffff',
      pillText: '#0f172a',
      pillBorder: '#cbd5e1',
      actionBtnBg: '#f59e0b',
      actionBtnText: '#0f172a',
      footerBg: '#ffffff',
      inputBg: '#ffffff',
      inputText: '#0f172a',
      inputBorder: '#e2e8f0',
      sendBtnBg: '#0f172a',
      sendBtnText: '#ffffff',
      launcherBg: '#0f172a',
      launcherIcon: '#ffffff',
      badgeBg: '#e11d48',
      badgeBorder: '#ffffff',
      systemText: '#64748b',
      linkText: '#0f172a'
    }
  },
  {
    name: 'Modern Emerald',
    desc: 'Sophisticated dark forest green with fresh mint accents',
    theme: {
      primary: '#064e3b',
      accent: '#10b981',
      text: '#064e3b',
      headerBg: '#064e3b',
      headerText: '#ffffff',
      headerSubtext: '#a7f3d0',
      headerBorder: '#10b981',
      windowBg: '#ffffff',
      chatBg: '#f0fdf4',
      visitorBubbleBg: '#064e3b',
      visitorBubbleText: '#ffffff',
      visitorBubbleBorder: '#064e3b',
      botBubbleBg: '#ffffff',
      botBubbleText: '#064e3b',
      botBubbleBorder: '#bbf7d0',
      pillBg: '#ffffff',
      pillText: '#064e3b',
      pillBorder: '#86efac',
      actionBtnBg: '#10b981',
      actionBtnText: '#ffffff',
      footerBg: '#ffffff',
      inputBg: '#ffffff',
      inputText: '#064e3b',
      inputBorder: '#bbf7d0',
      sendBtnBg: '#064e3b',
      sendBtnText: '#ffffff',
      launcherBg: '#064e3b',
      launcherIcon: '#ffffff',
      badgeBg: '#ef4444',
      badgeBorder: '#ffffff',
      systemText: '#047857',
      linkText: '#059669'
    }
  },
  {
    name: 'Midnight Dark Mode',
    desc: 'Deep slate & OLED dark with neon cyan highlights',
    theme: {
      primary: '#0f172a',
      accent: '#06b6d4',
      text: '#f8fafc',
      headerBg: '#0f172a',
      headerText: '#f8fafc',
      headerSubtext: '#94a3b8',
      headerBorder: '#06b6d4',
      windowBg: '#1e293b',
      chatBg: '#0f172a',
      visitorBubbleBg: '#06b6d4',
      visitorBubbleText: '#0f172a',
      visitorBubbleBorder: '#06b6d4',
      botBubbleBg: '#1e293b',
      botBubbleText: '#f1f5f9',
      botBubbleBorder: '#334155',
      pillBg: '#1e293b',
      pillText: '#38bdf8',
      pillBorder: '#38bdf8',
      actionBtnBg: '#06b6d4',
      actionBtnText: '#0f172a',
      footerBg: '#1e293b',
      inputBg: '#0f172a',
      inputText: '#f8fafc',
      inputBorder: '#475569',
      sendBtnBg: '#06b6d4',
      sendBtnText: '#0f172a',
      launcherBg: '#0f172a',
      launcherIcon: '#38bdf8',
      badgeBg: '#f43f5e',
      badgeBorder: '#0f172a',
      systemText: '#94a3b8',
      linkText: '#38bdf8'
    }
  },
  {
    name: 'Royal Sapphire & Violet',
    desc: 'Luxurious violet purple with sapphire blue accents',
    theme: {
      primary: '#1e1b4b',
      accent: '#8b5cf6',
      text: '#1e1b4b',
      headerBg: '#1e1b4b',
      headerText: '#ffffff',
      headerSubtext: '#ddd6fe',
      headerBorder: '#8b5cf6',
      windowBg: '#ffffff',
      chatBg: '#faf5ff',
      visitorBubbleBg: '#1e1b4b',
      visitorBubbleText: '#ffffff',
      visitorBubbleBorder: '#1e1b4b',
      botBubbleBg: '#ffffff',
      botBubbleText: '#1e1b4b',
      botBubbleBorder: '#e9d5ff',
      pillBg: '#ffffff',
      pillText: '#6d28d9',
      pillBorder: '#c4b5fd',
      actionBtnBg: '#8b5cf6',
      actionBtnText: '#ffffff',
      footerBg: '#ffffff',
      inputBg: '#ffffff',
      inputText: '#1e1b4b',
      inputBorder: '#ddd6fe',
      sendBtnBg: '#1e1b4b',
      sendBtnText: '#ffffff',
      launcherBg: '#1e1b4b',
      launcherIcon: '#ffffff',
      badgeBg: '#ec4899',
      badgeBorder: '#ffffff',
      systemText: '#7c3aed',
      linkText: '#8b5cf6'
    }
  },
  {
    name: 'Ocean Azure',
    desc: 'Clear flight sky blue with sunny warm action accent',
    theme: {
      primary: '#0369a1',
      accent: '#f97316',
      text: '#0c4a6e',
      headerBg: '#0369a1',
      headerText: '#ffffff',
      headerSubtext: '#e0f2fe',
      headerBorder: '#f97316',
      windowBg: '#ffffff',
      chatBg: '#f0f9ff',
      visitorBubbleBg: '#0369a1',
      visitorBubbleText: '#ffffff',
      visitorBubbleBorder: '#0369a1',
      botBubbleBg: '#ffffff',
      botBubbleText: '#0c4a6e',
      botBubbleBorder: '#bae6fd',
      pillBg: '#ffffff',
      pillText: '#0284c7',
      pillBorder: '#7dd3fc',
      actionBtnBg: '#f97316',
      actionBtnText: '#ffffff',
      footerBg: '#ffffff',
      inputBg: '#ffffff',
      inputText: '#0c4a6e',
      inputBorder: '#bae6fd',
      sendBtnBg: '#0369a1',
      sendBtnText: '#ffffff',
      launcherBg: '#0369a1',
      launcherIcon: '#ffffff',
      badgeBg: '#dc2626',
      badgeBorder: '#ffffff',
      systemText: '#0284c7',
      linkText: '#0284c7'
    }
  },
  {
    name: 'Warm Crimson & Sunset',
    desc: 'Inviting wine red with warm amber and soft blush',
    theme: {
      primary: '#881337',
      accent: '#f59e0b',
      text: '#4c0519',
      headerBg: '#881337',
      headerText: '#ffffff',
      headerSubtext: '#ffe4e6',
      headerBorder: '#f59e0b',
      windowBg: '#ffffff',
      chatBg: '#fff1f2',
      visitorBubbleBg: '#881337',
      visitorBubbleText: '#ffffff',
      visitorBubbleBorder: '#881337',
      botBubbleBg: '#ffffff',
      botBubbleText: '#4c0519',
      botBubbleBorder: '#fecdd3',
      pillBg: '#ffffff',
      pillText: '#9f1239',
      pillBorder: '#fca5a5',
      actionBtnBg: '#f59e0b',
      actionBtnText: '#4c0519',
      footerBg: '#ffffff',
      inputBg: '#ffffff',
      inputText: '#4c0519',
      inputBorder: '#fecdd3',
      sendBtnBg: '#881337',
      sendBtnText: '#ffffff',
      launcherBg: '#881337',
      launcherIcon: '#ffffff',
      badgeBg: '#e11d48',
      badgeBorder: '#ffffff',
      systemText: '#9f1239',
      linkText: '#be123c'
    }
  }
]

function ensureFullTheme(t: any) {
  const p = t.primary || '#0f172a'
  const a = t.accent || '#2563eb'
  const tx = t.text || '#0f172a'
  return {
    primary: p,
    accent: a,
    text: tx,
    radius: t.radius ?? 16,
    position: t.position || 'right',
    icon: t.icon || 'chat',
    iconUrl: t.iconUrl || '',
    headerBg: t.headerBg || p,
    headerText: t.headerText || '#ffffff',
    headerSubtext: t.headerSubtext || 'rgba(255,255,255,0.85)',
    headerBorder: t.headerBorder || a,
    windowBg: t.windowBg || '#ffffff',
    chatBg: t.chatBg || '#f8fafc',
    visitorBubbleBg: t.visitorBubbleBg || p,
    visitorBubbleText: t.visitorBubbleText || '#ffffff',
    visitorBubbleBorder: t.visitorBubbleBorder || p,
    botBubbleBg: t.botBubbleBg || '#ffffff',
    botBubbleText: t.botBubbleText || tx,
    botBubbleBorder: t.botBubbleBorder || '#e2e8f0',
    pillBg: t.pillBg || '#ffffff',
    pillText: t.pillText || p,
    pillBorder: t.pillBorder || '#cbd5e1',
    actionBtnBg: t.actionBtnBg || a,
    actionBtnText: t.actionBtnText || '#ffffff',
    footerBg: t.footerBg || '#ffffff',
    inputBg: t.inputBg || '#ffffff',
    inputText: t.inputText || '#0f172a',
    inputBorder: t.inputBorder || '#e2e8f0',
    sendBtnBg: t.sendBtnBg || p,
    sendBtnText: t.sendBtnText || '#ffffff',
    launcherBg: t.launcherBg || p,
    launcherIcon: t.launcherIcon || '#ffffff',
    badgeBg: t.badgeBg || '#e11d48',
    badgeBorder: t.badgeBorder || '#ffffff',
    systemText: t.systemText || '#64748b',
    linkText: t.linkText || a
  }
}

async function load() {
  sites.value = (await sb.from('sites').select('*').order('created_at')).data || []
  if (sites.value.length > 0 && !f.value) {
    open(sites.value[0])
  }
}
onMounted(load)

async function open(s: any) {
  const clone = JSON.parse(JSON.stringify(s))
  clone.theme = ensureFullTheme(clone.theme || {})
  f.value = { ...clone, origins: (s.allowed_origins || []).join(', ') }
  const r = await sb.from('site_secrets').select('*').eq('site_id', s.id).maybeSingle()
  secrets.value = { webhook_url: r.data?.webhook_url || '', dashboard_url: r.data?.dashboard_url || '' }
}

async function create() {
  const { data, error } = await sb.from('sites').insert({ name: 'New airport property' }).select().single()
  if (error) return show(error.message, 'err')
  await load()
  open(data)
  show('New site created', 'ok')
}

function applyPreset(preset: any) {
  if (!f.value) return
  f.value.theme = {
    ...f.value.theme,
    ...preset.theme
  }
  show(`Applied preset: ${preset.name}`)
}

function applyFrom() {
  const s = sites.value.find(x => x.id === copyFrom.value)
  if (!s) return
  f.value.theme = ensureFullTheme(JSON.parse(JSON.stringify(s.theme)))
  f.value.texts = JSON.parse(JSON.stringify(s.texts))
  f.value.faq_url = s.faq_url
  show('Theme and texts copied. Click Save to keep them.')
}

async function save() {
  if (!f.value?.name.trim()) {
    show('Site name cannot be empty', 'err')
    return
  }
  const row = {
    name: f.value.name,
    faq_url: f.value.faq_url || null,
    theme: f.value.theme,
    texts: f.value.texts,
    is_active: f.value.is_active,
    allowed_origins: f.value.origins.split(',').map((x: string) => x.trim().replace(/\/$/, '')).filter(Boolean)
  }
  const a = await sb.from('sites').update(row).eq('id', f.value.id)
  const b = await sb.from('site_secrets').upsert({
    site_id: f.value.id,
    webhook_url: secrets.value.webhook_url || null,
    dashboard_url: secrets.value.dashboard_url || null
  })
  const err = a.error || b.error
  if (err) show(err.message, 'err')
  else { show('Site changes saved successfully!', 'ok'); load() }
}

async function deleteCurrentSite() {
  if (!f.value?.id) return
  deletingSite.value = true
  try {
    // Attempt 1: Call RPC function delete_site
    const { error: rpcErr } = await sb.rpc('delete_site', { p_site_id: f.value.id })
    if (rpcErr) {
      // Fallback: direct cascading delete if RPC not applied
      await sb.from('tickets').delete().eq('site_id', f.value.id)
      await sb.from('bot_events').delete().eq('site_id', f.value.id)
      await sb.from('bot_rules').delete().eq('site_id', f.value.id)
      await sb.from('canned_replies').delete().eq('site_id', f.value.id)
      await sb.from('site_secrets').delete().eq('site_id', f.value.id)
      const { error: dirErr } = await sb.from('sites').delete().eq('id', f.value.id)
      if (dirErr) throw dirErr
    }
    show(`Site "${f.value.name}" deleted successfully`, 'ok')
    confirmDeleteModal.value = false
    f.value = null
    await load()
  } catch (err: any) {
    show(err.message || 'Failed to delete site', 'err')
  } finally {
    deletingSite.value = false
  }
}

const snippet = computed(() => f.value ? `<script src="https://YOUR-DASHBOARD-DOMAIN/uaa-widget.js" data-site-key="${f.value.site_key}" data-api-url="${cfg.supabaseUrl}" data-api-key="${cfg.supabaseKey}" defer><\/script>` : '')

const previewStyles = computed(() => {
  if (!f.value?.theme) return {}
  const th = f.value.theme
  return {
    '--p': th.primary,
    '--a': th.accent,
    '--t': th.text,
    '--r': `${th.radius ?? 16}px`,
    '--hdr-bg': th.headerBg || th.primary,
    '--hdr-txt': th.headerText || '#ffffff',
    '--hdr-sub': th.headerSubtext || 'rgba(255,255,255,0.85)',
    '--hdr-bdr': th.headerBorder || th.accent,
    '--win-bg': th.windowBg || '#ffffff',
    '--chat-bg': th.chatBg || '#f8fafc',
    '--v-bg': th.visitorBubbleBg || th.primary,
    '--v-txt': th.visitorBubbleText || '#ffffff',
    '--v-bdr': th.visitorBubbleBorder || th.primary,
    '--b-bg': th.botBubbleBg || '#ffffff',
    '--b-txt': th.botBubbleText || th.text,
    '--b-bdr': th.botBubbleBorder || '#e2e8f0',
    '--pill-bg': th.pillBg || '#ffffff',
    '--pill-txt': th.pillText || th.primary,
    '--pill-bdr': th.pillBorder || '#cbd5e1',
    '--act-bg': th.actionBtnBg || th.accent,
    '--act-txt': th.actionBtnText || '#ffffff',
    '--ftr-bg': th.footerBg || '#ffffff',
    '--in-bg': th.inputBg || '#ffffff',
    '--in-txt': th.inputText || '#0f172a',
    '--in-bdr': th.inputBorder || '#e2e8f0',
    '--send-bg': th.sendBtnBg || th.primary,
    '--send-txt': th.sendBtnText || '#ffffff',
    '--fab-bg': th.launcherBg || th.primary,
    '--fab-txt': th.launcherIcon || '#ffffff',
    '--badge-bg': th.badgeBg || '#e11d48',
    '--badge-bdr': th.badgeBorder || '#ffffff',
    '--sys-txt': th.systemText || '#64748b',
    '--lnk-txt': th.linkText || th.accent
  }
})

const ICONS: Record<string, string> = {
  chat: 'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z',
  plane: 'M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z',
  help: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 16h-2v-2h2zm2.1-7.8-.9.9c-.7.7-1.2 1.3-1.2 2.9h-2v-.5c0-1.1.5-2.1 1.2-2.8l1.2-1.3a2 2 0 1 0-3.4-1.4H8a4 4 0 1 1 7.1 2.2z',
  headset: 'M12 2a8 8 0 0 0-8 8v7a3 3 0 0 0 3 3h2v-8H6v-2a6 6 0 0 1 12 0v2h-3v8h4v1h-5v2h5a2 2 0 0 0 2-2V10a8 8 0 0 0-8-8z'
}
</script>

<template>
  <div class="sites-page">
    <div class="page-header-row">
      <div>
        <h1>Sites & Chat Themes</h1>
        <p class="sub" style="margin:0">
          Configure website properties, complete color palettes, wording, and team alerts.
        </p>
      </div>
      <div class="header-actions">
        <button class="btn amber" @click="create">
          <strong>+ Add Site</strong>
        </button>
      </div>
    </div>

    <!-- Horizontal Site Selector Tabs -->
    <div class="site-nav-container">
      <div class="site-nav-scroll">
        <button
          v-for="s in sites"
          :key="s.id"
          class="tab"
          :class="{ on: f?.id === s.id }"
          @click="open(s)"
        >
          <span>{{ s.name }}</span>
          <span v-if="!s.is_active" class="chip" style="font-size:.68rem;padding:0 .4rem;margin-left:.3rem;background:#fee2e2;color:#b91c1c">OFF</span>
        </button>
      </div>
    </div>

    <!-- Empty State if no sites exist -->
    <div v-if="!f && sites.length === 0" class="card empty-sites-card">
      <p class="empty" style="padding:3rem 1rem">
        No websites configured yet. Click <strong>"+ Add Site"</strong> above to set up your first assistance chat desk.
      </p>
    </div>

    <template v-if="f">
      <!-- Site Action Bar: Title, Status, Save & Delete -->
      <div class="site-action-bar card">
        <div class="row" style="gap:.75rem">
          <h2 style="margin:0">{{ f.name }}</h2>
          <span class="chip" :class="f.is_active ? 'closed' : 'open'">
            {{ f.is_active ? 'Live on web' : 'Disabled' }}
          </span>
        </div>
        <div class="row" style="gap:.5rem">
          <button class="btn danger sm" @click="confirmDeleteModal = true" title="Delete this site property">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            <span>Delete Site</span>
          </button>
          <button class="btn amber" @click="save">
            Save Changes
          </button>
        </div>
      </div>

      <!-- Responsive View Toggle on Mobile/Tablet (< 1080px) -->
      <div class="responsive-view-toggle">
        <button class="tab" :class="{ on: mobileTab === 'editor' }" @click="mobileTab = 'editor'">
          ⚙ Customizer & Settings
        </button>
        <button class="tab" :class="{ on: mobileTab === 'preview' }" @click="mobileTab = 'preview'">
          👁 Live Widget Preview
        </button>
      </div>

      <!-- Main Layout: Editor & Live Preview -->
      <div class="theme-customizer-grid">
        <!-- LEFT COLUMN: SETTINGS & CONTROLS -->
        <div class="controls-col" :class="{ 'hidden-mobile': mobileTab === 'preview' }">
          <!-- 1. Basics -->
          <div class="card">
            <h2>Website Basics</h2>
            <div class="cols">
              <div>
                <label>Website / Property Name <span style="color:var(--red)">*</span></label>
                <input v-model="f.name" placeholder="e.g. Heathrow Terminal Assistance">
              </div>
              <div>
                <label>FAQ Help Page URL</label>
                <input v-model="f.faq_url" placeholder="https://airport.com/faq">
              </div>
            </div>

            <label>Allowed Domain Origins <small>(comma separated, e.g. https://www.airport.com; leave blank for any)</small></label>
            <input v-model="f.origins" placeholder="https://yourdomain.com">

            <div class="row" style="margin-top:.85rem;justify-content:space-between">
              <label style="margin:0;font-weight:600;display:inline-flex;align-items:center;gap:.5rem;cursor:pointer">
                <input type="checkbox" v-model="f.is_active" style="width:auto;cursor:pointer">
                <span>Chat Widget is Enabled</span>
              </label>

              <div class="row" style="gap:.4rem">
                <select v-model="copyFrom" style="width:auto;font-size:.85rem">
                  <option value="">Clone theme from…</option>
                  <option v-for="s in sites.filter(x => x.id !== f.id)" :key="s.id" :value="s.id">{{ s.name }}</option>
                </select>
                <button class="btn alt sm" :disabled="!copyFrom" @click="applyFrom">Copy</button>
              </div>
            </div>
          </div>

          <!-- 2. 1-Click Theme Presets -->
          <div class="card">
            <div class="row" style="justify-content:space-between;margin-bottom:.5rem">
              <div>
                <h2>1-Click Design Presets</h2>
                <p class="sub" style="margin:0">Instantly switch color themes. You can customize any individual color below.</p>
              </div>
            </div>
            <div class="grid preset-grid">
              <button
                v-for="preset in presets"
                :key="preset.name"
                type="button"
                class="card preset-btn"
                @click="applyPreset(preset)"
              >
                <div class="row" style="gap:5px;margin-bottom:.5rem">
                  <span class="preset-swatch" :style="{ backgroundColor: preset.theme.headerBg }" />
                  <span class="preset-swatch" :style="{ backgroundColor: preset.theme.accent }" />
                  <span class="preset-swatch" :style="{ backgroundColor: preset.theme.chatBg }" />
                  <span class="preset-swatch" :style="{ backgroundColor: preset.theme.visitorBubbleBg }" />
                  <span class="preset-swatch" :style="{ backgroundColor: preset.theme.botBubbleBg }" />
                </div>
                <strong>{{ preset.name }}</strong>
                <small class="sub" style="display:block;margin-top:.2rem;font-size:.78rem">{{ preset.desc }}</small>
              </button>
            </div>
          </div>

          <!-- 3. Comprehensive Color Controls -->
          <div class="card">
            <h2>Chat Section Colors</h2>
            <p class="sub">Refine individual colors across header, surfaces, bubbles, buttons, and launcher.</p>

            <!-- Categorized Tabs -->
            <div class="tabs" style="margin-bottom:1rem">
              <button class="tab" :class="{ on: activeColorSection === 'all' }" @click="activeColorSection = 'all'">All</button>
              <button class="tab" :class="{ on: activeColorSection === 'header' }" @click="activeColorSection = 'header'">Header & Window</button>
              <button class="tab" :class="{ on: activeColorSection === 'bubbles' }" @click="activeColorSection = 'bubbles'">Bubbles</button>
              <button class="tab" :class="{ on: activeColorSection === 'buttons' }" @click="activeColorSection = 'buttons'">Buttons</button>
              <button class="tab" :class="{ on: activeColorSection === 'input' }" @click="activeColorSection = 'input'">Input</button>
              <button class="tab" :class="{ on: activeColorSection === 'launcher' }" @click="activeColorSection = 'launcher'">Launcher</button>
            </div>

            <!-- Header & Window -->
            <div v-show="activeColorSection === 'all' || activeColorSection === 'header'" class="color-section-block">
              <h3>Header & Window Surfaces</h3>
              <div class="cols color-inputs-grid">
                <div class="color-item">
                  <label>Header Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.headerBg">
                    <input v-model="f.theme.headerBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Header Title Text</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.headerText">
                    <input v-model="f.theme.headerText">
                  </div>
                </div>
                <div class="color-item">
                  <label>Header Subtitle Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.headerSubtext">
                    <input v-model="f.theme.headerSubtext">
                  </div>
                </div>
                <div class="color-item">
                  <label>Header Bottom Accent Line</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.headerBorder">
                    <input v-model="f.theme.headerBorder">
                  </div>
                </div>
                <div class="color-item">
                  <label>Chat Window Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.windowBg">
                    <input v-model="f.theme.windowBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Conversation Body Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.chatBg">
                    <input v-model="f.theme.chatBg">
                  </div>
                </div>
              </div>
            </div>

            <!-- Message Bubbles -->
            <div v-show="activeColorSection === 'all' || activeColorSection === 'bubbles'" class="color-section-block">
              <h3>Message Bubbles (Visitor & Staff)</h3>
              <div class="cols color-inputs-grid">
                <div class="color-item">
                  <label>Visitor Bubble Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.visitorBubbleBg">
                    <input v-model="f.theme.visitorBubbleBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Visitor Bubble Text Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.visitorBubbleText">
                    <input v-model="f.theme.visitorBubbleText">
                  </div>
                </div>
                <div class="color-item">
                  <label>Visitor Bubble Border</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.visitorBubbleBorder">
                    <input v-model="f.theme.visitorBubbleBorder">
                  </div>
                </div>
                <div class="color-item">
                  <label>Bot & Staff Bubble Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.botBubbleBg">
                    <input v-model="f.theme.botBubbleBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Bot & Staff Bubble Text</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.botBubbleText">
                    <input v-model="f.theme.botBubbleText">
                  </div>
                </div>
                <div class="color-item">
                  <label>Bot & Staff Bubble Border</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.botBubbleBorder">
                    <input v-model="f.theme.botBubbleBorder">
                  </div>
                </div>
                <div class="color-item">
                  <label>System Notice Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.systemText">
                    <input v-model="f.theme.systemText">
                  </div>
                </div>
                <div class="color-item">
                  <label>Clickable Link Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.linkText">
                    <input v-model="f.theme.linkText">
                  </div>
                </div>
              </div>
            </div>

            <!-- Buttons & Action Elements -->
            <div v-show="activeColorSection === 'all' || activeColorSection === 'buttons'" class="color-section-block">
              <h3>Quick Reply Pills & Action Buttons</h3>
              <div class="cols color-inputs-grid">
                <div class="color-item">
                  <label>Quick Reply Pill Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.pillBg">
                    <input v-model="f.theme.pillBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Quick Reply Pill Text</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.pillText">
                    <input v-model="f.theme.pillText">
                  </div>
                </div>
                <div class="color-item">
                  <label>Quick Reply Pill Border</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.pillBorder">
                    <input v-model="f.theme.pillBorder">
                  </div>
                </div>
                <div class="color-item">
                  <label>Primary Action Button Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.actionBtnBg">
                    <input v-model="f.theme.actionBtnBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Primary Action Button Text</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.actionBtnText">
                    <input v-model="f.theme.actionBtnText">
                  </div>
                </div>
              </div>
            </div>

            <!-- Input Bar & Footer -->
            <div v-show="activeColorSection === 'all' || activeColorSection === 'input'" class="color-section-block">
              <h3>Compose Bar & Inputs</h3>
              <div class="cols color-inputs-grid">
                <div class="color-item">
                  <label>Footer Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.footerBg">
                    <input v-model="f.theme.footerBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Input Box Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.inputBg">
                    <input v-model="f.theme.inputBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Input Text Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.inputText">
                    <input v-model="f.theme.inputText">
                  </div>
                </div>
                <div class="color-item">
                  <label>Input Border Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.inputBorder">
                    <input v-model="f.theme.inputBorder">
                  </div>
                </div>
                <div class="color-item">
                  <label>Send Button Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.sendBtnBg">
                    <input v-model="f.theme.sendBtnBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Send Button Icon Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.sendBtnText">
                    <input v-model="f.theme.sendBtnText">
                  </div>
                </div>
              </div>
            </div>

            <!-- Launcher FAB & Position -->
            <div v-show="activeColorSection === 'all' || activeColorSection === 'launcher'" class="color-section-block">
              <h3>Launcher Button & Position</h3>
              <div class="cols color-inputs-grid">
                <div class="color-item">
                  <label>Launcher Button Background</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.launcherBg">
                    <input v-model="f.theme.launcherBg">
                  </div>
                </div>
                <div class="color-item">
                  <label>Launcher Icon Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.launcherIcon">
                    <input v-model="f.theme.launcherIcon">
                  </div>
                </div>
                <div class="color-item">
                  <label>Unread Badge Color</label>
                  <div class="row">
                    <input type="color" v-model="f.theme.badgeBg">
                    <input v-model="f.theme.badgeBg">
                  </div>
                </div>
                <div>
                  <label>Corner Radius (px)</label>
                  <input type="number" min="0" max="30" v-model.number="f.theme.radius">
                </div>
                <div>
                  <label>Screen Position</label>
                  <select v-model="f.theme.position">
                    <option value="right">Bottom right</option>
                    <option value="left">Bottom left</option>
                  </select>
                </div>
                <div>
                  <label>Launcher Icon</label>
                  <select v-model="f.theme.icon">
                    <option v-for="i in icons" :key="i">{{ i }}</option>
                    <option value="custom">Custom image URL</option>
                  </select>
                </div>
              </div>
              <template v-if="f.theme.icon === 'custom'">
                <label style="margin-top:.6rem">Custom Icon Image URL</label>
                <input v-model="f.theme.iconUrl" placeholder="https://…/icon.png">
              </template>
            </div>
          </div>

          <!-- 4. Text & Wording Customization -->
          <div class="card">
            <h2>Wording & Labels</h2>
            <div class="cols">
              <div v-for="[k, l] in textFields" :key="k">
                <label>{{ l }}</label>
                <input v-model="f.texts[k]">
              </div>
            </div>
          </div>

          <!-- 5. Team Alerts (Webhook) -->
          <div class="card">
            <h2>Team Alerts & Webhook</h2>
            <p class="sub">Post notifications to a Slack, Discord, or Google Chat incoming webhook.</p>
            <label>Webhook URL</label>
            <input v-model="secrets.webhook_url" placeholder="https://hooks.slack.com/services/…">
            <label>Dashboard URL <small>(used in notification links)</small></label>
            <input v-model="secrets.dashboard_url" placeholder="https://support.yourdomain.com">
          </div>

          <!-- 6. Embed Script -->
          <div class="card">
            <h2>Embed Code</h2>
            <p class="sub">Paste this snippet before &lt;/body&gt; on any website to embed the widget.</p>
            <pre>{{ snippet }}</pre>
            <button class="btn alt sm" @click="copy(snippet).then(() => show('Embed code copied!'))">
              Copy embed code
            </button>
          </div>

          <!-- 7. Danger Zone: Delete Site -->
          <div class="card danger-zone-card">
            <div class="row" style="justify-content:space-between">
              <div>
                <h3 style="color:var(--red);margin:0 0 .2rem">Danger Zone</h3>
                <p class="sub" style="margin:0">Permanently delete this site property, its keyword rules, and tickets.</p>
              </div>
              <button class="btn danger" @click="confirmDeleteModal = true">
                Delete This Site
              </button>
            </div>
          </div>
        </div>

        <!-- RIGHT COLUMN: INTERACTIVE LIVE PREVIEW -->
        <div class="preview-col" :class="{ 'hidden-mobile': mobileTab === 'editor' }">
          <div class="sticky-preview">
            <div class="row" style="justify-content:space-between;margin-bottom:.5rem">
              <h3 style="margin:0">Live Chat Preview</h3>
              <span class="chip role">Realtime</span>
            </div>
            <p class="sub" style="font-size:.82rem;margin-bottom:.65rem">
              Theme changes and color tweaks update instantly in this interactive preview.
            </p>

            <!-- Mode Toggles -->
            <div class="tabs" style="margin-bottom:.75rem">
              <button class="tab sm" :class="{ on: previewMode === 'bot' }" @click="previewMode = 'bot'">Bot Mode</button>
              <button class="tab sm" :class="{ on: previewMode === 'chat' }" @click="previewMode = 'chat'">Agent Chat</button>
              <button class="tab sm" :class="{ on: previewMode === 'form' }" @click="previewMode = 'form'">Ticket Form</button>
            </div>

            <!-- The Live Simulated Widget -->
            <div class="live-widget-wrapper" :style="previewStyles">
              <div class="sim-win">
                <div class="sim-header">
                  <div>
                    <div class="sim-title-row">
                      <span class="sim-online-dot" />
                      <div class="sim-title">{{ f.texts.title || 'Assistance desk' }}</div>
                    </div>
                    <div class="sim-subtitle">
                      {{ previewMode === 'chat' ? 'Sarah J. is assisting you' : (f.texts.subtitle || 'We usually reply in a few minutes') }}
                    </div>
                  </div>
                  <div class="sim-close">×</div>
                </div>

                <div class="sim-body">
                  <template v-if="previewMode === 'bot'">
                    <div class="sim-msg bot">
                      {{ f.texts.greeting || 'Hello! How can we help with your airport assistance?' }}
                    </div>
                    <div class="sim-chips">
                      <button class="sim-pill">Wheelchair assistance</button>
                      <button class="sim-pill">Luggage help</button>
                    </div>
                    <div class="sim-msg me">
                      I need wheelchair assistance at Terminal 2.
                    </div>
                    <div class="sim-msg bot">
                      We provide free assistance for passengers with reduced mobility. Please book at least 48 hours in advance.
                      <a href="#" class="sim-lnk" @click.prevent>Read Assistance FAQ →</a>
                    </div>
                    <button class="sim-pill solid">
                      {{ f.texts.handoff || 'Talk to our team' }}
                    </button>
                  </template>

                  <template v-if="previewMode === 'chat'">
                    <div class="sim-msg me">
                      Can an agent meet me at Gate 14 with a wheelchair?
                    </div>
                    <div class="sim-msg bot">
                      Hello! I'm Sarah from the PRM Assistance desk. We have booked an agent for Gate 14. What time does your flight arrive?
                    </div>
                    <div class="sim-msg me">
                      Flight UA-412 arrives at 16:45.
                    </div>
                    <div class="sim-msg bot">
                      Noted! Our team will be waiting right at the aircraft door.
                    </div>
                    <div class="sim-sys">
                      Conversation active · End-to-end encrypted
                    </div>
                  </template>

                  <template v-if="previewMode === 'form'">
                    <div class="sim-form">
                      <label>Your full name</label>
                      <input class="sim-input" value="Alex Morgan" readonly>
                      <label>Email address</label>
                      <input class="sim-input" value="alex@example.com" readonly>
                      <label>Phone number</label>
                      <input class="sim-input" value="+1 (555) 234-5678" readonly>
                      <label>How can our team help?</label>
                      <textarea class="sim-textarea" rows="2" readonly>Need priority boarding assistance at terminal 1</textarea>
                      <button class="sim-pill solid" style="width:100%;text-align:center;margin-top:.4rem;padding:7px 12px">
                        Send to our team
                      </button>
                    </div>
                  </template>
                </div>

                <div class="sim-footer">
                  <div class="sim-send-bar">
                    <input
                      class="sim-input-box"
                      :placeholder="f.texts.placeholder || 'Type your message…'"
                      value=""
                      readonly
                    >
                    <button class="sim-send-btn">
                      <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
                    </button>
                  </div>
                </div>
              </div>

              <!-- Simulated Launcher Button -->
              <div class="sim-fab-row" :style="{ justifyContent: f.theme.position === 'left' ? 'flex-start' : 'flex-end' }">
                <div class="sim-fab">
                  <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
                    <path :d="ICONS[f.theme.icon] || ICONS.chat" />
                  </svg>
                  <span class="sim-badge" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- CONFIRMATION MODAL: DELETE SITE -->
    <div v-if="confirmDeleteModal && f" class="modal-backdrop" @click.self="confirmDeleteModal = false">
      <div class="modal card" role="dialog" aria-modal="true" aria-labelledby="del-site-title">
        <div class="row" style="justify-content:space-between;margin-bottom:.75rem">
          <div class="row" style="gap:.5rem">
            <span style="display:inline-flex;align-items:center;justify-content:center;width:32px;height:32px;border-radius:8px;background:#fee2e2;color:#dc2626">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
            </span>
            <h2 id="del-site-title" style="margin:0;color:var(--red)">Delete Website Property?</h2>
          </div>
          <button class="x-close" @click="confirmDeleteModal = false" aria-label="Close dialog">×</button>
        </div>

        <p class="sub" style="margin-bottom:1.25rem">
          Are you sure you want to permanently delete <strong>"{{ f.name }}"</strong>?
          This will permanently delete this site, its theme styling, connected bot keyword rules, saved replies, and all historical tickets for this website.
        </p>

        <div class="card" style="background:#fff1f2;border-color:#fecdd3;margin-bottom:1.25rem;padding:.75rem 1rem">
          <p style="margin:0;font-size:.85rem;color:#9f1239;font-weight:600">
            ⚠ Warning: This action cannot be reversed. Any embedded widgets using this site key will cease to load.
          </p>
        </div>

        <div class="row" style="justify-content:flex-end;gap:.6rem">
          <button type="button" class="btn alt" @click="confirmDeleteModal = false">
            Cancel
          </button>
          <button type="button" class="btn danger" :disabled="deletingSite" @click="deleteCurrentSite">
            {{ deletingSite ? 'Deleting Property…' : 'Yes, Delete This Site' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page-header-row {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 1rem;
  flex-wrap: wrap;
  gap: 0.75rem;
}
.site-nav-container {
  margin-bottom: 1.25rem;
  border-bottom: 1px solid var(--line);
  padding-bottom: 0.5rem;
}
.site-nav-scroll {
  display: flex;
  gap: 0.5rem;
  overflow-x: auto;
  padding-bottom: 0.25rem;
  scrollbar-width: thin;
}
.site-action-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-bottom: 1.25rem;
  padding: 0.85rem 1.25rem;
}
.responsive-view-toggle {
  display: none;
  gap: 0.5rem;
  margin-bottom: 1rem;
}
.theme-customizer-grid {
  display: grid;
  grid-template-columns: 1fr 400px;
  gap: 1.5rem;
  align-items: start;
  height: calc(100vh - 165px);
  min-height: 540px;
}
.controls-col {
  overflow-y: auto;
  max-height: 100%;
  padding-right: 0.75rem;
  scrollbar-width: thin;
}
.controls-col::-webkit-scrollbar {
  width: 6px;
}
.controls-col::-webkit-scrollbar-track {
  background: transparent;
}
.controls-col::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 99px;
}
.controls-col::-webkit-scrollbar-thumb:hover {
  background: #94a3b8;
}
.preview-col {
  position: sticky;
  top: 0;
  max-height: 100%;
  overflow-y: auto;
  scrollbar-width: none;
}
.preview-col::-webkit-scrollbar {
  display: none;
}

@media (max-width: 1080px) {
  .responsive-view-toggle {
    display: flex;
  }
  .theme-customizer-grid {
    grid-template-columns: 1fr;
    height: auto;
    min-height: auto;
  }
  .controls-col {
    overflow-y: visible;
    max-height: none;
    padding-right: 0;
  }
  .preview-col {
    position: static;
    max-height: none;
    overflow-y: visible;
  }
  .hidden-mobile {
    display: none !important;
  }
}

.sticky-preview {
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: var(--r);
  padding: 1.25rem;
  box-shadow: var(--shadow);
}
.preset-grid {
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 0.75rem;
  margin-top: 0.75rem;
}
.preset-btn {
  text-align: left;
  cursor: pointer;
  border: 1px solid var(--line);
  transition: all .15s ease;
  margin: 0;
  padding: 0.75rem;
  background: #ffffff;
}
.preset-btn:hover {
  border-color: var(--accent);
  transform: translateY(-2px);
  box-shadow: var(--shadow-md);
}
.preset-swatch {
  display: inline-block;
  width: 18px;
  height: 18px;
  border-radius: 4px;
  border: 1px solid rgba(0,0,0,0.1);
}
.color-section-block {
  margin-bottom: 1.25rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--line-subtle);
}
.color-section-block h3 {
  font-size: 0.95rem;
  margin: 0 0 0.75rem;
  color: var(--teal);
}
.color-inputs-grid {
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.5rem 1rem;
}
.color-item label {
  font-size: 0.8rem;
  margin: 0.4rem 0 0.2rem;
  color: var(--muted);
}
.color-item input[type="color"] {
  width: 36px;
  height: 34px;
  padding: 2px;
  cursor: pointer;
}
.color-item input[type="text"],
.color-item input:not([type="color"]) {
  font-family: monospace;
  font-size: 0.85rem;
  padding: 0.35rem 0.5rem;
}
.danger-zone-card {
  border-color: var(--red-border);
  background: #fffafa;
}

/* Modal styles */
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
  max-width: 520px;
  width: 100%;
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

/* Simulated Live Widget styles */
.live-widget-wrapper {
  margin-top: .75rem;
  font-family: 'Plus Jakarta Sans', system-ui, -apple-system, sans-serif;
}
.sim-win {
  background: var(--win-bg);
  border-radius: var(--r);
  box-shadow: 0 20px 40px -15px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.06);
  border: 1px solid rgba(0,0,0,0.06);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  height: 460px;
}
.sim-header {
  background: var(--hdr-bg);
  color: var(--hdr-txt);
  padding: 12px 14px;
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-bottom: 3px solid var(--hdr-bdr);
}
.sim-title-row {
  display: flex;
  align-items: center;
  gap: 6px;
}
.sim-online-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #22c55e;
  box-shadow: 0 0 0 2px rgba(34, 197, 94, 0.25);
  display: inline-block;
}
.sim-title {
  font-weight: 700;
  font-size: 14px;
  line-height: 1.2;
  letter-spacing: -0.01em;
}
.sim-subtitle {
  color: var(--hdr-sub);
  font-size: 11.5px;
  margin-top: 2px;
  font-weight: 500;
  opacity: 0.9;
}
.sim-close {
  font-size: 18px;
  line-height: 1;
  color: var(--hdr-txt);
  cursor: default;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: rgba(255,255,255,0.1);
  display: grid;
  place-items: center;
}
.sim-body {
  flex: 1;
  background: var(--chat-bg);
  padding: 12px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.sim-msg {
  max-width: 82%;
  padding: 8px 12px;
  border-radius: var(--r);
  font-size: 13px;
  line-height: 1.45;
  word-break: break-word;
  box-shadow: 0 1px 2px rgba(0,0,0,0.03);
}
.sim-msg.bot {
  align-self: flex-start;
  background: var(--b-bg);
  color: var(--b-txt);
  border: 1px solid var(--b-bdr);
  border-bottom-left-radius: 3px;
}
.sim-msg.me {
  align-self: flex-end;
  background: var(--v-bg);
  color: var(--v-txt);
  border: 1px solid var(--v-bdr);
  border-bottom-right-radius: 3px;
}
.sim-lnk {
  display: inline-block;
  margin-top: 4px;
  color: var(--lnk-txt);
  font-weight: 600;
  text-decoration: none;
  font-size: 12px;
}
.sim-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
}
.sim-pill {
  border: 1px solid var(--pill-bdr);
  background: var(--pill-bg);
  color: var(--pill-txt);
  border-radius: 99px;
  padding: 5px 12px;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  align-self: flex-start;
  box-shadow: 0 1px 2px rgba(0,0,0,0.03);
}
.sim-pill.solid {
  background: var(--act-bg);
  border-color: var(--act-bg);
  color: var(--act-txt);
  font-weight: 600;
}
.sim-sys {
  align-self: center;
  color: var(--sys-txt);
  font-size: 11px;
  font-weight: 500;
  margin: 3px 0;
}
.sim-form {
  background: var(--win-bg);
  border: 1px solid var(--b-bdr);
  border-radius: var(--r);
  padding: 10px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
.sim-form label {
  font-size: 11px;
  margin: 0;
  font-weight: 600;
}
.sim-input, .sim-textarea {
  border: 1px solid var(--in-bdr);
  background: var(--in-bg);
  color: var(--in-txt);
  padding: 5px 8px;
  border-radius: 6px;
  font-size: 12px;
}
.sim-footer {
  border-top: 1px solid var(--b-bdr);
  padding: 8px 12px;
  background: var(--ftr-bg);
}
.sim-send-bar {
  display: flex;
  align-items: center;
  gap: 6px;
  border: 1px solid var(--in-bdr);
  border-radius: 20px;
  background: var(--in-bg);
  padding: 2px 3px 2px 10px;
}
.sim-input-box {
  flex: 1;
  border: 0;
  background: transparent;
  color: var(--in-txt);
  font-size: 12px;
  padding: 4px 0;
}
.sim-send-btn {
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
}
.sim-fab-row {
  display: flex;
  margin-top: 12px;
}
.sim-fab {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  background: var(--fab-bg);
  color: var(--fab-txt);
  display: grid;
  place-items: center;
  position: relative;
  box-shadow: 0 8px 20px -4px rgba(0,0,0,0.22);
  transition: transform .15s ease;
}
.sim-badge {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--badge-bg);
  border: 2px solid var(--badge-bdr);
}
</style>
