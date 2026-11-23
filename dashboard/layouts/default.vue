<script setup lang="ts">
const auth = useAuth()
const staff = useStaff()
const sb = useSb()
const { toast, show } = useToast()
const route = useRoute()
const alarm = useAlarm()

// Fully reactive top-level computed variables so template re-renders automatically
const activeAlarmTickets = computed(() => alarm.activeAlarmTickets.value)
const isAlarming = computed(() => alarm.isAlarming.value)
const isSnoozed = computed(() => alarm.isSnoozed.value)
const globalAlarmEnabled = computed(() => alarm.globalEnabled.value)
const firstAlarmTicket = computed(() => activeAlarmTickets.value[0] || null)

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
function subscribeNewTickets() {
  if (channel) sb.removeChannel(channel)
  if (!auth.session.value) return
  channel = sb.channel('staff-notifications-sync')
    .on('broadcast', { event: 'ticket_claimed' }, () => {
      alarm.checkUnrespondedTickets()
    })
    .on('broadcast', { event: 'ticket_opened' }, () => {
      alarm.checkUnrespondedTickets()
    })
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'tickets' }, (p: any) => {
      const t = p?.new
      // Only notify if passenger actually filled out the form and it's unclaimed
      const isFilled = t && (t.form_submitted === true || (t.visitor_email && !t.visitor_email.includes('@uaa.chat')))
      if (isFilled && !t.claimed_by && t.status !== 'closed') {
        beep()
        show(`New ticket UAA-${t.ticket_no}: ${t.subject || 'Assistance requested'}`, 'info')
        if (canNotify.value) new Notification('New support ticket', { body: t.subject || 'Passenger submitted assistance form' })
      }
      alarm.checkUnrespondedTickets()
    })
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'tickets' }, (p: any) => {
      const t = p?.new
      // As soon as ONE agent claims it, trigger off alarm and notification for all other users!
      alarm.checkUnrespondedTickets()
      if (t?.claimed_by && t.claimed_by !== auth.session.value?.user?.id) {
        const claimedStaff = staff.label(t.claimed_by)
        show(`Ticket UAA-${t.ticket_no} claimed by ${claimedStaff}`, 'info')
      }
    })
    .subscribe()
}

watch(() => auth.session.value, async (s) => {
  if (s) {
    if (sb.realtime?.setAuth) {
      try { await sb.realtime.setAuth(s.access_token) } catch {}
    }
    await staff.load()
    alarm.start()
    subscribeNewTickets()
  } else {
    alarm.destroy()
    if (channel) {
      sb.removeChannel(channel)
      channel = null
    }
  }
})

