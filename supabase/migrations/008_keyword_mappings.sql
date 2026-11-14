-- UAA Support · 008 Comprehensive airport assistance keyword mappings

-- Clean up any existing global rules to avoid duplicates
delete from bot_rules where site_id is null;

insert into bot_rules (site_id, name, keywords, match_type, action, response, link_url, button_label, priority, is_active) values
  (
    null,
    'Greetings & Welcome',
    array['hello', 'hi', 'hey', 'good morning', 'good afternoon', 'good evening', 'start', 'greetings', 'help', 'howdy'],
    'contains',
    'reply',
    'Hello! Welcome to our airport assistance desk. How can we help you today? You can ask about wheelchair assistance, baggage, flight details, or connect directly with our team.',
    null,
    'Hello',
    10,
    true
  ),
  (
    null,
    'Wheelchair & Mobility (PRM)',
    array['wheelchair', 'mobility', 'prm', 'disabled', 'disability', 'handicap', 'walking', 'elderly', 'senior', 'stretcher', 'ramp', 'special assistance', 'escort', 'buggy', 'electric cart', 'accessible'],
    'contains',
    'reply',
    'We provide dedicated assistance for passengers with reduced mobility (PRM) free of charge. Our team can meet you at terminal entry, assist through check-in, security, and boarding. Please book at least 48 hours in advance for priority scheduling.',
    null,
    'Wheelchair assistance',
    20,
    true
  ),
  (
    null,
    'Baggage & Lost Property',
    array['baggage', 'luggage', 'bags', 'bag', 'suitcase', 'lost bag', 'lost luggage', 'delayed baggage', 'damaged bag', 'carousel', 'lost property', 'lost and found', 'lost item', 'lost my', 'left behind', 'left luggage'],
    'contains',
    'reply',
    'For baggage retrieval, delayed luggage, or items left inside the terminal, our Lost Property & Baggage desk is located in the Arrivals Hall near Carousel 3. Would you like to connect with our team to report a lost item?',
    null,
    'Lost baggage & items',
    30,
    true
  ),
  (
    null,
    'Flight, Gates & Check-in',
    array['flight', 'gate', 'terminal', 'boarding', 'check in', 'checkin', 'check-in', 'delay', 'departure', 'arrival', 'boarding pass', 'counter', 'security', 'fast track', 'customs', 'passport'],
    'contains',
    'reply',
    'Check-in desks open 3 hours prior to international flights and 2 hours for domestic flights. Live gate assignments and flight schedules are displayed on terminal screens throughout the airport.',
    null,
    'Flight & Gate info',
    40,
    true
  ),
  (
    null,
    'Terminal Amenities & Wi-Fi',
    array['wifi', 'wi-fi', 'internet', 'restroom', 'restrooms', 'toilet', 'toilets', 'bathroom', 'washroom', 'food', 'restaurant', 'cafe', 'coffee', 'lounge', 'lounges', 'atm', 'cash', 'money', 'charging', 'charger', 'parking', 'taxi', 'cab', 'bus', 'train', 'water', 'smoking', 'prayer'],
    'contains',
    'reply',
    'Free high-speed airport Wi-Fi is available across all terminals. Restrooms, charging stations, prayer rooms, dining, and airline lounges are located along the central concourses.',
    null,
    'Terminal amenities',
    50,
    true
  ),
  (
    null,
    'Talk to Support Team',
    array['human', 'agent', 'person', 'staff', 'representative', 'talk to someone', 'speak to someone', 'talk to team', 'connect', 'live agent', 'operator', 'call me', 'urgent', 'real person', 'help me'],
    'contains',
    'handoff',
    'I would be happy to connect you with our assistance team. Please fill in your details below so an agent can assist you right away:',
    null,
    'Talk to our team',
    5,
    true
  );

-- Update site texts default fallback and handoff for friendly visitor guidance
update sites set texts = jsonb_set(
  jsonb_set(
    coalesce(texts, '{}'::jsonb),
    '{fallback}',
    '"I could not find an automated answer for that. Would you like to connect with our support team? Please share your details below."'
  ),
  '{handoff}',
  '"Connect with our team"'
);
