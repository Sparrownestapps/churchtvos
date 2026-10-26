// Minimal in-memory stand-in for supabase-js used by the MCP tools (no RLS; logic tests only).
export const T = {};
export const calls = [];
let seq = 1;
const uuid = () => `00000000-0000-4000-8000-${String(seq++).padStart(12, '0')}`;

function cmp(row, col, op, val) {
  const v = row[col];
  switch (op) {
    case 'eq': return String(v) === String(val);
    case 'neq': return String(v) !== String(val);
    case 'lt': return v != null && v < val;
    case 'gt': return v != null && v > val;
    case 'is': return val === null || val === 'null' ? v == null : v === val;
    case 'in': return val.map(String).includes(String(v));
    case 'ilike': {
      const re = new RegExp('^' + String(val).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*') + '$', 'i');
      return v != null && re.test(v);
    }
  }
  throw new Error('op ' + op);
}
function parseOr(s) {
  return s.split(',').map((p) => {
    const [col, op, ...rest] = p.split('.');
    return [col, op, rest.join('.')];
  });
}

class Q {
  constructor(table) { this.table = table; this.f = []; this.mode = 'select'; this.ret = false; this.one = null; this.lim = null; this.ord = null; this.head = false; }
  select(_c, o) { if (this.mode !== 'select') this.ret = true; if (o?.head) { this.head = true; this.countMode = true; } return this; }
  insert(rows) { this.mode = 'insert'; this.rows = Array.isArray(rows) ? rows : [rows]; return this; }
  update(p) { this.mode = 'update'; this.patch = p; return this; }
  delete() { this.mode = 'delete'; return this; }
  eq(c, v) { this.f.push((r) => cmp(r, c, 'eq', v)); return this; }
  lt(c, v) { this.f.push((r) => cmp(r, c, 'lt', v)); return this; }
  gt(c, v) { this.f.push((r) => cmp(r, c, 'gt', v)); return this; }
  in(c, v) { this.f.push((r) => cmp(r, c, 'in', v)); return this; }
  is(c, v) { this.f.push((r) => cmp(r, c, 'is', v)); return this; }
  ilike(c, v) { this.f.push((r) => cmp(r, c, 'ilike', v)); return this; }
  not(c, op, v) { this.f.push((r) => !cmp(r, c, op, v)); return this; }
  or(s) { const parts = parseOr(s); this.f.push((r) => parts.some(([c, op, v]) => cmp(r, c, op, v))); return this; }
  order(c, o) { this.ord = [c, o?.ascending !== false]; return this; }
  limit(n) { this.lim = n; return this; }
  maybeSingle() { this.one = 'maybe'; return this; }
  single() { this.one = 'single'; return this; }
  run() {
    const rows = (T[this.table] ??= []);
    calls.push({ table: this.table, mode: this.mode });
    if (this.mode === 'insert') {
      const out = this.rows.map((r) => {
        const row = { id: r.id ?? uuid(), created_at: new Date().toISOString(), ...r };
        if (this.table.endsWith('_exceptions')) delete row.id;
        if (this.table === 'mcp_activity') row.id = seq++;
        if (this.table === 'signage_slots' && row.end_time <= row.start_time) return { error: 'check' };
        rows.push(row);
        return row;
      });
      if (out.some((o) => o.error)) return { data: null, error: { message: 'violates check constraint' } };
      return this.fin(out.map((o) => ({ ...o })));
    }
    let hit = rows.filter((r) => this.f.every((f) => f(r)));
    if (this.mode === 'update') { hit.forEach((r) => Object.assign(r, this.patch)); return this.fin(hit.map((r) => ({ ...r }))); }
    if (this.mode === 'delete') { T[this.table] = rows.filter((r) => !hit.includes(r)); return this.fin(hit); }
    if (this.ord) { const [c, asc] = this.ord; hit = [...hit].sort((a, b) => (a[c] > b[c] ? 1 : a[c] < b[c] ? -1 : 0) * (asc ? 1 : -1)); }
    if (this.lim) hit = hit.slice(0, this.lim);
    if (this.countMode) return { data: null, count: hit.length, error: null };
    return this.fin(hit.map((r) => ({ ...r })));
  }
  fin(data) {
    if (this.one === 'single') return data.length === 1 ? { data: data[0], error: null } : { data: null, error: { message: 'not single' } };
    if (this.one === 'maybe') return { data: data[0] ?? null, error: null };
    return { data, error: null };
  }
  then(res, rej) { try { res(this.run()); } catch (e) { rej(e); } }
}

export function createClient() {
  return {
    auth: { getUser: async (t) => (t === 'good' ? { data: { user: { id: 'user-1' } }, error: null } : { data: { user: null }, error: { message: 'bad' } }) },
    from: (t) => new Q(t),
    rpc: async (name, args) => { calls.push({ rpc: name, args }); return { data: name.endsWith('occurrences') ? (T['__occ'] ?? []) : 1, error: null }; },
    storage: {
      from: () => ({
        upload: async (path, bytes) => { (T.__files ??= []).push(path); return { data: { path }, error: null }; },
        getPublicUrl: (p) => ({ data: { publicUrl: `https://cdn/${p}` } }),
        remove: async () => ({ data: null, error: null }),
      }),
    },
  };
}
