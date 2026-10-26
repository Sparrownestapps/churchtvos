// End-to-end tests of the MCP tools against an in-memory database (fakedb.mjs; no RLS, logic only).
// Run: node supabase/functions/mcp/tests/test.mjs   (Node 22.18+ / 24, no packages needed)
import path from 'node:path';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Node 24 runs the .ts files directly (type stripping); this hook swaps supabase-js for the in-memory fake.
const here = path.dirname(fileURLToPath(import.meta.url));
const fake = pathToFileURL(path.join(here, 'fakedb.mjs')).href;
register('data:text/javascript,' + encodeURIComponent(
  `export async function resolve(s, c, next) { return s.startsWith('npm:@supabase/') ? { url: ${JSON.stringify(fake)}, shortCircuit: true } : next(s, c); }`));
let handler;
globalThis.Deno = { env: { get: (k) => ({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'k' })[k] }, serve: (h) => { handler = h; } };
const { T, calls } = await import(fake);
await import(pathToFileURL(path.join(here, '..', 'index.ts')).href);

// ── seed ──
const ORG = '10000000-0000-4000-8000-000000000001', SITE = '10000000-0000-4000-8000-000000000002';
const LOBBY = '10000000-0000-4000-8000-000000000003', KIDSROOM = '10000000-0000-4000-8000-000000000004';
const SC1 = '10000000-0000-4000-8000-000000000005', SC2 = '10000000-0000-4000-8000-000000000006', SCK = '10000000-0000-4000-8000-000000000007';
const IMG1 = '10000000-0000-4000-8000-000000000008', IMG2 = '10000000-0000-4000-8000-000000000009', VID = '10000000-0000-4000-8000-00000000000a';
const SONG = '10000000-0000-4000-8000-00000000000b';
const now = new Date().toISOString();
Object.assign(T, {
  memberships: [{ organization_id: ORG, user_id: 'user-1', role: 'owner', modules: ['kids', 'signage', 'slides'], site_ids: null }],
  organizations: [{ id: ORG, name: 'Forward Church' }],
  sites: [{ id: SITE, organization_id: ORG, name: 'Cambridge', timezone: 'America/Toronto' }],
  locations: [{ id: LOBBY, organization_id: ORG, site_id: SITE, name: 'Lobby' }, { id: KIDSROOM, organization_id: ORG, site_id: SITE, name: 'Kids Room' }],
  screens: [
    { id: SC1, organization_id: ORG, location_id: LOBBY, group_id: null, name: 'Lobby TV', default_module: 'signage', last_seen_at: now, signage_default_playlist_id: null, app_version: '1.7.0' },
    { id: SC2, organization_id: ORG, location_id: LOBBY, group_id: null, name: 'Lobby Portrait', default_module: 'signage', last_seen_at: null, signage_default_playlist_id: null, app_version: '1.7.0' },
    { id: '10000000-0000-4000-8000-0000000000ff', organization_id: ORG, location_id: null, group_id: null, name: 'Loose TV', default_module: 'signage', last_seen_at: null, signage_default_playlist_id: null, app_version: '1.7.0' },
    { id: SCK, organization_id: ORG, location_id: KIDSROOM, group_id: null, name: 'Kids TV', default_module: 'kids', last_seen_at: now, signage_default_playlist_id: null, app_version: '1.3.0' },
  ],
  screen_groups: [],
  entitlements: ['kids', 'signage', 'slides'].map((m) => ({ organization_id: ORG, module: m, status: 'active' })),
  media: [
    { id: IMG1, organization_id: ORG, module: 'signage', title: 'Youth Night', kind: 'image', url: 'https://cdn/a.png', created_at: now },
    { id: IMG2, organization_id: ORG, module: 'signage', title: 'Coffee', kind: 'image', url: 'https://cdn/b.png', created_at: now },
    { id: VID, organization_id: ORG, module: 'kids', title: 'Bible story wk1', kind: 'video', url: 'https://cdn/v.mp4', created_at: now },
  ],
  songs: [{ id: SONG, organization_id: ORG, title: 'Way Maker', authors: 'Sinach', ccli_number: '7115744' }],
  screen_schedules: [], signage_slots: [], signage_playlists: [], playlists: [], decks: [], slide_themes: [],
  schedules: [], deck_schedules: [], kids_series: [], deck_series: [], kids_series_exceptions: [], deck_series_exceptions: [], mcp_activity: [], mcp_upload_requests: [], content_folders: [],
});

