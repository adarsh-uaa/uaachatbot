export default defineNuxtRouteMiddleware(async (to) => {
  const auth = useAuth()
  if (!auth.ready.value) await auth.load()
  if (!auth.session.value && to.path !== '/login') return navigateTo('/login')
  if (auth.session.value && to.path === '/login') return navigateTo('/')
  const need = to.meta.perm as string | undefined
  if (need && !auth.can(need)) return navigateTo('/')
})
