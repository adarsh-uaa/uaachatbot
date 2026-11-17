// Composable for persistent Escalation Alarm and Site-specific controls
// Keeps running until an escalated ticket is responded to / claimed by staff.
// Supports continuous ringing, customizable intervals, Tawk.to phone ring tone, and schema-cache fallback.

export interface AlarmSite {
  id: string
  name: string
  escalation_alarm_enabled: boolean
}

export type AlarmSoundType = 'tawk' | 'siren' | 'radar' | 'chime' | 'beep'

const globalEnabled = ref(true)
const soundType = ref<AlarmSoundType>('tawk')
const intervalSec = ref(0) // 0 = continuous non-stop ringing
const volume = ref(0.95)
const snoozedUntil = ref(0)
const unrespondedTickets = ref<any[]>([])
const sitesList = ref<AlarmSite[]>([])
const isSettingsOpen = ref(false)
const isAudioSuspended = ref(false)

let audioCtx: AudioContext | null = null
let alarmTimer: any = null
let pollTimer: any = null
let sbChannel: any = null
let localBc: BroadcastChannel | null = null

const SHARED_ALARM_CHANNEL = 'staff-alarm-sync'

function getAudioContext(): AudioContext | null {
  if (typeof window === 'undefined') return null
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext
    if (AudioContextClass) audioCtx = new AudioContextClass()
  }
  if (audioCtx && audioCtx.state === 'suspended') {
    audioCtx.resume().catch(() => {})
  }
  return audioCtx
}

// Synthesize loud, clear alert tones with Web Audio API
async function playTone(type: AlarmSoundType, vol: number) {
  try {
    const ctx = getAudioContext()
    if (!ctx) return
    if (ctx.state === 'suspended') {
      await ctx.resume().catch(() => {})
    }

    const now = ctx.currentTime
    const gainNode = ctx.createGain()
    const masterVol = Math.max(0.1, Math.min(1.0, vol))
    gainNode.gain.setValueAtTime(masterVol, now)
    gainNode.connect(ctx.destination)

    if (type === 'tawk') {
      // 🔔 Tawk.to Style Incoming Chat Telephone Ring
      // Dual-burst rapid 24Hz warble ring (alternating ~920Hz and ~1180Hz)
      const bursts = [
        { start: now, duration: 0.28 },
        { start: now + 0.35, duration: 0.36 }
      ]

      bursts.forEach(({ start, duration }) => {
        const osc = ctx.createOscillator()
        const lfo = ctx.createOscillator()
        const lfoGain = ctx.createGain()
        const burstGain = ctx.createGain()

        osc.type = 'sawtooth'
        osc.frequency.setValueAtTime(1050, start)

        // 24Hz square wave frequency modulation (phone warble)
        lfo.type = 'square'
        lfo.frequency.setValueAtTime(24, start)
        lfoGain.gain.setValueAtTime(130, start)

        lfo.connect(lfoGain)
        lfoGain.connect(osc.frequency)

        // Full punchy envelope
        burstGain.gain.setValueAtTime(masterVol * 0.95, start)
        burstGain.gain.setValueAtTime(masterVol * 0.95, start + duration - 0.03)
        burstGain.gain.linearRampToValueAtTime(0.001, start + duration)

        osc.connect(burstGain)
        burstGain.connect(gainNode)

        lfo.start(start)
        osc.start(start)
        lfo.stop(start + duration)
        osc.stop(start + duration)
      })
    } else if (type === 'siren') {
      // 🚨 High-energy alternating two-tone siren
      const osc = ctx.createOscillator()
      osc.type = 'sawtooth'
      osc.frequency.setValueAtTime(960, now)
      osc.frequency.setValueAtTime(720, now + 0.16)
      osc.frequency.setValueAtTime(960, now + 0.32)
      osc.frequency.setValueAtTime(720, now + 0.48)
      osc.connect(gainNode)

      gainNode.gain.setValueAtTime(masterVol * 0.9, now)
      gainNode.gain.linearRampToValueAtTime(0.001, now + 0.65)

      osc.start(now)
      osc.stop(now + 0.66)
    } else if (type === 'radar') {
      // 📡 Rapid ascending radar pulse (punchy sonar sweep)
      const osc = ctx.createOscillator()
      osc.type = 'sine'
      osc.frequency.setValueAtTime(650, now)
      osc.frequency.exponentialRampToValueAtTime(1850, now + 0.32)
      osc.connect(gainNode)

      gainNode.gain.setValueAtTime(masterVol * 0.95, now)
      gainNode.gain.exponentialRampToValueAtTime(0.001, now + 0.38)

      osc.start(now)
      osc.stop(now + 0.4)
    } else if (type === 'chime') {
      // 🔔 Loud Airport Boarding / Arrival Chime (3-tone chord: C5 -> E5 -> G5)
      const freqs = [523.25, 659.25, 783.99]
      freqs.forEach((freq, idx) => {
        const osc = ctx.createOscillator()
        const noteGain = ctx.createGain()
        osc.type = 'sine'
        osc.frequency.value = freq

        const startAt = now + idx * 0.13
        noteGain.gain.setValueAtTime(masterVol * 0.85, startAt)
        noteGain.gain.exponentialRampToValueAtTime(0.001, startAt + 0.5)

        osc.connect(noteGain)
        noteGain.connect(gainNode)

        osc.start(startAt)
        osc.stop(startAt + 0.52)
      })
    } else {
      // ⚡ Double Crisp Beep
      [0, 0.12].forEach((offset) => {
        const osc = ctx.createOscillator()
        osc.type = 'square'
        osc.frequency.value = 920

        const startAt = now + offset
        const noteGain = ctx.createGain()
        noteGain.gain.setValueAtTime(masterVol * 0.85, startAt)
        noteGain.gain.exponentialRampToValueAtTime(0.001, startAt + 0.08)

        osc.connect(noteGain)
        noteGain.connect(gainNode)

        osc.start(startAt)
        osc.stop(startAt + 0.09)
      })
    }
  } catch {}
}

