// zoom-meeting: make a Zoom meeting for Schedule a call. The app sends the
// Gaard people on the call (the scheduler first); the first of them who is a
// user in Gaard's Zoom account hosts it. When none is, or Zoom is not set up
// here, the answer has no join_url and the app makes a Google Meet instead.
//
// Setup, once (needs an admin of Gaard's Zoom account):
// 1. marketplace.zoom.us > Develop > Build App > Server-to-Server OAuth App,
//    named "Gaard CRM". Scopes: meeting:write:meeting:admin (create a meeting
//    for a user) and user:read:user:admin. Activate it.
// 2. Supabase dashboard > Edge Functions > Secrets: ZOOM_ACCOUNT_ID,
//    ZOOM_CLIENT_ID, ZOOM_CLIENT_SECRET from the app's App Credentials. They
//    never go in this repository.
// 3. Edge Functions > Deploy a new function > Via Editor, name it zoom-meeting,
//    paste this file, deploy. Leave "Verify JWT" ON: only a signed-in person
//    reaches it, and it checks is_team_member() (which needs the two-step code).

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const caller = createClient(Deno.env.get('SUPABASE_URL')!, req.headers.get('apikey') ?? Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      auth: { persistSession: false },
    });
    const { data: ok, error: tmErr } = await caller.rpc('is_team_member');
    if (tmErr || !ok) return json({ error: 'Only a team member, signed in with the two-step code, can make a meeting.' }, 403);

    const account = Deno.env.get('ZOOM_ACCOUNT_ID'), id = Deno.env.get('ZOOM_CLIENT_ID'), secret = Deno.env.get('ZOOM_CLIENT_SECRET');
    if (!account || !id || !secret) return json({ reason: 'Zoom is not set up for the CRM yet.' });

    const { hosts = [], topic = 'Gaard Capital', start, minutes = 30 } = await req.json();
    const emails = (Array.isArray(hosts) ? hosts : []).map((h) => String(h).trim().toLowerCase())
      .filter((h) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(h)).slice(0, 10);
    if (!emails.length) return json({ reason: 'Nobody from Gaard is on the call.' });

    const tok = await fetch('https://zoom.us/oauth/token?grant_type=account_credentials&account_id=' + encodeURIComponent(account), {
      method: 'POST', headers: { Authorization: 'Basic ' + btoa(id + ':' + secret) },
    }).then((r) => r.json());
    if (!tok.access_token) return json({ reason: 'Zoom refused the CRM: ' + (tok.reason || tok.error || 'no token') });

    for (const email of emails) {
      const r = await fetch('https://api.zoom.us/v2/users/' + encodeURIComponent(email) + '/meetings', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + tok.access_token, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topic: String(topic).slice(0, 200), type: 2, start_time: start, duration: Math.max(5, Math.min(600, Number(minutes) || 30)),
          timezone: 'America/Denver', settings: { join_before_host: false, waiting_room: true },
        }),
      });
      const m = await r.json().catch(() => ({}));
      if (r.ok && m.join_url) return json({ join_url: m.join_url, passcode: m.password || '', id: m.id, host: email });
      // 1001: not a user in this Zoom account; try the next person
      if (m.code !== 1001 && r.status !== 404) return json({ reason: 'Zoom answered ' + r.status + ': ' + (m.message || '') });
    }
    return json({ reason: 'Nobody on the call has a user in Gaard\'s Zoom account.' });
  } catch (err) {
    return json({ error: String((err as Error)?.message ?? err) }, 500);
  }
});