let id = 1;
async function rpc(method, params, token = 'good') {
  const r = await handler(new Request('https://x.supabase.co/functions/v1/mcp', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: id++, method, params }) }));
  return { status: r.status, body: r.status === 202 ? null : await r.json() };
}
async function tool(name, args) {
  const { body } = await rpc('tools/call', { name, arguments: args });
  const res = body.result;
  return { err: !!res.isError, text: res.content[0].text };
}
const ok = (r, label) => { if (r.err) { console.error('FAILED', label, r.text); process.exit(1); } console.log(`✓ ${label}`); return r.text; };
const bad = (r, re, label) => { assert.ok(r.err, `${label}: expected error, got ${r.text}`); assert.match(r.text, re, label); console.log(`✓ ${label} (refused: ${r.text.slice(0, 90)}…)`); };

// ── protocol ──
assert.equal((await rpc('tools/call', { name: 'list_targets' }, 'nope')).status, 401);
const list = (await rpc('tools/list')).body.result.tools;
console.log(`✓ ${list.length} tools: ${list.map((t) => t.name).join(', ')}`);
assert.ok(list.every((t) => t.inputSchema && !t.run));

// ── common ──
let t = ok(await tool('list_targets', {}), 'list_targets');
assert.match(t, /Lobby TV/); assert.match(t, /local now/);
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex').toString('base64');
t = ok(await tool('upload_image', { organization_id: ORG, title: 'Poster', image_base64: PNG }), 'upload_image');
assert.equal(T.media.length, 4);
bad(await tool('upload_image', { organization_id: ORG, title: 'x', image_base64: Buffer.from('hello').toString('base64') }), /PNG, JPEG/, 'upload_image rejects non-image');
bad(await tool('upload_image', { organization_id: ORG, title: 'x', image_url: 'https://localhost/a.png' }), /public https/, 'upload_image rejects private url');
t = ok(await tool('request_upload', { organization_id: ORG, module: 'kids', title: 'Week 2 video' }), 'request_upload');
const upId = /upload\?request=([0-9a-f-]+)/.exec(t)[1];
assert.match(ok(await tool('check_upload', { upload_id: upId }), 'check_upload (pending)'), /Not uploaded yet/);
T.mcp_upload_requests[0].media_id = VID;
assert.match(ok(await tool('check_upload', { upload_id: upId }), 'check_upload (done)'), new RegExp(VID));

// ── signage: Keith's example ──
const run = { screen_ids: [SC1], items: [{ media_id: IMG1 }, { media_id: IMG2 }], seconds: 10, days: 'weekdays', start: '09:00', end: '18:00' };
t = ok(await tool('schedule_signage', run), 'schedule_signage weekday run preview');
assert.match(t, /PREVIEW ONLY/); assert.match(t, /Monday–Friday/); assert.match(t, /goes blank when nothing is scheduled/); assert.match(t, /rotating/);
assert.equal(T.signage_slots.length, 0);
t = ok(await tool('schedule_signage', { ...run, confirm: true }), 'schedule_signage weekday run confirm');
assert.equal(T.signage_slots.length, 1);
const slot = T.signage_slots[0];
assert.deepEqual(slot.days, [1, 2, 3, 4, 5]); assert.equal(slot.start_time, '09:00:00'); assert.equal(slot.end_time, '18:00:00'); assert.equal(slot.priority, 50); assert.equal(slot.end_date, null);
assert.equal(T.signage_playlists[0].items.length, 2); assert.equal(T.signage_playlists[0].items[1].seconds, 10);
const runActivity = +/activity_id: (\d+)/.exec(t)[1];