export function useAlarm() {
  const sb = useSb()
  const { show } = useToast()

  // Load preferences from localStorage on client
  function initPreferences() {
    if (typeof window === 'undefined') return
    const g = localStorage.getItem('uaa:alarm_global_enabled')
    if (g !== null) globalEnabled.value = g === 'true'

    const s = localStorage.getItem('uaa:alarm_sound')
    if (s && ['tawk', 'siren', 'radar', 'chime', 'beep'].includes(s)) {
      soundType.value = s as AlarmSoundType
    }

    const i = localStorage.getItem('uaa:alarm_interval')
    if (i !== null && !isNaN(Number(i))) intervalSec.value = Number(i)

    const v = localStorage.getItem('uaa:alarm_volume')
    if (v && !isNaN(Number(v))) volume.value = Number(v)

    // Unlock Web Audio context on user interactions with window
    const unlock = () => {
      const ctx = getAudioContext()
      if (ctx && ctx.state === 'suspended') {
        ctx.resume().then(() => {
          isAudioSuspended.value = false
        }).catch(() => {})
      } else if (ctx) {
        isAudioSuspended.value = false
      }
    }
    window.addEventListener('click', unlock, { passive: true })
    window.addEventListener('keydown', unlock, { passive: true })
    window.addEventListener('focus', unlock, { passive: true })
    window.addEventListener('pointerdown', unlock, { passive: true })
    window.addEventListener('touchstart', unlock, { passive: true })

    // Setup local BroadcastChannel for 0ms cross-tab sync in same browser
    try {
      if ('BroadcastChannel' in window && !localBc) {
        localBc = new BroadcastChannel('uaa_staff_alarm_sync')
        localBc.onmessage = (ev) => {
          if (ev.data?.event === 'ticket_claimed') {
            const id = ev.data.ticketId
            if (id) {
              unrespondedTickets.value = unrespondedTickets.value.filter(t => t.id !== id)
              evaluateAlarmLoop()
            }
            checkUnrespondedTickets()
          } else if (ev.data?.event === 'ticket_escalated') {
            checkUnrespondedTickets()
          }
        }
      }
    } catch {}

    // Cross-tab storage event backup (fires across tabs on same origin when localStorage is written)
    window.addEventListener('storage', (e) => {
      if ((e.key === 'uaa:claimed_ticket_id' || e.key === 'uaa:opened_ticket_id') && e.newValue) {
        const id = e.newValue.split(':')[0]
        if (id) {
          unrespondedTickets.value = unrespondedTickets.value.filter(t => t.id !== id)
          evaluateAlarmLoop()
        }
        checkUnrespondedTickets()
      }
    })

    window.addEventListener('focus', () => {
      unlock()
      checkUnrespondedTickets()
    })

    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) {
          unlock()
          checkUnrespondedTickets()
        }
      }, { passive: true })
    }
  }

  function savePreferences() {
    if (typeof window === 'undefined') return
    localStorage.setItem('uaa:alarm_global_enabled', String(globalEnabled.value))
    localStorage.setItem('uaa:alarm_sound', soundType.value)
    localStorage.setItem('uaa:alarm_interval', String(intervalSec.value))
    localStorage.setItem('uaa:alarm_volume', String(volume.value))
    if (alarmTimer) {
      clearInterval(alarmTimer)
      alarmTimer = null
      evaluateAlarmLoop()
    }
  }

  // Load all sites and their individual alarm settings (with self-healing fallback)
  async function loadSites() {
    let data: any[] | null = null

    // Attempt 1: Query with escalation_alarm_enabled column
    try {
      const res = await sb.from('sites').select('id, name, escalation_alarm_enabled, theme').order('name')
      if (!res.error && res.data) data = res.data
    } catch {}

    // Attempt 2: Fallback if column not yet in PostgREST schema cache
    if (!data) {
      const res = await sb.from('sites').select('id, name, theme').order('name')
      data = res.data || []
    }

    sitesList.value = (data || []).map((d: any) => {
      // Priority: localStorage > column > theme config > default true
      let isEnabled = true
      if (typeof window !== 'undefined') {
        const local = localStorage.getItem('uaa:site_alarm:' + d.id)
        if (local !== null) isEnabled = local === 'true'
        else if (d.escalation_alarm_enabled !== undefined) isEnabled = d.escalation_alarm_enabled !== false
        else if (d.theme?.escalation_alarm_enabled !== undefined) isEnabled = d.theme.escalation_alarm_enabled !== false
      }
      return {
        id: d.id,
        name: d.name,
        escalation_alarm_enabled: isEnabled
      }
    })
  }

  // Desktop browser notification
  function notifyBrowser(title: string, bodyText: string) {
    if (typeof window === 'undefined' || !('Notification' in window)) return
    try {
      if (Notification.permission === 'granted') {
        new Notification(title, { body: bodyText, icon: '/favicon.ico' })
      } else if (Notification.permission !== 'denied') {
        Notification.requestPermission()
      }
    } catch {}
  }

  function isFormFilled(t: any): boolean {
    if (!t) return false
    // Explicit database boolean flag
    if (t.form_submitted === true) return true
    // Real email provided (not an anonymous placeholder)
    if (t.visitor_email && !t.visitor_email.includes('@uaa.chat') && !t.visitor_email.includes('anonymous')) {
      return true
    }
    // Real phone number provided
    if (t.visitor_phone && String(t.visitor_phone).trim().length > 0) {
      return true
    }
    return false
  }

  // Query tickets waiting for staff response:
  // - status !== 'closed'
  // - claimed_by is null (unclaimed: nobody has responded/claimed it yet)
  // - unread_by_staff === true (nobody has OPENED or attended the ticket yet)
  // - form_submitted === true (ONLY send alarm if passenger filled out the form)
  // As soon as ANY staff member opens the ticket or claims it, unread_by_staff becomes false
  // or claimed_by is set, which immediately silences the alarm and removes the banner for ALL devices!
  async function checkUnrespondedTickets() {
    let list: any[] = []
    let queryFailed = false
    try {
      const res = await sb
        .from('tickets')
        .select('id, ticket_no, visitor_name, visitor_email, visitor_phone, form_submitted, subject, status, site_id, updated_at, created_at, claimed_by, unread_by_staff, first_response_at, sites(name, escalation_alarm_enabled, theme)')
        .neq('status', 'closed')
        .is('claimed_by', null)
        .eq('unread_by_staff', true)
        .order('updated_at', { ascending: false })

      if (res.error) {
        queryFailed = true
      } else {
        list = res.data || []
      }
    } catch {
      queryFailed = true
    }

    // Fallback if escalation_alarm_enabled or form_submitted column is not yet in PostgREST schema cache
    if (queryFailed) {
      try {
        const resFallback = await sb
          .from('tickets')
          .select('id, ticket_no, visitor_name, visitor_email, visitor_phone, subject, status, site_id, updated_at, created_at, claimed_by, unread_by_staff, first_response_at, sites(name, theme)')
          .neq('status', 'closed')
          .is('claimed_by', null)
          .eq('unread_by_staff', true)
          .order('updated_at', { ascending: false })

        if (!resFallback.error && resFallback.data) list = resFallback.data
      } catch {}
    }

    // STRICT BUSINESS RULE:
    // 1. Only send alarm IF visitor has filled out the contact form (form_submitted or real email/phone).
    // 2. If ANY staff member opens the ticket (unread_by_staff = false) or claims it (claimed_by is set),
    //    it MUST NOT show the warning/alarm on ANY other device or account!
    unrespondedTickets.value = (list || []).filter((t: any) => {
      if (t.status === 'closed') return false
      if (t.claimed_by) return false
      if (t.unread_by_staff === false) return false
      if (!isFormFilled(t)) return false
      return true
    })
    evaluateAlarmLoop()
  }

  // Filter tickets whose individual site allows alarms
  const activeAlarmTickets = computed(() => {
    if (!globalEnabled.value) return []
    return unrespondedTickets.value.filter((t: any) => {
      const siteConfig = sitesList.value.find(s => s.id === t.site_id)
      if (siteConfig && siteConfig.escalation_alarm_enabled !== undefined) {
        return siteConfig.escalation_alarm_enabled !== false
      }
      if (typeof window !== 'undefined') {
        const local = localStorage.getItem('uaa:site_alarm:' + t.site_id)
        if (local !== null) return local === 'true'
      }
      if (t.sites?.escalation_alarm_enabled !== undefined) return t.sites.escalation_alarm_enabled !== false
      if (t.sites?.theme?.escalation_alarm_enabled !== undefined) return t.sites.theme.escalation_alarm_enabled !== false
      return true
    })
  })

  const isSnoozed = computed(() => Date.now() < snoozedUntil.value)
  const isAlarming = computed(() => activeAlarmTickets.value.length > 0 && !isSnoozed.value)

  function evaluateAlarmLoop() {
    if (isAlarming.value) {
      if (!alarmTimer) {
        // Play sound immediately
        playTone(soundType.value, volume.value)
        // Interval: 0 = continuous non-stop ringing (~800ms repeat)
        const delayMs = intervalSec.value === 0 ? 800 : Math.max(1, intervalSec.value) * 1000
        alarmTimer = setInterval(() => {
          if (isAlarming.value) {
            playTone(soundType.value, volume.value)
          } else {
            stopAlarm()
          }
        }, delayMs)
      }
    } else {
      stopAlarm()
    }
  }

  function stopAlarm() {
    if (alarmTimer) {
      clearInterval(alarmTimer)
      alarmTimer = null
    }
  }

  function snooze(minutes: number = 5) {
    snoozedUntil.value = Date.now() + minutes * 60 * 1000
    stopAlarm()
    show(`Alarm snoozed for ${minutes} minutes`, 'info')
  }

  function unsnooze() {
    snoozedUntil.value = 0
    evaluateAlarmLoop()
    show('Alarm resumed', 'ok')
  }

  function testSound(type?: AlarmSoundType) {
    const t = type || soundType.value
    playTone(t, volume.value)
  }

  // Global toggle (all sites together)
  function toggleGlobal(val?: boolean) {
    globalEnabled.value = val !== undefined ? val : !globalEnabled.value
    savePreferences()
    if (!globalEnabled.value) stopAlarm()
    else evaluateAlarmLoop()
    show(`Escalation alarm ${globalEnabled.value ? 'enabled' : 'disabled'} for all sites`, 'info')
  }

  // Individual Site control (Self-healing fallback if column not yet in schema cache)
  async function toggleSite(siteId: string, enabled: boolean) {
    // 1. Optimistic local update & localStorage persistence
    const s = sitesList.value.find(x => x.id === siteId)
    if (s) s.escalation_alarm_enabled = enabled
    if (typeof window !== 'undefined') {
      localStorage.setItem('uaa:site_alarm:' + siteId, String(enabled))
    }

    // 2. Persist to Supabase
    try {
      const { error } = await sb.from('sites').update({ escalation_alarm_enabled: enabled }).eq('id', siteId)
      if (error) {
        const msg = String(error.message || '')
        if (msg.includes('column') || msg.includes('schema cache')) {
          // Fallback: save inside theme config so it still persists in DB without failing!
          const { data: cur } = await sb.from('sites').select('theme').eq('id', siteId).single()
          await sb.from('sites').update({ theme: { ...(cur?.theme || {}), escalation_alarm_enabled: enabled } }).eq('id', siteId)
          show(`Alarm ${enabled ? 'enabled' : 'disabled'} for ${s?.name || 'site'} (saved to config)`, 'ok')
        } else {
          show('Failed to update: ' + error.message, 'err')
        }
      } else {
        show(`Alarm ${enabled ? 'enabled' : 'disabled'} for ${s?.name || 'site'}`, 'ok')
      }
    } catch {
      show(`Alarm ${enabled ? 'enabled' : 'disabled'} for ${s?.name || 'site'}`, 'ok')
    }

    evaluateAlarmLoop()
  }

  // Bulk update (All sites together)
  async function setAllSites(enabled: boolean) {
    // 1. Update in-memory state & localStorage
    sitesList.value.forEach(s => {
      s.escalation_alarm_enabled = enabled
      if (typeof window !== 'undefined') {
        localStorage.setItem('uaa:site_alarm:' + s.id, String(enabled))
      }
    })

    // 2. Try updating column in Supabase
    try {
      const { error } = await sb.from('sites').update({ escalation_alarm_enabled: enabled }).neq('id', '00000000-0000-0000-0000-000000000000')
      if (error) {
        const msg = String(error.message || '')
        if (msg.includes('column') || msg.includes('schema cache')) {
          // Schema cache notice: kept locally and ready to persist once migration is run
          show(`All sites ${enabled ? 'enabled' : 'muted'}! (Run migration 011 in Supabase SQL Editor to sync DB column)`, 'info')
        } else {
          show('Failed to update all sites: ' + error.message, 'err')
        }
      } else {
        show(`Escalation alarm ${enabled ? 'enabled' : 'disabled'} on all ${sitesList.value.length} sites`, 'ok')
      }
    } catch {
      show(`All sites ${enabled ? 'enabled' : 'muted'}!`, 'ok')
    }

    evaluateAlarmLoop()
  }

  // Broadcast that a ticket was OPENED / viewed by a staff member
  // (Immediately silences alarm & removes warning banner on all other devices/accounts)
  function broadcastTicketOpened(ticketId: string) {
    if (!ticketId) return
    // 1. Immediately remove from local list & silence alarm locally
    unrespondedTickets.value = unrespondedTickets.value.filter(t => t.id !== ticketId)
    evaluateAlarmLoop()

    // 2. Cross-tab localStorage trigger (0ms latency, zero network required)
    if (typeof window !== 'undefined') {
      try {
        localStorage.setItem('uaa:opened_ticket_id', `${ticketId}:${Date.now()}`)
      } catch {}
    }

    // 3. Browser BroadcastChannel (0ms latency across tabs)
    try {
      localBc?.postMessage({ event: 'ticket_opened', ticketId })
    } catch {}

    // 4. Supabase Realtime broadcast across all staff members on network
    try {
      if (sbChannel) {
        sbChannel.send({
          type: 'broadcast',
          event: 'ticket_opened',
          payload: { ticketId }
        }).catch(() => {})
      }
    } catch {}
  }

  function broadcastTicketClaimed(ticketId: string) {
    if (!ticketId) return
    broadcastTicketOpened(ticketId)

    if (typeof window !== 'undefined') {
      try {
        localStorage.setItem('uaa:claimed_ticket_id', `${ticketId}:${Date.now()}`)
      } catch {}
    }

    try {
      localBc?.postMessage({ event: 'ticket_claimed', ticketId })
    } catch {}

    try {
      if (sbChannel) {
        sbChannel.send({
          type: 'broadcast',
          event: 'ticket_claimed',
          payload: { ticketId }
        }).catch(() => {})
      }
    } catch {}
  }

  // One-click claim and respond (immediately silences the alarm for this ticket)
  async function claimAndRespond(ticketId: string) {
    // 1. Immediately stop alarm sound and dismiss banner locally
    unrespondedTickets.value = unrespondedTickets.value.filter(t => t.id !== ticketId)
    evaluateAlarmLoop()

    // 2. Instantly notify all peer tabs and staff screens via Broadcast to silence their alarms too
    broadcastTicketOpened(ticketId)
    broadcastTicketClaimed(ticketId)

    // 3. Perform database claim
    const { error } = await sb.rpc('claim_ticket', { p_ticket: ticketId })
    if (error) {
      const msg = String(error.message || '').toLowerCase()
      if (msg.includes('already claimed') || msg.includes('closed')) {
        show('Ticket was already claimed by a teammate. Opening ticket…', 'info')
      } else {
        show(error.message, 'err')
      }
    } else {
      show('Ticket claimed! Escalation alarm cleared.', 'ok')
    }

    // 4. Re-sync queue
    await checkUnrespondedTickets()

    // 5. ALWAYS navigate to the ticket page so the staff member can see it and never gets stuck
    navigateTo('/tickets/' + ticketId)
  }

  function start() {
    initPreferences()
    loadSites()
    checkUnrespondedTickets()

    // 1. Ensure token is set on Realtime socket for current user
    const token = auth.session.value?.access_token
    if (token && sb.realtime?.setAuth) {
      try { sb.realtime.setAuth(token) } catch {}
    }

    // 2. 2-second backup polling loop ensures alarms ring across all staff tabs even if background WebSockets sleep
    if (!pollTimer) {
      pollTimer = setInterval(() => {
        checkUnrespondedTickets()
      }, 2000)
    }

    // 3. Reset channel so it connects with the authenticated session on shared topic
    if (sbChannel) {
      sb.removeChannel(sbChannel)
      sbChannel = null
    }

    const channelTopic = SHARED_ALARM_CHANNEL
    sbChannel = sb.channel(channelTopic)
      // Broadcast event: instantly received when any staff member claims or OPENS a ticket
      .on('broadcast', { event: 'ticket_claimed' }, (payload: any) => {
        const id = payload?.payload?.ticketId
        if (id) {
          unrespondedTickets.value = unrespondedTickets.value.filter(t => t.id !== id)
          evaluateAlarmLoop()
        }
        checkUnrespondedTickets()
      })
      .on('broadcast', { event: 'ticket_opened' }, (payload: any) => {
        const id = payload?.payload?.ticketId
        if (id) {
          unrespondedTickets.value = unrespondedTickets.value.filter(t => t.id !== id)
          evaluateAlarmLoop()
        }
        checkUnrespondedTickets()
      })
      .on('broadcast', { event: 'ticket_escalated' }, async () => {
        await checkUnrespondedTickets()
      })
      // 1. Sound alarm whenever visitor sends any message on an unclaimed ticket
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'ticket_messages' }, async (payload: any) => {
        const msg = payload?.new
        if (msg && msg.sender === 'visitor') {
          await checkUnrespondedTickets()
          if (activeAlarmTickets.value.length > 0) {
            playTone(soundType.value, volume.value)
            notifyBrowser('UAA Airport Support', `New message: ${msg.body?.slice(0, 75) || 'Passenger replied'}`)
            show(`💬 Passenger messaged: "${msg.body?.slice(0, 50)}${msg.body?.length > 50 ? '…' : ''}"`, 'info')
          }
        }
      })
      // 2. Sound alarm when form-submitted ticket is created/updated and unclaimed;
      //    And immediately silence alarm for all users if someone opens, claims, or closes it!
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' }, async (payload: any) => {
        const t = payload?.new
        // If ticket was claimed, opened/read (unread_by_staff = false), or closed:
        // immediately re-evaluate and silence alarm for all devices/accounts!
        if (t && (t.claimed_by || t.status === 'closed' || t.unread_by_staff === false)) {
          if (t.id) {
            unrespondedTickets.value = unrespondedTickets.value.filter(x => x.id !== t.id)
            evaluateAlarmLoop()
          }
          await checkUnrespondedTickets()
          return
        }
        // Only sound alarm if the visitor has actually submitted the form AND ticket is unread!
        if (t && !t.claimed_by && t.status !== 'closed' && t.unread_by_staff === true && isFormFilled(t)) {
          playTone(soundType.value, volume.value)
        }
        await checkUnrespondedTickets()
      })
      // 3. Site settings changes
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sites' }, () => {
        loadSites()
      })
      .subscribe((status: string) => {
        if (status === 'SUBSCRIBED') {
          checkUnrespondedTickets()
        }
      })
  }

  function destroy() {
    stopAlarm()
    if (pollTimer) {
      clearInterval(pollTimer)
      pollTimer = null
    }
    if (sbChannel) {
      sb.removeChannel(sbChannel)
      sbChannel = null
    }
    if (localBc) {
      try { localBc.close() } catch {}
      localBc = null
    }
  }

  return {
    globalEnabled,
    soundType,
    intervalSec,
    volume,
    snoozedUntil,
    isSnoozed,
    isAlarming,
    isAudioSuspended,
    unrespondedTickets,
    activeAlarmTickets,
    sitesList,
    isSettingsOpen,
    start,
    destroy,
    checkUnrespondedTickets,
    loadSites,
    playTone,
    testSound,
    snooze,
    unsnooze,
    toggleGlobal,
    toggleSite,
    setAllSites,
    claimAndRespond,
    broadcastTicketOpened,
    broadcastTicketClaimed,
    savePreferences
  }
}