onMounted(async () => {
  if (auth.session.value) {
    if (sb.realtime?.setAuth) {
      try { await sb.realtime.setAuth(auth.session.value.access_token) } catch {}
    }
    await staff.load()
    canNotify.value = 'Notification' in window && Notification.permission === 'granted'
    alarm.start()
    subscribeNewTickets()
  }
})
onBeforeUnmount(() => {
  if (channel) sb.removeChannel(channel)
  alarm.destroy()
})
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
      <div class="row" style="gap:.4rem;align-items:center">
        <!-- Quick Alarm Bell on Mobile -->
        <button
          class="alarm-header-btn"
          :class="{ active: isAlarming, muted: !globalAlarmEnabled }"
          @click="alarm.isSettingsOpen.value = true"
          :title="isAlarming ? 'Escalation Alarm Ringing!' : 'Escalation Alarm Settings'"
        >
          {{ isAlarming ? '🚨' : !globalAlarmEnabled ? '🔕' : '🔔' }}
        </button>
        <div v-if="auth.profile.value" class="mobile-avatar" :title="auth.profile.value.pseudo_name">
          {{ initials }}
        </div>
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

      <!-- Quick Escalation Alarm Status & Setting Pill in Sidebar -->
      <div style="padding:0 .75rem;margin-bottom:.5rem">
        <button
          class="alarm-sidebar-card"
          :class="{ ringing: isAlarming, muted: !globalAlarmEnabled }"
          @click="alarm.isSettingsOpen.value = true"
        >
          <div class="alarm-sidebar-left">
            <span class="alarm-pulse-dot" :class="{ ringing: isAlarming, muted: !globalAlarmEnabled }" />
            <div style="text-align:left;line-height:1.2">
              <strong style="font-size:.76rem;display:block">
                {{ isAlarming ? '🚨 ALARM RINGING' : !globalAlarmEnabled ? '🔕 Alarm Muted' : '🔔 Escalation Alarm' }}
              </strong>
              <small style="font-size:.68rem;opacity:.8">
                {{ isAlarming ? `${activeAlarmTickets.length} waiting` : 'Settings & controls' }}
              </small>
            </div>
          </div>
          <span style="font-size:.7rem;opacity:.7">⚙️</span>
        </button>
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

    <!-- Main Content Area with Persistent Escalation Alarm Banner -->
    <main class="main">
      <!-- Background Audio Activation Banner (Appears if user hasn't clicked yet on this tab) -->
      <div v-if="alarm.isAudioSuspended.value" class="audio-unlock-banner" @click="alarm.unlock()">
        <div style="display:flex;align-items:center;gap:.65rem">
          <span style="font-size:1.25rem">🔔</span>
          <div>
            <strong style="display:block;font-size:.85rem;color:#1e40af">Background Audio Alerts</strong>
            <span style="font-size:.78rem;color:#2563eb">Click here or anywhere on the page so alarms can ring when this tab is minimized or in the background.</span>
          </div>
        </div>
        <button class="btn sm" style="background:#2563eb;color:#fff;font-weight:600;padding:4px 12px;border:none;border-radius:6px;cursor:pointer">
          Enable Background Sound
        </button>
      </div>

      <!-- 🚨 Persistent Escalation Alarm Banner (Runs continuously until ticket is opened, claimed, or responded) -->
      <div v-if="activeAlarmTickets.length > 0 && firstAlarmTicket" class="escalation-alert-banner" :class="{ snoozed: isSnoozed }">
        <div class="banner-inner">
          <div class="banner-info">
            <span class="banner-siren-icon">{{ isSnoozed ? '🔕' : '🚨' }}</span>
            <div>
              <div class="row" style="gap:.5rem;align-items:center">
                <strong class="banner-title">
                  {{ firstAlarmTicket.unread_by_staff ? '💬 New Passenger Message' : '🚨 Escalated Ticket Waiting' }}
                  ({{ activeAlarmTickets.length }} ticket{{ activeAlarmTickets.length > 1 ? 's' : '' }})
                </strong>
                <span v-if="isSnoozed" class="chip" style="background:#fef08a;color:#854d0e;font-size:.7rem;padding:1px 6px">
                  Audio Snoozed
                </span>
                <span v-else class="pulse-indicator-badge">ALARM ACTIVE</span>
              </div>
              <div class="banner-desc">
                <strong>UAA-{{ firstAlarmTicket.ticket_no }}</strong>
                ({{ firstAlarmTicket.sites?.name || 'Airport' }})
                · Passenger: <em>{{ firstAlarmTicket.visitor_name || 'Anonymous' }}</em>
                - {{ firstAlarmTicket.subject }}
              </div>
            </div>
          </div>
          <div class="banner-actions">
            <button
              class="btn-alarm primary"
              @click="alarm.claimAndRespond(firstAlarmTicket.id)"
              title="Claim ticket and silence alarm immediately"
            >
              ⚡ Open & Respond
            </button>
            <button
              v-if="!isSnoozed"
              class="btn-alarm secondary"
              @click="alarm.snooze(5)"
              title="Silence alarm sound for 5 minutes"
            >
              🔕 Silence (5m)
            </button>
            <button
              v-else
              class="btn-alarm secondary"
              @click="alarm.unsnooze()"
              title="Resume alarm audio"
            >
              🔔 Resume Audio
            </button>
            <button
              class="btn-alarm icon-only"
              @click="alarm.isSettingsOpen.value = true"
              title="Escalation Alarm & Site Settings"
            >
              ⚙️
            </button>
          </div>
        </div>
      </div>

      <slot />
    </main>

    <!-- 🚨 Escalation Alarm & Sound Settings Modal (Global + Per-Site Controls) -->
    <div v-if="alarm.isSettingsOpen.value" class="alarm-modal-backdrop" @click="alarm.isSettingsOpen.value = false">
      <div class="alarm-modal card" @click.stop>
        <div class="row" style="justify-content:space-between;align-items:center;margin-bottom:1.25rem;border-bottom:1px solid var(--line-subtle);padding-bottom:.85rem">
          <div class="row" style="gap:.6rem;align-items:center">
            <span style="font-size:1.5rem">🚨</span>
            <div>
              <h2 style="margin:0;font-size:1.2rem">Escalation Alarm Settings</h2>
              <p class="sub" style="margin:0;font-size:.82rem">Continuous alert when a passenger escalates from bot to team.</p>
            </div>
          </div>
          <button class="close-modal-btn" aria-label="Close" @click="alarm.isSettingsOpen.value = false">✕</button>
        </div>

        <div class="alarm-settings-body">
          <!-- 1. All Sites Together: Master Toggle -->
          <div class="settings-section-card">
            <div class="row" style="justify-content:space-between;align-items:center">
              <div>
                <strong style="font-size:1rem;display:block">Global Escalation Alarm</strong>
                <p class="sub" style="margin:.2rem 0 0 0;font-size:.82rem">
                  Master switch for all sites together. When active, alarm rings continuously until tickets are claimed or responded to.
                </p>
              </div>
              <label class="switch-control">
                <input
                  type="checkbox"
                  :checked="alarm.globalEnabled.value"
                  @change="alarm.toggleGlobal(!alarm.globalEnabled.value)"
                >
                <span class="switch-slider" />
              </label>
            </div>
          </div>

          <!-- 2. Sound Tone, Volume & Repeat Timing -->
          <div class="settings-section-card">
            <h3 style="font-size:.95rem;margin:0 0 .75rem 0">Audio Alert & Ringtone</h3>
            <div class="grid g2" style="gap:1rem;margin-bottom:1rem">
              <div>
                <label style="font-size:.82rem;font-weight:600;display:block;margin-bottom:.35rem">Alarm Sound Profile</label>
                <select v-model="alarm.soundType.value" @change="alarm.savePreferences()">
                  <option value="tawk">🔔 Tawk.to Chat Ring (Loud Telephone Warble)</option>
                  <option value="siren">🚨 Loud Emergency Siren (Alternating dual-tone)</option>
                  <option value="radar">📡 High Sonar / Radar Sweep</option>
                  <option value="chime">🔔 Loud Boarding Chime (3-tone melodic)</option>
                  <option value="beep">⚡ Double Crisp Beep</option>
                </select>
              </div>
              <div>
                <label style="font-size:.82rem;font-weight:600;display:block;margin-bottom:.35rem">Repeat Frequency / Mode</label>
                <select v-model.number="alarm.intervalSec.value" @change="alarm.savePreferences()">
                  <option :value="0">⚡ Continuous Alarm (Non-stop non-stop loop)</option>
                  <option :value="2">Every 2 seconds (Rapid loop)</option>
                  <option :value="4">Every 4 seconds (Urgent)</option>
                  <option :value="6">Every 6 seconds (Standard)</option>
                  <option :value="10">Every 10 seconds</option>
                  <option :value="15">Every 15 seconds</option>
                </select>
              </div>
            </div>

            <div class="row" style="justify-content:space-between;align-items:center;gap:1rem;flex-wrap:wrap">
              <div class="row" style="gap:.6rem;align-items:center;flex:1;min-width:200px">
                <span style="font-size:.82rem;font-weight:600">Volume</span>
                <input
                  type="range"
                  min="0.1"
                  max="1"
                  step="0.05"
                  v-model.number="alarm.volume.value"
                  @change="alarm.savePreferences()"
                  style="flex:1"
                >
                <span style="font-size:.8rem;font-family:monospace">{{ Math.round(alarm.volume.value * 100) }}%</span>
              </div>
              <button class="btn alt sm" @click="alarm.testSound()" style="white-space:nowrap">
                ▶ Test Sound
              </button>
            </div>
          </div>

          <!-- 3. Individual Site Controls (Per-Site Depending) -->
          <div class="settings-section-card">
            <div class="row" style="justify-content:space-between;align-items:center;margin-bottom:.75rem">
              <div>
                <h3 style="font-size:.95rem;margin:0">Individual Site Controls</h3>
                <p class="sub" style="margin:0;font-size:.8rem">Enable or silence the escalation alarm for specific airport properties.</p>
              </div>
              <div class="row" style="gap:.4rem">
                <button class="btn alt sm" style="font-size:.75rem;padding:3px 8px" @click="alarm.setAllSites(true)">
                  Turn All ON
                </button>
                <button class="btn alt sm" style="font-size:.75rem;padding:3px 8px" @click="alarm.setAllSites(false)">
                  Mute All
                </button>
              </div>
            </div>

            <div v-if="!alarm.sitesList.value.length" class="empty" style="padding:1rem 0">
              Loading sites…
            </div>
            <div v-else class="site-alarm-list">
              <div
                v-for="site in alarm.sitesList.value"
                :key="site.id"
                class="site-alarm-row"
              >
                <div class="row" style="gap:.5rem;align-items:center">
                  <span style="font-size:.9rem">{{ site.escalation_alarm_enabled ? '🔔' : '🔕' }}</span>
                  <strong>{{ site.name }}</strong>
                </div>
                <label class="switch-control sm">
                  <input
                    type="checkbox"
                    :checked="site.escalation_alarm_enabled"
                    @change="alarm.toggleSite(site.id, !site.escalation_alarm_enabled)"
                  >
                  <span class="switch-slider" />
                </label>
              </div>
            </div>
          </div>
        </div>

        <div class="row" style="justify-content:flex-end;margin-top:1.25rem">
          <button class="btn amber" @click="alarm.isSettingsOpen.value = false">
            Done & Save
          </button>
        </div>
      </div>
    </div>

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

/* Sidebar Alarm Card */
.alarm-sidebar-card {
  width: 100%;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 8px;
  padding: 8px 10px;
  color: #fff;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: space-between;
  transition: all 0.2s ease;
}
.alarm-sidebar-card:hover {
  background: rgba(255, 255, 255, 0.09);
  border-color: rgba(255, 255, 255, 0.2);
}
.alarm-sidebar-card.ringing {
  background: rgba(239, 68, 68, 0.2);
  border-color: rgba(239, 68, 68, 0.6);
  animation: pulseRinging 1.5s infinite;
}
.alarm-sidebar-card.muted {
  opacity: 0.6;
}
.alarm-sidebar-left {
  display: flex;
  align-items: center;
  gap: 8px;
}
.alarm-pulse-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #22c55e;
  box-shadow: 0 0 0 2px rgba(34, 197, 94, 0.3);
}
.alarm-pulse-dot.ringing {
  background: #ef4444;
  box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.5);
  animation: blink 0.8s infinite;
}
.alarm-pulse-dot.muted {
  background: #94a3b8;
  box-shadow: none;
}
@keyframes pulseRinging {
  0%, 100% { border-color: rgba(239, 68, 68, 0.4); }
  50% { border-color: rgba(239, 68, 68, 1); box-shadow: 0 0 12px rgba(239, 68, 68, 0.4); }
}
@keyframes blink {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.4; transform: scale(0.85); }
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
.alarm-header-btn {
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 6px;
  padding: 4px 8px;
  font-size: 1rem;
  cursor: pointer;
}
.alarm-header-btn.active {
  background: #ef4444;
  animation: blink 0.8s infinite;
}