// one-off Friday 8–10pm that overlaps nothing, then one that overlaps the run
t = ok(await tool('schedule_signage', { screen_ids: [SC1, SC2], items: [{ media_id: IMG1 }], date: '2030-11-01', start: '20:00', end: '22:00' }), 'one-off preview');
assert.match(t, /holds for the whole window/);
assert.match(t, /Friday 2030-11-01/); assert.match(t, /Lobby Portrait.*offline/);
t = ok(await tool('schedule_signage', { screen_ids: [SC1], items: [{ media_id: IMG1 }], date: '2030-11-01', start: '12:00', end: '13:00' }), 'one-off overlapping preview');
assert.match(t, /Takes over from/);
bad(await tool('schedule_signage', { screen_ids: [SC1], items: [{ media_id: IMG1 }], date: '2020-01-01', start: '12:00', end: '13:00' }), /already ended/, 'past date refused');
bad(await tool('schedule_signage', { screen_ids: [SC1], items: [{ media_id: IMG1 }], days: 'weekdays', start: '18:00', end: '09:00' }), /overnight/, 'overnight refused');
t = ok(await tool('schedule_signage', { screen_ids: [SCK], items: [{ media_id: IMG1 }], date: '2030-11-01', start: '12:00', end: '13:00' }), 'kids screen preview');
assert.match(t, /set to run kids/);

// list, cancel, undo
t = ok(await tool('list_signage_schedule', { organization_id: ORG }), 'list_signage_schedule');
assert.match(t, /\[assistant\]/);
t = ok(await tool('cancel_signage', { slot_id: slot.id }), 'cancel preview');
assert.equal(T.signage_slots.length, 1);
t = ok(await tool('cancel_signage', { slot_id: slot.id, confirm: true }), 'cancel confirm');
assert.equal(T.signage_slots.length, 0); assert.equal(T.signage_playlists.length, 0);
const cancelAct = +/activity_id: (\d+)/.exec(t)[1];
ok(await tool('undo_change', { activity_id: cancelAct, confirm: true }), 'undo the cancel');
assert.equal(T.signage_slots.length, 1); assert.equal(T.signage_playlists.length, 1); assert.equal(T.signage_slots[0].id, slot.id);
ok(await tool('undo_change', { activity_id: runActivity, confirm: true }), 'undo the original run');
assert.equal(T.signage_slots.length, 0); assert.equal(T.signage_playlists.length, 0);
bad(await tool('undo_change', { activity_id: runActivity, confirm: true }), /already undone/, 'double undo refused');
T.signage_slots.push({ id: '20000000-0000-4000-8000-000000000001', organization_id: ORG, screen_id: SC1, playlist_id: 'x', days: [0], start_time: '08:00:00', end_time: '09:00:00', priority: 0, source: null });
bad(await tool('cancel_signage', { slot_id: '20000000-0000-4000-8000-000000000001' }), /regular slot made in the dashboard/, 'regular slot protected');

