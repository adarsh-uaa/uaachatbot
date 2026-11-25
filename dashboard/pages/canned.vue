<script setup lang="ts">
definePageMeta({ perm: 'canned.manage' })
const sb = useSb(), auth = useAuth(), { show } = useToast()
const rows = ref<any[]>([]), sites = ref<any[]>([]), f = ref<any>({ id: null, title: '', body: '', site_id: null, shortcut: '' })

async function load() {
  rows.value = (await sb.from('canned_replies').select('*').order('title')).data || []
  sites.value = (await sb.from('sites').select('id,name')).data || []
}
onMounted(load)

function cleanShortcut(s: any) {
  if (!s) return null
  const cleaned = String(s).trim().replace(/^\/+/, '').toLowerCase()
  return cleaned || null
}

async function save() {
  if (!f.value.title.trim() || !f.value.body.trim()) return
  const shortcut = cleanShortcut(f.value.shortcut)
  const row = {
    title: f.value.title.trim(),
    body: f.value.body.trim(),
    site_id: f.value.site_id || null,
    shortcut
  }
  const { error } = f.value.id
    ? await sb.from('canned_replies').update(row).eq('id', f.value.id)
    : await sb.from('canned_replies').insert({ ...row, created_by: auth.session.value?.user?.id })
  if (error) return show(error.message, 'err')
  show(f.value.id ? 'Saved reply updated' : 'Saved reply created', 'ok')
  f.value = { id: null, title: '', body: '', site_id: null, shortcut: '' }
  load()
}

function editReply(r: any) {
  f.value = {
    id: r.id,
    title: r.title,
    body: r.body,
    site_id: r.site_id,
    shortcut: r.shortcut || ''
  }
  if (typeof window !== 'undefined') {
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }
}

async function del(r: any) {
  if (confirm(`Delete saved reply "${r.title}"?`)) {
    await sb.from('canned_replies').delete().eq('id', r.id)
    show('Reply deleted', 'ok')
    load()
  }
}
</script>

<template>
  <div class="row" style="justify-content:space-between;margin-bottom:1rem">
    <div>
      <h1>Saved Replies (Canned Responses)</h1>
      <p class="sub" style="margin:0">Pre-written responses agents can insert into conversations with a single click or keyboard shortkey (e.g. <code>/g</code>).</p>
    </div>
  </div>

  <!-- Create / Edit Canned Reply -->
  <div class="card" style="margin-bottom:1.5rem">
    <h2>{{ f.id ? 'Edit Saved Reply' : 'Add New Saved Reply' }}</h2>
    <div class="cols" style="grid-template-columns:repeat(auto-fit, minmax(200px, 1fr));gap:1rem;margin-bottom:1rem">
      <div>
        <label>Reply Title <span style="color:var(--red)">*</span></label>
        <input v-model="f.title" placeholder="e.g. Greeting / Booking Reference">
      </div>
      <div>
        <label>
          Shortkey / Shortcut
          <small class="sub" style="margin:0;font-size:.76rem">(e.g. <code>/g</code> or <code>/thanks</code>)</small>
        </label>
        <div style="position:relative;display:flex;align-items:center">
          <span style="position:absolute;left:10px;font-weight:700;color:var(--muted);font-size:.92rem;pointer-events:none">/</span>
          <input
            v-model="f.shortcut"
            placeholder="e.g. g or greeting"
            style="padding-left:24px;padding-right:32px"
            @input="f.shortcut = (f.shortcut || '').replace(/^\/+/, '').toLowerCase()"
          >
          <button
            v-if="f.shortcut"
            type="button"
            style="position:absolute;right:8px;background:none;border:none;color:var(--muted);cursor:pointer;font-size:.85rem;padding:2px"
            @click="f.shortcut = ''"
            title="Remove shortkey"
          >
            ✕
          </button>
        </div>
        <small class="sub" style="display:block;margin:.25rem 0 0 0;font-size:.76rem">
          Type <code>/{{ f.shortcut || 'key' }}</code> in chat to expand. Clear field to remove.
        </small>
      </div>
      <div>
        <label>Applies To</label>
        <select v-model="f.site_id">
          <option :value="null">All sites (Global)</option>
          <option v-for="s in sites" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
      </div>
    </div>
    
    <label>Message Content <span style="color:var(--red)">*</span></label>
    <textarea v-model="f.body" rows="3" placeholder="Thank you for reaching out. Could you please provide your booking reference…"></textarea>
    
    <div class="row" style="margin-top:1rem">
      <button class="btn amber" @click="save">{{ f.id ? 'Update Saved Reply' : 'Save Reply' }}</button>
      <button v-if="f.id" class="btn alt" @click="f = { id: null, title: '', body: '', site_id: null, shortcut: '' }">Cancel</button>
    </div>
  </div>

  <!-- List of Saved Replies -->
  <div class="grid g2">
    <div v-for="r in rows" :key="r.id" class="card" style="display:flex;flex-direction:column;justify-content:space-between">
      <div>
        <div class="row" style="justify-content:space-between;align-items:flex-start;margin-bottom:.5rem;gap:.5rem">
          <div style="display:flex;align-items:center;gap:.5rem;flex-wrap:wrap">
            <strong>{{ r.title }}</strong>
            <span v-if="r.shortcut" class="chip" style="background:#fef3c7;border:1px solid #fde68a;color:#92400e;font-weight:700;font-size:.78rem;padding:2px 8px;border-radius:4px" title="Type /{{ r.shortcut }} in chat to quickly insert this reply">
              ⌨️ /{{ r.shortcut }}
            </span>
          </div>
          <span class="chip" style="background:#f1f5f9;color:var(--muted);font-size:.72rem">
            {{ r.site_id ? sites.find(s => s.id === r.site_id)?.name : 'Global' }}
          </span>
        </div>
        <p style="white-space:pre-wrap;font-size:.88rem;color:var(--ink2);line-height:1.55">{{ r.body }}</p>
      </div>
      <div class="row" style="margin-top:1rem;padding-top:.75rem;border-top:1px solid var(--line-subtle);justify-content:flex-end">
        <button class="btn sm alt" @click="copy(r.body).then(() => show('Copied to clipboard'))">Copy</button>
        <button class="btn sm alt" @click="editReply(r)">Edit</button>
        <button class="btn sm danger" @click="del(r)">Delete</button>
      </div>
    </div>
  </div>
  <p v-if="!rows.length" class="empty">No saved replies created yet.</p>
</template>
