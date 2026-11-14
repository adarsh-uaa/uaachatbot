-- UAA Support · 004 seed permissions, role defaults, demo site
insert into permissions(key, description) values
 ('tickets.view_all',   'See every ticket, including all closed ones'),
 ('tickets.view_recent','See active tickets and tickets closed in the last 10 days'),
 ('tickets.claim',      'Claim and release tickets'),
 ('tickets.reply',      'Reply to visitors and write internal notes'),
 ('tickets.close',      'Close tickets they own'),
 ('tickets.reassign',   'Assign, release, close or reply on any ticket'),
 ('dashboard.view',     'View the dashboard'),
 ('rules.manage',       'Manage keyword rules'),
 ('canned.manage',      'Manage saved replies'),
 ('sites.manage',       'Manage sites, themes, texts and webhooks'),
 ('users.manage',       'Manage users, roles and permissions'),
 ('users.view_real',    'See real names behind pseudo names');

insert into role_permissions(role, permission) select 'admin', key from permissions;
insert into role_permissions(role, permission) select 'manager', unnest(array[
 'tickets.view_all','tickets.claim','tickets.reply','tickets.close','tickets.reassign','dashboard.view','rules.manage','canned.manage','users.view_real']);
insert into role_permissions(role, permission) select 'teamlead', unnest(array[
 'tickets.view_all','tickets.claim','tickets.reply','tickets.close','tickets.reassign','dashboard.view','rules.manage','canned.manage']);
insert into role_permissions(role, permission) select 'employee', unnest(array[
 'tickets.view_recent','tickets.claim','tickets.reply','tickets.close','dashboard.view']);

insert into sites(name, site_key, faq_url) values ('Demo site', 'demo-site-key', 'https://example.com/faq');

insert into bot_rules(site_id, name, keywords, action, response, link_url, button_label, priority) values
 (null, 'Greeting',        '{hello,hi,hey,good morning,good afternoon}', 'reply',    'Hello! Ask me about booking, assistance times or lost items, or talk to our team.', null, null, 10),
 (null, 'General enquiry', '{enquiry,enquiries,question,information,info}', 'faq_link','Most answers are on our FAQ page:', null, 'Read the FAQ', 20),
 (null, 'Wheelchair',      '{wheelchair,mobility,reduced mobility,prm}', 'reply',    'We provide free assistance for passengers with reduced mobility. Please book at least 48 hours before travel.', null, 'Wheelchair help', 30),
 (null, 'Talk to a person','{human,agent,person,staff,call me}', 'handoff',  'Of course, I will pass you to our team.', null, null, 5);

insert into canned_replies(site_id, title, body) values
 (null, 'Thanks and checking', 'Thank you for contacting us. I am checking this for you and will update you shortly.'),
 (null, 'Need booking ref',    'Could you share your booking reference and the date of travel so we can look into this?');
