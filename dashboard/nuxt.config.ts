export default defineNuxtConfig({
  ssr: false, // pure SPA: deploy the static output anywhere (Netlify, Cloudflare Pages, Vercel)
  compatibilityDate: '2024-09-01',
  css: ['~/assets/css/main.css'],
  routeRules: {
    '/uaa-widget.js': {
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      }
    }
  },
  nitro: {
    prerender: {
      crawlLinks: false,
      failOnError: false
    }
  },
  runtimeConfig: {
    public: {
      supabaseUrl: '',  // NUXT_PUBLIC_SUPABASE_URL
      supabaseKey: ''   // NUXT_PUBLIC_SUPABASE_KEY (anon / publishable key)
    }
  },
  app: {
    head: {
      title: 'UAA Support',
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap' }
      ]
    }
  }
})
