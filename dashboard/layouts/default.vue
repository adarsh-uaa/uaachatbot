<script setup lang="ts">
const auth = useAuth()
const staff = useStaff()
const sb = useSb()
const { toast, show } = useToast()
const route = useRoute()

const mobileOpen = ref(false)
watch(() => route.fullPath, () => {
  mobileOpen.value = false
})

const nav = computed(() => [
  { to: '/', label: 'Dashboard', icon: 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z', ok: auth.can('dashboard.view') },
  { to: '/tickets', label: 'Tickets', icon: 'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0-2-.9-2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z', ok: auth.can('tickets.view_all') || auth.can('tickets.view_recent') },
  { to: '/rules', label: 'Keyword rules', icon: 'M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z', ok: auth.can('rules.manage') },
  { to: '/canned', label: 'Saved replies', icon: 'M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-2 10H7v-2h10v2zm0-4H7V7h10v2z', ok: auth.can('canned.manage') },
  { to: '/sites', label: 'Sites & themes', icon: 'M12 3c-4.97 0-9 4.03-9 9 0 2.12.74 4.07 1.97 5.61L4.35 19.4c-.39.39-.39 1.02 0 1.41.39.39 1.02.39 1.41 0l1.9-1.9C9.22 19.58 10.56 20 12 20c4.97 0 9-4.03 9-9s-4.03-9-9-9zm0 15c-3.31 0-6-2.69-6-6s2.69-6 6-6 6 2.69 6 6-2.69 6-6 6z', ok: auth.can('sites.manage') },
  { to: '/teams', label: 'Team & Roles', icon: 'M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z', ok: auth.can('users.manage') || auth.can('dashboard.view') },
  { to: '/preview', label: 'Widget preview', icon: 'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z', ok: auth.can('sites.manage') }
].filter(n => n.ok))

function beep() {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)()
    const o = ctx.createOscillator(), g = ctx.createGain()
    o.connect(g); g.connect(ctx.destination); o.frequency.value = 880; g.gain.value = 0.08
    o.start(); o.stop(ctx.currentTime + 0.18)
  } catch {}
}
const canNotify = ref(false)
async function enableNotify() {
  if ('Notification' in window) { await Notification.requestPermission(); canNotify.value = Notification.permission === 'granted' }
}

const initials = computed(() => {
  const p = auth.profile.value?.pseudo_name || auth.profile.value?.real_name || 'U'
  return p.substring(0, 2).toUpperCase()
})

let channel: any
onMounted(async () => {
  if (!auth.session.value) return
  await staff.load()
  canNotify.value = 'Notification' in window && Notification.permission === 'granted'
  channel = sb.channel('new-tickets')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'tickets' }, (p: any) => {
      beep(); show(`New ticket UAA-${p.new.ticket_no}: ${p.new.subject}`, 'info')
      if (canNotify.value) new Notification('New support ticket', { body: p.new.subject })
    }).subscribe()
})
onBeforeUnmount(() => channel && sb.removeChannel(channel))
</script>

