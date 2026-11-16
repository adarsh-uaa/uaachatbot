-- UAA Support · 015 Database Performance Indexes & Optimization
-- Adds targeted indexes for high-concurrency widget traffic and staff dashboard queries.

-- 1. Index for fast site configuration lookup by site_key
create index if not exists idx_sites_site_key on sites(site_key) where is_active = true;

-- 2. Index for visitor session token lookups (polled every few seconds by active widgets)
create index if not exists idx_tickets_visitor_token on tickets(visitor_token);

-- 3. Composite index for active/unclaimed ticket queue queries in dashboard
create index if not exists idx_tickets_status_unread on tickets(status, unread_by_staff, updated_at desc);

-- 4. Index for tickets by site_id and status (filter tabs and per-site ticket lists)
create index if not exists idx_tickets_site_status on tickets(site_id, status);

-- 5. Index for claimed agent queue ('My Tickets')
create index if not exists idx_tickets_claimed_by on tickets(claimed_by) where status = 'claimed';

-- 6. Index for ordered message retrieval inside tickets (thread loading and polling)
create index if not exists idx_ticket_messages_ticket_created on ticket_messages(ticket_id, created_at asc);

-- 7. Composite index for bot keyword matching rules
create index if not exists idx_bot_rules_site_active_prio on bot_rules(site_id, is_active, priority asc);

-- 8. Index for query event logs
create index if not exists idx_bot_events_site_created on bot_events(site_id, created_at desc);

-- 9. Optimize query plan statistics
analyze sites;
analyze tickets;
analyze ticket_messages;
analyze bot_rules;
analyze bot_events;

