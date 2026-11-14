<script setup lang="ts">
definePageMeta({ perm: 'dashboard.view' })
const sb = useSb()
const days = ref(30), site = ref<string>(''), sites = ref<any[]>([]), s = ref<any>(null), error = ref('')
async function load() {
  const { data, error: e } = await sb.rpc('dashboard_stats', { p_days: days.value, p_site: site.value || null })
  if (e) error.value = e.message; else { error.value = ''; s.value = data }
}
onMounted(async () => { sites.value = (await sb.from('sites').select('id,name').order('name')).data || []; load() })
watch([days, site], load)
const max = (a: any[], k: string) => Math.max(1, ...(a || []).map(x => x[k]))
</script>
<template>
  <div class="row" style="justify-content:space-between;align-items:flex-start;margin-bottom:1.5rem">
    <div>
      <h1>Dashboard Overview</h1>
      <p class="sub" style="margin:0">Live metrics on visitor enquiries, response performance, and team resolution.</p>
    </div>
    <div class="row">
      <select v-model="days" style="width:auto">
        <option :value="7">Last 7 days</option>
        <option :value="30">Last 30 days</option>
        <option :value="90">Last 90 days</option>
      </select>
      <select v-model="site" style="width:auto">
        <option value="">All sites</option>
        <option v-for="x in sites" :key="x.id" :value="x.id">{{ x.name }}</option>
      </select>
    </div>
  </div>

  <p v-if="error" class="err">{{ error }}</p>

  <template v-if="s">
    <div class="grid g4" style="margin-bottom:1.5rem">
      <div class="card stat" style="border-left-color: var(--red);">
        <small>Unclaimed</small>
        <b>{{ s.open }}</b>
        <span class="sub" style="font-size:.78rem">Needs attention</span>
      </div>
      <div class="card stat amber">
        <small>In Progress</small>
        <b>{{ s.claimed }}</b>
        <span class="sub" style="font-size:.78rem">Currently claimed</span>
      </div>
      <div class="card stat green">
        <small>Resolved</small>
        <b>{{ s.closed }}</b>
        <span class="sub" style="font-size:.78rem">Closed in period</span>
      </div>
      <div class="card stat" style="border-left-color: var(--accent);">
        <small>Avg First Reply</small>
        <b>{{ s.avg_first_response_min != null ? `${s.avg_first_response_min}m` : '—' }}</b>
        <span class="sub" style="font-size:.78rem">Response time</span>
      </div>
    </div>

    <div class="grid g2">
      <div class="card">
        <h2>Top Bot Inquiries</h2>
        <p class="sub">Frequent questions successfully resolved by automatic keyword rules.</p>
        <p v-if="!s.top_rules.length" class="empty">No bot questions recorded yet.</p>
        <div v-for="r in s.top_rules" :key="r.name" class="bar">
          <span>{{ r.name }}</span>
          <i :style="{ width: (r.hits / max(s.top_rules,'hits')) * 50 + '%' }" />
          <b style="font-size:.85rem;color:var(--muted)">{{ r.hits }}</b>
        </div>
      </div>

      <div class="card">
        <h2>Unanswered Questions</h2>
        <p class="sub">Questions visitors typed where no automated answer was matched.</p>
        <p v-if="!s.unmatched.length" class="empty">All visitor questions matched existing rules.</p>
        <div v-for="r in s.unmatched" :key="r.query" class="row" style="justify-content:space-between;border-bottom:1px solid var(--line-subtle);padding:.5rem 0">
          <span class="grow" style="font-size:.9rem">
            {{ r.query }} <span class="chip" style="margin-left:.4rem">{{ r.hits }} hits</span>
          </span>
          <NuxtLink v-if="useAuth().can('rules.manage')" class="btn sm alt" :to="{ path: '/rules', query: { kw: r.query } }">
            + Create rule
          </NuxtLink>
        </div>
      </div>

      <div class="card">
        <h2>Ticket Volume Over Time</h2>
        <p class="sub">Number of support tickets opened per day in the selected period.</p>
        <p v-if="!s.per_day.length" class="empty">No tickets created in this period.</p>
        <div class="spark">
          <i
            v-for="d in s.per_day"
            :key="d.d"
            :title="`${d.d}: ${d.n} tickets`"
            :style="{ height: Math.max(10, (d.n / max(s.per_day,'n')) * 100) + '%' }"
          />
        </div>
      </div>

      <div class="card">
        <h2>Tickets by Website</h2>
        <p class="sub">Breakdown of assistance tickets across connected properties.</p>
        <div v-for="r in s.by_site" :key="r.name" class="bar">
          <span>{{ r.name }}</span>
          <i :style="{ width: (r.tickets / max(s.by_site,'tickets')) * 50 + '%', backgroundColor: 'var(--teal)' }" />
          <b style="font-size:.85rem;color:var(--muted)">{{ r.tickets }}</b>
        </div>
      </div>
    </div>
  </template>
</template>
