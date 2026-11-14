<script setup lang="ts">
definePageMeta({ perm: 'canned.manage' })
const sb = useSb(), auth = useAuth(), { show } = useToast()
const rows = ref<any[]>([]), sites = ref<any[]>([]), f = ref<any>({ id: null, title: '', body: '', site_id: null })
async function load() {
  rows.value = (await sb.from('canned_replies').select('*').order('title')).data || []
  sites.value = (await sb.from('sites').select('id,name')).data || []
}
onMounted(load)
async function save() {
  if (!f.value.title.trim() || !f.value.body.trim()) return
  const row = { title: f.value.title.trim(), body: f.value.body.trim(), site_id: f.value.site_id || null }
  const { error } = f.value.id ? await sb.from('canned_replies').update(row).eq('id', f.value.id) : await sb.from('canned_replies').insert({ ...row, created_by: auth.session.value.user.id })
  if (error) return show(error.message, 'err')
  show('Saved reply updated', 'ok'); f.value = { id: null, title: '', body: '', site_id: null }; load()
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
      <p class="sub" style="margin:0">Pre-written responses agents can insert into conversations with a single click.</p>
    </div>
  </div>

  <!-- Create / Edit Canned Reply -->
  <div class="card" style="margin-bottom:1.5rem">
    <h2>{{ f.id ? 'Edit Saved Reply' : 'Add New Saved Reply' }}</h2>
    <div class="cols">
      <div>
        <label>Reply Title <span style="color:var(--red)">*</span></label>
        <input v-model="f.title" placeholder="e.g. Booking Reference Needed">
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
      <button v-if="f.id" class="btn alt" @click="f = { id: null, title: '', body: '', site_id: null }">Cancel</button>
    </div>
  </div>

  <!-- List of Saved Replies -->
  <div class="grid g2">
    <div v-for="r in rows" :key="r.id" class="card" style="display:flex;flex-direction:column;justify-content:space-between">
      <div>
        <div class="row" style="justify-content:space-between;align-items:flex-start;margin-bottom:.5rem">
          <strong>{{ r.title }}</strong>
          <span class="chip" style="background:#f1f5f9;color:var(--muted);font-size:.72rem">
            {{ r.site_id ? sites.find(s => s.id === r.site_id)?.name : 'Global' }}
          </span>
        </div>
        <p style="white-space:pre-wrap;font-size:.88rem;color:var(--ink2);line-height:1.55">{{ r.body }}</p>
      </div>
      <div class="row" style="margin-top:1rem;padding-top:.75rem;border-top:1px solid var(--line-subtle);justify-content:flex-end">
        <button class="btn sm alt" @click="copy(r.body).then(() => show('Copied to clipboard'))">Copy</button>
        <button class="btn sm alt" @click="f = { ...r }">Edit</button>
        <button class="btn sm danger" @click="del(r)">Delete</button>
      </div>
    </div>
  </div>
  <p v-if="!rows.length" class="empty">No saved replies created yet.</p>
</template>