// ── kids ──
t = ok(await tool('save_kids_playlist', { organization_id: ORG, name: 'Sunday wk1', items: [{ type: 'countdown', until: '09:30' }, { type: 'video', media_id: VID }, { type: 'lyrics', song_id: SONG, show_title: true }] }), 'create kids playlist');
const PL = T.playlists[0].id;
assert.equal(T.playlists[0].items[2].title, 'Way Maker'); assert.equal(T.playlists[0].items[0].at_zero, 'hold');
bad(await tool('save_kids_playlist', { organization_id: ORG, name: 'x', items: [{ type: 'video', media_id: IMG1 }] }), /is image/, 'image as video refused');
t = ok(await tool('save_kids_playlist', { playlist_id: PL, items: [{ type: 'video', media_id: VID }] }), 'update kids playlist preview');
assert.match(t, /Before \(3\)/); assert.equal(T.playlists[0].items.length, 3);
ok(await tool('save_kids_playlist', { playlist_id: PL, items: [{ type: 'video', media_id: VID }], confirm: true }), 'update kids playlist confirm');
assert.equal(T.playlists[0].items.length, 1);
t = ok(await tool('schedule_kids', { location_id: KIDSROOM, playlist_ids: [PL], days: ['sun'], start: '09:00', end: '12:00', start_date: '2030-11-03', name: 'Sunday 9' }), 'schedule_kids preview');
assert.match(t, /Kids TV/);
t = ok(await tool('schedule_kids', { location_id: KIDSROOM, playlist_ids: [PL], days: ['sun'], start: '09:00', end: '12:00', start_date: '2030-11-03', name: 'Sunday 9', confirm: true }), 'schedule_kids confirm');
const SER = T.kids_series[0].id;
assert.deepEqual(T.kids_series[0].days, [0]);
ok(await tool('change_kids_schedule', { series_id: SER, on_date: '2030-11-10', action: 'skip', confirm: true }), 'skip a Sunday');
assert.equal(T.kids_series_exceptions.length, 1); assert.equal(T.kids_series_exceptions[0].action, 'skip');
bad(await tool('change_kids_schedule', { series_id: SER, on_date: '2030-11-11' }), /isn't one of/, 'non-Sunday refused');
t = ok(await tool('list_kids_schedule', { organization_id: ORG }), 'list_kids_schedule');
assert.match(t, /Sunday wk1 in Kids Room/);
ok(await tool('change_kids_schedule', { series_id: SER, confirm: true }), 'delete series');
assert.equal(T.kids_series.length, 0); assert.equal(T.kids_series_exceptions.length, 0);
const delAct = T.mcp_activity.at(-1).id;
ok(await tool('undo_change', { activity_id: delAct, confirm: true }), 'undo series delete');
assert.equal(T.kids_series.length, 1); assert.equal(T.kids_series_exceptions.length, 1);

// service guard: a window around now, today
const tor = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Toronto', hourCycle: 'h23', hour: '2-digit', minute: '2-digit', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date());
const P = Object.fromEntries(tor.map((x) => [x.type, x.value]));
const today = `${P.year}-${P.month}-${P.day}`, hh = +P.hour;
if (hh <= 21) { // a window starting this very minute
  bad(await tool('schedule_kids', { location_id: KIDSROOM, playlist_ids: [PL], date: today, start: `${P.hour}:${P.minute}`, end: `${String(hh + 2).padStart(2, '0')}:00` }), /within 30 minutes/, 'service guard');
}

// ── slides ──
t = ok(await tool('save_deck', { organization_id: ORG, name: 'Welcome', slides: [{ kind: 'text', title: 'Welcome!', body: 'Service at 10' }, { kind: 'song', song_id: SONG }, { kind: 'countdown', seconds: 300 }, { kind: 'blank' }] }), 'create deck');
const D = T.decks[0];
assert.equal(D.slides.length, 4); assert.ok(D.slides.every((s) => /^s_[a-z0-9]{5}$/.test(s.id))); assert.equal(new Set(D.slides.map((s) => s.id)).size, 4);
t = ok(await tool('schedule_slides', { location_id: LOBBY, deck_ids: [D.id], date: '2026-12-06', start: '09:30', end: '12:00', confirm: true }), 'schedule_slides one-off (EST)');
assert.equal(T.deck_schedules[0].starts_at, '2026-12-06T14:30:00.000Z');
ok(await tool('schedule_slides', { location_id: LOBBY, deck_ids: [D.id], date: '2027-07-04', start: '09:30', end: '12:00', confirm: true }), 'schedule_slides one-off (EDT)');
assert.equal(T.deck_schedules[1].starts_at, '2027-07-04T13:30:00.000Z');
t = ok(await tool('list_slides_schedule', { organization_id: ORG, days_ahead: 120 }), 'list_slides_schedule');
t = ok(await tool('schedule_slides', { location_id: KIDSROOM, deck_ids: [D.id], date: '2026-12-06', start: '09:30', end: '12:00' }), 'slides on old app warns');
assert.match(t, /Slides needs 1.4.0/);
t = ok(await tool('search_songs', { organization_id: ORG, query: 'way' }), 'search_songs');
assert.match(t, /Way Maker/);

// ── control ──
ok(await tool('play_now', { screen_id: SC1, deck_id: D.id }), 'play_now preview');
assert.ok(!calls.some((c) => c.rpc === 'send_screen_command'));
ok(await tool('play_now', { screen_id: SC1, deck_id: D.id, confirm: true }), 'play_now confirm');
assert.ok(calls.some((c) => c.rpc === 'send_screen_command' && c.args.p_command === 'start'));
ok(await tool('set_screen_module', { screen_ids: [SCK], module: 'signage', days: 'weekdays', start: '09:00', end: '17:00', confirm: true }), 'set_screen_module');
assert.equal(T.screen_schedules.length, 1);
t = ok(await tool('list_screen_rules', { screen_id: SCK }), 'list_screen_rules');
t = ok(await tool('list_activity', { organization_id: ORG }), 'list_activity');
assert.match(t, /UNDONE/);

// ── getting files in ──
const JPG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0]);
const MP4 = new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d]);
const seen = [];
globalThis.fetch = async (url) => {
  url = String(url); seen.push(url);
  if (url.includes('redirect-to-private')) return new Response(null, { status: 302, headers: { location: 'https://10.0.0.5/x.png' } });
  if (url.includes('webpage')) return new Response('<html>', { status: 200, headers: { 'content-type': 'text/html' } });
  if (url.includes('.mp4')) return new Response(MP4, { status: 200 });
  return new Response(JPG, { status: 200 });
};
t = ok(await tool('upload_from_url', { organization_id: ORG, title: 'Canva promo', url: 'https://export-download.canva.com/abc/design.png?sig=1' }), 'upload_from_url (Canva link)');
assert.equal(T.media.at(-1).kind, 'image');
ok(await tool('upload_from_url', { organization_id: ORG, title: 'Drive pic', url: 'https://drive.google.com/file/d/1AbC-dEf/view?usp=sharing' }), 'upload_from_url (Drive share link)');
assert.match(seen.at(-1), /drive\.usercontent\.google\.com\/download\?id=1AbC-dEf/);
ok(await tool('upload_from_url', { organization_id: ORG, title: 'Dropbox clip', url: 'https://www.dropbox.com/s/xyz/clip.mp4?dl=0' }), 'upload_from_url (Dropbox video)');
assert.match(seen.at(-1), /raw=1/); assert.equal(T.media.at(-1).kind, 'video');
bad(await tool('upload_from_url', { organization_id: ORG, title: 'x', url: 'https://example.com/redirect-to-private' }), /public https/, 'redirect to private address refused');
bad(await tool('upload_from_url', { organization_id: ORG, title: 'x', url: 'https://example.com/webpage' }), /web page, not the file/, 'web page explained');
bad(await tool('upload_from_url', { organization_id: ORG, title: 'x', url: 'http://example.com/a.png' }), /public https/, 'http refused');

