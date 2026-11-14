# UAA Support: free hybrid chat + ticket desk

Supabase (free) = database, auth, realtime. Nuxt dashboard = static site. Widget = one JS file (34 KB gzip) for any site.
No server code, no paid AI. Employees answer; keyword rules handle repeat questions.

## 1. Supabase (10 min)
1. Create a free project at supabase.com.
2. Authentication → Providers → Email: **turn OFF "Allow new users to sign up"**.
3. SQL Editor: run `supabase/migrations/001` through `007` in order (one at a time).
   - Migration `005` enables direct user creation with instant email verification (bypassing confirmation emails) and the Teams section.
   - Migration `006` enables safe site deletion with cascading cleanup of tickets, rules, events, canned replies, and secrets.
   - Migration `007` enables live bot chat tracking, instant human agent takeover (which disables automated bot replies), passenger phone number capture, and support teams.
4. Authentication → Users → Add user (your initial admin email). The first user becomes **admin** automatically.
5. Settings → API: copy the Project URL and the anon/publishable key.
   - Subsequent team members can be added **directly from the dashboard** in the Teams section!

## 2. Dashboard
```bash
cd widget && npm install && npm run build      # creates dashboard/public/uaa-widget.js
cd ../dashboard && cp .env.example .env        # paste URL + key
npm install && npm run dev                     # http://localhost:3000
npm run generate                               # static site in .output/public → Cloudflare Pages / Netlify (free)
```
Sign in → Teams: add new users directly with instant email verification, manage departments and pseudo names → Sites: customize chat colors with live preview → Widget preview.

## 3. Put the widget on a site
Sites & themes → pick site → copy the embed code.
- **WordPress**: install the free "WPCode" plugin → Add snippet → Footer → paste.
- **Nuxt site** (`nuxt.config.ts`):
```ts
app: { head: { script: [{ src: 'https://YOUR-DASHBOARD-DOMAIN/uaa-widget.js', defer: true,
  'data-site-key': 'SITE_KEY', 'data-api-url': 'https://xxx.supabase.co', 'data-api-key': 'ANON_KEY' }] } }
```
- **Plain Vue / any HTML**: same `<script>` tag.
Fill "Allowed website addresses" per site so other domains cannot use your key.

## 4. Team alerts without a backend
Sites → Team alerts → paste a Slack / Discord / Google Chat webhook. A database trigger posts every new ticket there.
The dashboard also beeps and shows desktop notifications (click "Turn on desktop alerts").

## 5. Pre-launch checklist
- [ ] Anonymous visitor can open widget, sees greeting + quick buttons
- [ ] "hello", "wheelchair", "human" trigger the right rule; unknown text offers "Talk to our team"
- [ ] Ticket form creates a ticket; alert arrives in Slack/Discord; dashboard beeps
- [ ] Ticket shows as **open**; employee A claims; employee B sees claimer and cannot reply (can add internal note)
- [ ] Reply appears in widget within ~4 s; visitor sees the **pseudo** name only
- [ ] Manager sees "pseudo (real name)"; employee sees pseudo only
- [ ] Employee sees active + closed ≤10 days; team lead/manager see all closed tickets
- [ ] Close → visitor sees "closed" + "Start a new conversation"
- [ ] Rules page: add rule from the dashboard "unanswered" list; copy rules between sites
- [ ] Sites page: change entire chat section colours/icon/texts with live preview → reload widget → changes appear
- [ ] Teams page: add user directly with "Email Verified" checked → user signs in immediately without email confirmation
- [ ] Teams page: deny `dashboard.view` for one employee → their Dashboard link disappears and the RPC refuses
- [ ] Wrong site origin (test from another domain) → widget does not load
- [ ] Mobile layout (375 px)

## 6. Things to know
- Supabase free projects pause after ~1 week of inactivity and have a 500 MB DB limit. Open the dashboard weekly or upgrade later.
- The anon key is public by design. Protection = RLS + security-definer RPCs + rate limits (5 tickets/hour/email, 10 messages/min) + honeypot. The origin allow-list is a soft check (non-browsers can spoof it).
- Visitors poll every 4 s only while a conversation is open.
- Add staff directly in the dashboard under **Teams** → **Add User** (email verified automatically without email links). You can also set role/pseudo/team.
- Do not delete your last admin. Keep a second admin account.

## 7. AI
Skipped on purpose: every free LLM API needs a server-side key, which breaks "no backend". The "unanswered questions" panel
gives you the same result: add keywords for repeated questions and the bot improves weekly.
