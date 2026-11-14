<script setup lang="ts">
const auth = useAuth()
const email = ref(''), password = ref(''), error = ref(''), busy = ref(false)
async function submit() {
  if (!email.value || !password.value) return
  error.value = ''; busy.value = true
  try { await auth.login(email.value, password.value); await navigateTo('/') }
  catch (e: any) { error.value = e.message || 'Could not sign in' }
  busy.value = false
}
</script>
<template>
  <div class="login">
    <div class="card" style="box-shadow: 0 20px 40px -15px rgba(0,0,0,0.3); border-radius: 16px;">
      <div style="display:flex;align-items:center;gap:.6rem;margin-bottom:1rem">
        <span style="display:inline-flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:9px;background:#2563eb;color:#fff">
          <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0-2-.9-2-2V4c0-1.1-.9-2-2-2z"/></svg>
        </span>
        <div>
          <h1 style="font-size:1.4rem;margin:0">UAA Support</h1>
          <small style="color:var(--muted);font-weight:500">Airport assistance desk</small>
        </div>
      </div>
      <p class="sub" style="margin-bottom:1.5rem">Sign in with your staff account to access conversations and tickets.</p>
      
      <form @submit.prevent="submit">
        <label for="e">Work Email</label>
        <input id="e" v-model="email" type="email" autocomplete="username" placeholder="staff@airport.com" required style="margin-bottom:.5rem">
        
        <label for="p">Password</label>
        <input id="p" v-model="password" type="password" autocomplete="current-password" placeholder="••••••••" required style="margin-bottom:1rem">
        
        <p v-if="error" class="err" style="margin-bottom:1rem;padding:.5rem .75rem;background:var(--red-soft);border-radius:6px;border:1px solid var(--red-border)">
          {{ error }}
        </p>
        
        <button class="btn amber" :disabled="busy" style="width:100%;padding:.7rem;font-size:.95rem;border-radius:8px">
          {{ busy ? 'Signing in…' : 'Sign in to Dashboard' }}
        </button>
      </form>
    </div>
  </div>
</template>