/* Persistent Escalation Alert Banner */
.escalation-alert-banner {
  background: linear-gradient(135deg, #7f1d1d, #991b1b);
  border: 1px solid #ef4444;
  color: #ffffff;
  border-radius: 10px;
  padding: 12px 16px;
  margin-bottom: 1.25rem;
  box-shadow: 0 10px 25px -5px rgba(220, 38, 38, 0.4);
  animation: alertPulse 1.8s infinite;
}
.escalation-alert-banner.snoozed {
  background: linear-gradient(135deg, #713f12, #854d0e);
  border-color: #eab308;
  animation: none;
  box-shadow: 0 4px 15px -3px rgba(234, 179, 8, 0.2);
}
@keyframes alertPulse {
  0%, 100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.4); }
  50% { box-shadow: 0 0 0 8px rgba(239, 68, 68, 0); }
}
.audio-unlock-banner {
  background: #eff6ff;
  border: 1px solid #bfdbfe;
  border-radius: 8px;
  padding: .75rem 1.25rem;
  margin-bottom: 1.25rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  cursor: pointer;
  transition: background .15s ease;
}
.audio-unlock-banner:hover {
  background: #dbeafe;
}
.banner-inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}
.banner-info {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}
.banner-siren-icon {
  font-size: 1.8rem;
  flex-shrink: 0;
  animation: sirenShake 0.6s infinite alternate ease-in-out;
}
.snoozed .banner-siren-icon {
  animation: none;
}
@keyframes sirenShake {
  0% { transform: rotate(-8deg) scale(1); }
  100% { transform: rotate(8deg) scale(1.1); }
}
.banner-title {
  font-size: 1.05rem;
  letter-spacing: -0.01em;
}
.banner-desc {
  font-size: 0.85rem;
  opacity: 0.95;
  margin-top: 2px;
}
.pulse-indicator-badge {
  background: #ffffff;
  color: #991b1b;
  font-size: 0.68rem;
  font-weight: 800;
  padding: 2px 7px;
  border-radius: 99px;
  letter-spacing: 0.04em;
  display: inline-block;
}
.banner-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.btn-alarm {
  border: 0;
  border-radius: 6px;
  font-weight: 600;
  font-size: 0.85rem;
  cursor: pointer;
  padding: 7px 13px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  transition: transform 0.15s ease, opacity 0.15s ease;
}
.btn-alarm:active {
  transform: scale(0.97);
}
.btn-alarm.primary {
  background: #ffffff;
  color: #991b1b;
  font-weight: 700;
  box-shadow: 0 2px 6px rgba(0,0,0,0.2);
}
.btn-alarm.primary:hover {
  background: #f8fafc;
}
.btn-alarm.secondary {
  background: rgba(255, 255, 255, 0.15);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.25);
}
.btn-alarm.secondary:hover {
  background: rgba(255, 255, 255, 0.25);
}
.btn-alarm.icon-only {
  background: rgba(255, 255, 255, 0.15);
  color: #ffffff;
  padding: 7px 10px;
}

