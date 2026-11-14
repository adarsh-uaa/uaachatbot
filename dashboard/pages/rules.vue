<script setup lang="ts">
definePageMeta({ perm: 'rules.manage' })
const sb = useSb(), auth = useAuth(), route = useRoute(), { show } = useToast()
const rules = ref<any[]>([]), sites = ref<any[]>([]), filter = ref('all'), editing = ref<any>(null), error = ref('')
const cloneFrom = ref('global'), cloneTo = ref('')
const blank = () => ({ id: null, site_id: filter.value === 'all' || filter.value === 'global' ? null : filter.value, name: '', keywords: '', match_type: 'contains', action: 'reply', response: '', link_url: '', button_label: '', priority: 100, is_active: true })

async function load() {
  sites.value = (await sb.from('sites').select('id,name').order('name')).data || []
  rules.value = (await sb.from('bot_rules').select('*').order('priority')).data || []
}
onMounted(async () => {
  await load()
  if (route.query.kw) { editing.value = { ...blank(), name: String(route.query.kw), keywords: String(route.query.kw) } }
})
const siteName = (id: string | null) => id ? sites.value.find(s => s.id === id)?.name : 'All sites'
const shown = computed(() => rules.value.filter(r => filter.value === 'all' || (filter.value === 'global' ? !r.site_id : r.site_id === filter.value)))
function edit(r: any) { editing.value = { ...r, keywords: r.keywords.join(', '), link_url: r.link_url || '', button_label: r.button_label || '' } }
async function save() {
  error.value = ''
  const e = editing.value
  const kws = e.keywords.split(',').map((k: string) => k.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').trim()).filter(Boolean)
  if (!e.name.trim() || !kws.length || !e.response.trim()) { error.value = 'Name, at least one keyword and a response are required.'; return }
  const row = { site_id: e.site_id || null, name: e.name.trim(), keywords: kws, match_type: e.match_type, action: e.action, response: e.response.trim(),
    link_url: e.link_url.trim() || null, button_label: e.button_label.trim() || null, priority: Number(e.priority) || 100, is_active: e.is_active }
  const { error: er } = e.id ? await sb.from('bot_rules').update(row).eq('id', e.id) : await sb.from('bot_rules').insert({ ...row, created_by: auth.session.value.user.id })
  if (er) { error.value = er.message; return }
  show('Rule saved successfully', 'ok'); editing.value = null; load()
}
async function remove(r: any) { if (!confirm(`Delete rule "${r.name}"?`)) return; await sb.from('bot_rules').delete().eq('id', r.id); show('Rule deleted', 'ok'); load() }
async function toggle(r: any) { await sb.from('bot_rules').update({ is_active: !r.is_active }).eq('id', r.id); load() }
async function clone() {
  if (!cloneTo.value || cloneTo.value === cloneFrom.value) { show('Pick two different sites', 'err'); return }
  const { data, error: er } = await sb.rpc('clone_rules', { p_from: cloneFrom.value === 'global' ? null : cloneFrom.value, p_to: cloneTo.value === 'global' ? null : cloneTo.value })
  if (er) show(er.message, 'err'); else { show(`${data} rules copied`, 'ok'); load() }
}
</script>
<template>
  <div class="row" style="justify-content:space-between;margin-bottom:1rem">
    <div>
      <h1>Bot Keyword Rules</h1>
      <p class="sub" style="margin:0">Configure automated replies, FAQ links, and team handoffs for matching questions.</p>
    </div>
    <div class="row">
      <select v-model="filter" style="width:auto">
        <option value="all">All Rules</option>
        <option value="global">Global Rules Only</option>
        <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
      <button class="btn amber" @click="editing = blank()">+ New Rule</button>
    </div>
  </div>

  <!-- Rule Editor Card -->
  <div v-if="editing" class="card" style="margin-bottom:1.5rem">
    <div class="row" style="justify-content:space-between;margin-bottom:.5rem">
      <h2>{{ editing.id ? 'Edit Keyword Rule' : 'Create Keyword Rule' }}</h2>
      <button class="btn sm alt" @click="editing = null">Cancel</button>
    </div>
    
    <div class="cols">
      <div>
        <label>Rule Name <span style="color:var(--red)">*</span></label>
        <input v-model="editing.name" placeholder="e.g. Wheelchair assistance">
      </div>
      <div>
        <label>Applies To</label>
        <select v-model="editing.site_id">
          <option :value="null">All sites (Global)</option>
          <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
      </div>
      <div>
        <label>Action</label>
        <select v-model="editing.action">
          <option value="reply">Automated text reply</option>
          <option value="faq_link">Reply + Open FAQ link</option>
          <option value="handoff">Handoff to human staff</option>
        </select>
      </div>
      <div>
        <label>Match Type</label>
        <select v-model="editing.match_type">
          <option value="contains">Contains any keyword</option>
          <option value="exact">Exact query match</option>
        </select>
      </div>
    </div>

    <label>Keywords <small>(comma separated, e.g. wheelchair, mobility, PRM, special assistance)</small></label>
    <input v-model="editing.keywords" placeholder="wheelchair, prm, mobility">

    <label>Bot Response Message <span style="color:var(--red)">*</span></label>
    <textarea v-model="editing.response" rows="3" placeholder="We provide free assistance for passengers with reduced mobility…" />

    <div class="cols">
      <div>
        <label>External Link URL <small>(optional)</small></label>
        <input v-model="editing.link_url" placeholder="https://example.com/prm-guide">
      </div>
      <div>
        <label>Quick Button Label <small>(shown as clickable pill)</small></label>
        <input v-model="editing.button_label" placeholder="Wheelchair Help">
      </div>
      <div>
        <label>Priority <small>(lower numbers match first)</small></label>
        <input v-model="editing.priority" type="number">
      </div>
    </div>

    <div class="row" style="margin-top:.75rem">
      <label style="margin:0;font-weight:500;display:inline-flex;align-items:center;gap:.4rem;cursor:pointer">
        <input type="checkbox" v-model="editing.is_active" style="width:auto;cursor:pointer">
        <span>Rule is active and enabled</span>
      </label>
    </div>

    <p v-if="error" class="err">{{ error }}</p>

    <div class="row" style="margin-top:1.25rem">
      <button class="btn amber" @click="save">Save Rule</button>
      <button class="btn alt" @click="editing = null">Cancel</button>
    </div>
  </div>

  <!-- Rules Table Card -->
  <div class="card scroll" style="padding:0;overflow:hidden;margin-bottom:1.5rem">
    <table>
      <thead>
        <tr>
          <th>Rule Details</th>
          <th>Scope</th>
          <th>Keywords</th>
          <th>Action</th>
          <th>Priority</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in shown" :key="r.id" :style="{ opacity: r.is_active ? 1 : .55 }">
          <td>
            <strong>{{ r.name }}</strong>
            <small class="sub" style="display:block;font-size:.78rem;max-width:280px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
              {{ r.response }}
            </small>
          </td>
          <td>
            <span class="chip" style="background:#f1f5f9;color:var(--muted)">{{ siteName(r.site_id) }}</span>
          </td>
          <td style="max-width:200px">
            <span style="font-size:.84rem;color:var(--ink2)">{{ r.keywords.join(', ') }}</span>
          </td>
          <td>
            <span class="chip" :class="r.action === 'handoff' ? 'open' : 'role'">{{ r.action }}</span>
          </td>
          <td><span style="font-weight:600;font-size:.85rem">{{ r.priority }}</span></td>
          <td>
            <span class="chip" :class="r.is_active ? 'closed' : ''">
              {{ r.is_active ? 'Active' : 'Paused' }}
            </span>
          </td>
          <td class="row" style="white-space:nowrap">
            <button class="btn sm alt" @click="edit(r)">Edit</button>
            <button class="btn sm alt" @click="toggle(r)">{{ r.is_active ? 'Pause' : 'Resume' }}</button>
            <button class="btn sm danger" @click="remove(r)">Delete</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-if="!shown.length" class="empty">No keyword rules found. Click "+ New Rule" to create automated replies.</p>
  </div>

  <!-- Copy Rules Card -->
  <div class="card">
    <h2>Duplicate & Copy Rules</h2>
    <p class="sub">Quickly duplicate rules from global settings or between sites.</p>
    <div class="row">
      <select v-model="cloneFrom" style="width:auto">
        <option value="global">All sites (Global)</option>
        <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
      <span style="color:var(--muted)">→</span>
      <select v-model="cloneTo" style="width:auto">
        <option value="">Destination site…</option>
        <option value="global">All sites (Global)</option>
        <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
      <button class="btn alt" @click="clone">Copy Rules</button>
    </div>
  </div>
</template>