<template>
  <div v-if="route.path === '/login'"><slot /></div>
  <div v-else class="shell">
    <!-- Mobile Sticky Top Header (Visible on <= 860px) -->
    <header class="mobile-topbar">
      <button class="hamburger-btn" aria-label="Toggle Navigation" @click="mobileOpen = !mobileOpen">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>
      </button>
      <div class="mobile-brand">
        <span class="brand-icon">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0-2-.9-2-2V4c0-1.1-.9-2-2-2z"/></svg>
        </span>
        <strong>UAA Support</strong>
      </div>
      <div v-if="auth.profile.value" class="mobile-avatar" :title="auth.profile.value.pseudo_name">
        {{ initials }}
      </div>
    </header>

    <!-- Mobile Navigation Drawer Backdrop -->
    <div v-if="mobileOpen" class="mobile-backdrop" @click="mobileOpen = false" />

    <!-- Sidebar (Desktop fixed, Mobile sliding drawer) -->
    <aside class="side" :class="{ 'mobile-show': mobileOpen }">
      <div class="brand">
        <div style="display:flex;align-items:center;justify-content:space-between">
          <div style="display:flex;align-items:center;gap:.5rem">
            <span class="brand-icon">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0-2-.9-2-2V4c0-1.1-.9-2-2-2z"/></svg>
            </span>
            <span>UAA Support</span>
          </div>
          <!-- Close button on mobile -->
          <button class="mobile-close-btn" aria-label="Close menu" @click="mobileOpen = false">
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>
        <small>Airport assistance desk</small>
      </div>

      <nav>
        <NuxtLink v-for="n in nav" :key="n.to" :to="n.to" @click="mobileOpen = false">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" style="opacity:.8"><path :d="n.icon" /></svg>
          <span>{{ n.label }}</span>
        </NuxtLink>
      </nav>

      <div class="me" v-if="auth.profile.value">
        <div style="display:flex;align-items:center;gap:.65rem">
          <div class="user-avatar-circle">
            {{ initials }}
          </div>
          <div style="min-width:0;overflow:hidden">
            <strong style="display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
              {{ auth.profile.value.pseudo_name }}
            </strong>
            <span style="display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:.75rem">
              {{ auth.profile.value.role }}<template v-if="auth.profile.value.real_name"> · {{ auth.profile.value.real_name }}</template>
            </span>
          </div>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;margin-top:.4rem;padding-top:.4rem;border-top:1px solid rgba(255,255,255,0.08)">
          <button v-if="!canNotify" class="link" @click="enableNotify">Alerts off</button>
          <span v-else style="font-size:.75rem;color:#4ade80">● Live alerts</span>
          <button class="link" style="color:#f87171" @click="auth.logout()">Sign out</button>
        </div>
      </div>
    </aside>

    <!-- Main Content -->
    <main class="main"><slot /></main>
    <div v-if="toast" class="toast" :class="toast.kind" role="status">{{ toast.msg }}</div>
  </div>
</template>

<style scoped>
.brand-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 7px;
  background: var(--accent);
  color: #fff;
  flex-shrink: 0;
}
.user-avatar-circle {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: linear-gradient(135deg, #2563eb, #38bdf8);
  display: grid;
  place-items: center;
  color: #fff;
  font-weight: 700;
  font-size: .8rem;
  flex-shrink: 0;
}

/* Mobile top bar */
.mobile-topbar {
  display: none;
  position: sticky;
  top: 0;
  z-index: 40;
  background: #090d16;
  color: #ffffff;
  padding: 0.75rem 1rem;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid rgba(255,255,255,0.08);
}
.hamburger-btn {
  background: none;
  border: 0;
  color: #ffffff;
  display: grid;
  place-items: center;
  cursor: pointer;
  padding: 4px;
  border-radius: 6px;
}
.hamburger-btn:hover {
  background: rgba(255,255,255,0.1);
}
.mobile-brand {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 1.05rem;
}
.mobile-avatar {
  width: 30px;
  height: 30px;
  border-radius: 50%;
  background: linear-gradient(135deg, #2563eb, #38bdf8);
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 0.75rem;
  font-weight: 700;
}
.mobile-close-btn {
  display: none;
  background: rgba(255,255,255,0.1);
  border: 0;
  color: #ffffff;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  place-items: center;
  cursor: pointer;
}

/* Responsive Breakpoints */
@media (max-width: 860px) {
  .mobile-topbar {
    display: flex;
  }
  .mobile-close-btn {
    display: grid;
  }
  .mobile-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(9, 13, 22, 0.6);
    backdrop-filter: blur(4px);
    z-index: 90;
  }
  .side {
    position: fixed;
    top: 0;
    left: 0;
    bottom: 0;
    width: 270px;
    z-index: 100;
    transform: translateX(-100%);
    transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1);
    box-shadow: 0 0 30px rgba(0,0,0,0.5);
  }
  .side.mobile-show {
    transform: translateX(0);
  }
  .shell {
    display: block;
  }
  .main {
    padding: 1.25rem 1rem 4rem;
  }
}
</style>
