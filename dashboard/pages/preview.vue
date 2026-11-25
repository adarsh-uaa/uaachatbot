<script setup lang="ts">
definePageMeta({ perm: 'sites.manage' })
const sb = useSb(), cfg = useRuntimeConfig().public
const sites = ref<any[]>([]), key = ref(''), mounted = ref(false)
onMounted(async () => {
  sites.value = (await sb.from('sites').select('name,site_key')).data || []
  key.value = sites.value[0]?.site_key || ''
})
function mount() {
  document.querySelector('uaa-chat')?.remove()
  document.getElementById('uaa-script')?.remove()
  const s = document.createElement('script')
  s.id = 'uaa-script'
  s.src = '/uaa-widget.js?' + Date.now()
  s.dataset.siteKey = key.value
  s.dataset.apiUrl = cfg.supabaseUrl as string
  s.dataset.apiKey = cfg.supabaseKey as string
  s.dataset.botEnabled = 'true'
  document.body.appendChild(s)
  mounted.value = true
}
onBeforeUnmount(() => {
  document.querySelector('uaa-chat')?.remove()
  document.getElementById('uaa-script')?.remove()
})
</script>
<template>
  <div class="row" style="justify-content:space-between;margin-bottom:1rem">
    <div>
      <h1>Live Widget Playground</h1>
      <p class="sub" style="margin:0">Test the real embedded chat widget running live against your Supabase backend.</p>
    </div>
  </div>

  <div class="card" style="margin-bottom:1.5rem">
    <div class="row" style="gap:.75rem">
      <label style="margin:0">Select Website Property:</label>
      <select v-model="key" style="width:auto;min-width:200px">
        <option v-for="s in sites" :key="s.site_key" :value="s.site_key">{{ s.name }}</option>
      </select>
      <button class="btn amber" @click="mount">
        {{ mounted ? 'Reload Widget' : 'Launch Widget on Screen' }}
      </button>
    </div>
  </div>

  <!-- Mock Browser Window Simulation -->
  <div class="card" style="padding:0;overflow:hidden;border-radius:12px;border:1px solid var(--line);box-shadow:var(--shadow-lg)">
    <!-- Browser Title Bar -->
    <div style="background:#f1f5f9;border-bottom:1px solid var(--line);padding:10px 14px;display:flex;align-items:center;gap:8px">
      <span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#ef4444" />
      <span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#f59e0b" />
      <span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#10b981" />
      <span style="background:#ffffff;border:1px solid var(--line);border-radius:6px;padding:3px 14px;font-size:12px;color:var(--muted);margin-left:10px;flex:1;max-width:380px">
        https://uk-airport-assistance.com
      </span>
    </div>

    <!-- Mock Website Content -->
    <div style="padding:3rem 2rem;background:#ffffff;min-height:360px">
      <div style="max-width:680px;margin:0 auto;text-align:center">
        <span class="chip role" style="margin-bottom:1rem">UK Airport Assistance & Special Services</span>
        <h2 style="font-size:2rem;letter-spacing:-0.03em;margin-bottom:.75rem">Special Assistance & Flight Support</h2>
        <p class="sub" style="font-size:1rem;margin-bottom:1.5rem">
          Dedicated wheelchair assistance, mobility coordination, and terminal guidance across all international terminals.
        </p>
        <div style="display:inline-flex;gap:.75rem">
          <button class="btn amber" @click="mount">Test Live Chat Widget</button>
          <button class="btn alt">Book Assistance Online</button>
        </div>
      </div>
    </div>
  </div>

  <p class="sub" style="margin-top:1rem;text-align:center;font-size:.85rem">
    The widget floating action button will appear in the corner of this page. You can click it, chat with the bot, and submit live tickets.
  </p>
</template>
