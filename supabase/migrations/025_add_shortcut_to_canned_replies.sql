-- Migration 025: Add shortcut/shortkey support to canned_replies
-- Allows agents to trigger quick replies using /<shortkey> (e.g. /g for Greeting)

alter table canned_replies add column if not exists shortcut text;

-- Index on lower(shortcut) for fast lookups
create index if not exists idx_canned_replies_shortcut on canned_replies (lower(shortcut)) where shortcut is not null;

-- Populate default shortkeys for existing default replies if available
update canned_replies set shortcut = 'thanks' where (title ilike '%thanks%' or title ilike '%checking%') and shortcut is null;
update canned_replies set shortcut = 'ref' where (title ilike '%booking ref%' or title ilike '%flight%') and shortcut is null;
update canned_replies set shortcut = 'g' where (title ilike '%greeting%' or title ilike '%hello%') and shortcut is null;

-- Add standard Greeting canned reply with /g if not already present
insert into canned_replies (site_id, title, body, shortcut)
select 
  null, 
  'Greeting', 
  'Hello! Thank you for reaching out to our airport support desk. How can I assist you today?', 
  'g'
where not exists (select 1 from canned_replies where lower(shortcut) = 'g');