t = ok(await tool('create_upload_url', { organization_id: ORG, title: 'Disk poster', filename: 'poster.png' }), 'create_upload_url');
assert.match(t, /curl -sS -X PUT -H "Content-Type: image\/png"/);
const sid = /upload_id ([0-9a-f-]{36})/.exec(t)[1];
assert.match(ok(await tool('check_upload', { upload_id: sid }), 'check_upload before PUT'), /hasn't arrived/);
T.__files.push({ path: T.mcp_upload_requests.find((r) => r.id === sid).storage_path, mimetype: 'image/png', size: 1234 }); // the PUT landing
t = ok(await tool('check_upload', { upload_id: sid }), 'check_upload after PUT');
assert.equal(T.media.at(-1).title, 'Disk poster'); assert.equal(T.media.at(-1).size_bytes, 1234);
assert.match(ok(await tool('check_upload', { upload_id: sid }), 'check_upload again (idempotent)'), new RegExp(T.media.at(-1).id));
bad(await tool('create_upload_url', { organization_id: ORG, title: 'x', filename: 'evil.exe' }), /filename must end/, 'bad extension refused');

// upload & schedule in one step
const nMediaBefore = T.media.length, nSlotsBefore = T.signage_slots.length;
t = ok(await tool('schedule_signage', { screen_ids: [SC1], upload: { title: 'Fall promo', files: 2 }, days: 'weekdays', start: '09:00', end: '18:00', seconds: 10 }), 'schedule_signage with upload');
assert.match(t, /NOTHING IS SCHEDULED YET/); assert.match(t, /upload\?request=/); assert.match(t, /Monday–Friday/);
assert.equal(T.signage_slots.length, nSlotsBefore); assert.equal(T.media.length, nMediaBefore);
const reqRow = T.mcp_upload_requests.at(-1);
assert.equal(reqRow.plan.files, 2); assert.equal(reqRow.plan.start, '09:00'); assert.ok(!('upload' in reqRow.plan)); assert.match(reqRow.summary, /Lobby TV/);
// what the page does after uploading two files:
const { files: _f, ...plan } = reqRow.plan;
t = ok(await tool('schedule_signage', { ...plan, items: [{ media_id: IMG1 }, { media_id: IMG2 }], confirm: true }), 'page confirms the plan');
assert.equal(T.signage_slots.length, nSlotsBefore + 1); assert.equal(T.signage_playlists.at(-1).items.length, 2);
bad(await tool('schedule_signage', { screen_ids: [SC1], upload: { title: 'x' }, items: [{ media_id: IMG1 }], date: '2030-11-01', start: '09:00', end: '10:00' }), /not several/, 'upload + items refused');

t = ok(await tool('list_targets', {}), 'list_targets shows unassigned screens');
assert.match(t, /not in a room[\s\S]*Loose TV/);


// ── folders ──
const kidsFolder = () => T.content_folders.find((f) => f.module === 'kids' && f.system === 'assistant');
t = ok(await tool('save_kids_playlist', { organization_id: ORG, name: 'Assistant made', items: [] }), 'kids playlist goes to assistant folder');
const AM = T.playlists.at(-1);
assert.ok(kidsFolder()); assert.equal(AM.folder_id, kidsFolder().id); assert.equal(AM.source, 'mcp');
assert.equal(T.signage_playlists.at(-1).folder_id, T.content_folders.find((f) => f.module === 'signage' && f.system === 'assistant').id, 'signage playlist filed');
t = ok(await tool('organize_content', { module: 'kids', ids: [AM.id], new_folder_name: 'Fall series' }), 'organize into a new folder');
const fall = T.content_folders.find((f) => f.name === 'Fall series');
assert.ok(fall); assert.equal(T.playlists.find((p) => p.id === AM.id).folder_id, fall.id);
t = ok(await tool('list_folders', { organization_id: ORG, module: 'kids' }), 'list_folders');
assert.match(t, /Fall series \(1\)/); assert.match(t, /Made by assistant \(1\)/); // "Sunday wk1" from earlier
t = ok(await tool('list_kids_playlists', { organization_id: ORG }), 'list shows folder path');
assert.match(t, /Assistant made .*\[Fall series\]/);
T.kids_series.push({ id: 'ks-x', organization_id: ORG, location_id: KIDSROOM, playlist_ids: [AM.id], days: [0], start_time: '09:00:00', end_time: '10:00:00', start_date: '2030-01-01', end_date: null });
bad(await tool('organize_content', { module: 'kids', ids: [AM.id], archive: true }), /Still in use/, 'archive refused while scheduled');
T.kids_series.pop();
ok(await tool('organize_content', { module: 'kids', ids: [AM.id], archive: true }), 'archive');
assert.ok(T.playlists.find((p) => p.id === AM.id).archived_at);
assert.doesNotMatch(ok(await tool('list_kids_playlists', { organization_id: ORG }), 'archived hidden'), /Assistant made/);
assert.match(ok(await tool('list_kids_playlists', { organization_id: ORG, include_archived: true }), 'include_archived'), /Assistant made .*ARCHIVED/);
const orgAct = T.mcp_activity.at(-1).id;
ok(await tool('undo_change', { activity_id: orgAct, confirm: true }), 'undo archive');
assert.ok(!T.playlists.find((p) => p.id === AM.id).archived_at);
t = ok(await tool('save_deck', { organization_id: ORG, name: 'Top deck', slides: [], folder_id: 'top' }), 'deck at top level when asked');
assert.equal(T.decks.at(-1).folder_id, null);

console.log('\nAll tests passed.');