/* Alarm Modal */
.alarm-modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(9, 13, 22, 0.65);
  backdrop-filter: blur(4px);
  z-index: 200;
  display: grid;
  place-items: center;
  padding: 1rem;
}
.alarm-modal {
  width: 100%;
  max-width: 620px;
  max-height: 90vh;
  overflow-y: auto;
  border-radius: 12px;
  background: #ffffff;
  color: var(--t);
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
}
.close-modal-btn {
  background: none;
  border: 0;
  font-size: 1.2rem;
  cursor: pointer;
  color: var(--muted);
  padding: 4px;
}
.alarm-settings-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.settings-section-card {
  background: var(--bg-alt, #f8fafc);
  border: 1px solid var(--line-subtle, #e2e8f0);
  border-radius: 8px;
  padding: 14px;
}

/* Switch Controls */
.switch-control {
  position: relative;
  display: inline-block;
  width: 44px;
  height: 24px;
  flex-shrink: 0;
}
.switch-control.sm {
  width: 36px;
  height: 20px;
}
.switch-control input {
  opacity: 0;
  width: 0;
  height: 0;
}
.switch-slider {
  position: absolute;
  cursor: pointer;
  inset: 0;
  background-color: #cbd5e1;
  transition: .25s ease;
  border-radius: 34px;
}
.switch-slider:before {
  position: absolute;
  content: "";
  height: 18px;
  width: 18px;
  left: 3px;
  bottom: 3px;
  background-color: white;
  transition: .25s ease;
  border-radius: 50%;
  box-shadow: 0 1px 3px rgba(0,0,0,0.2);
}
.switch-control.sm .switch-slider:before {
  height: 14px;
  width: 14px;
}
input:checked + .switch-slider {
  background-color: #22c55e;
}
input:checked + .switch-slider:before {
  transform: translateX(20px);
}
.switch-control.sm input:checked + .switch-slider:before {
  transform: translateX(16px);
}

.site-alarm-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-height: 220px;
  overflow-y: auto;
  padding-right: 4px;
}
.site-alarm-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 10px;
  background: #ffffff;
  border: 1px solid var(--line-subtle, #e2e8f0);
  border-radius: 6px;
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
    padding: 1rem 0.85rem 4rem;
  }
}
</style>

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
