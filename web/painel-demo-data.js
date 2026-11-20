/* Modo demonstração do painel: imita o cliente do Supabase com dados fictícios em memória.
   Só é usado quando SUPABASE_URL ainda está com o valor de exemplo. Pode apagar este arquivo em produção. */
window.makeMock = function(){
  let seed = 7;
  const rnd = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  const pick = a => a[Math.floor(rnd() * a.length)];
  const wpick = (items, w) => { const tot = items.reduce((a, x) => a + w(x), 0); let r = rnd() * tot; for (const x of items) { r -= w(x); if (r < 0) return x; } return items[items.length - 1]; };
  let idc = 1; const uid = () => 'demo-' + (idc++).toString(36).padStart(5, '0');
  const now = Date.now(), DAY = 864e5;

  const NB = ['Centro', 'Bela Vista', 'Nova Santa Cruz', 'São Cristóvão', 'Malaquias Cardoso', 'Santa Terezinha'];
  const DB = {
    settings: [{ id: 1, campaign_name: 'Roleta Achei no Pão', active: true, starts_at: new Date(now - 45 * DAY).toISOString(), ends_at: null,
      spins_per_period: 1, period: 'day', max_spins_device_day: 3, max_phones_per_device: 2, max_spins_ip_hour: 30,
      lose_weight: 120, lose_label: 'Não foi dessa vez', lose_slices: 3, prize_valid_days: 7, require_otp: true, trusted_device_days: 30,
      rules_text: 'Válido para clientes das padarias parceiras. 1 giro por dia por WhatsApp. Prêmios sujeitos à disponibilidade. Apresente o código no anunciante dentro da validade.',
      timezone: 'America/Recife', neighborhoods: NB.slice() }],
    advertisers: [], bakeries: [], prizes: [], players: [], spins: [], claims: [], waitlist: []
  };

  [['Açaí da Praça', 'Açaíteria', '#6B2C91', 1], ['Ótica Visão', 'Ótica', '#1F6FB2', 1], ['Studio Bella', 'Salão de beleza', '#D14D8A', 1],
   ['Pizzaria Forno', 'Pizzaria', '#E07A1F', 1], ['Farmácia Vida', 'Farmácia', '#2E8B57', 1], ['Barbearia Navalha', 'Barbearia', '#3A3A3A', 0]]
    .forEach(([name, segment, color, pin]) => DB.advertisers.push({ id: uid(), name, segment, contact: '(81) 9 9' + Math.floor(rnd() * 900 + 100) + '-' + Math.floor(rnd() * 9000 + 1000), color, active: true, redeem_pin_hash: pin ? 'x' : null, created_at: new Date(now - 50 * DAY).toISOString() }));
  const A = n => DB.advertisers.find(a => a.name === n).id;
  [['Açaí 300ml', 'Açaí da Praça', 14, 250, 8, 'Com 2 complementos'], ['10% em óculos', 'Ótica Visão', 10, null, null, 'Armações e lentes'],
   ['Escova grátis', 'Studio Bella', 6, 60, 3, 'Agendar pelo WhatsApp'], ['Pizza broto', 'Pizzaria Forno', 8, 200, 5, 'Sabores tradicionais, retirada no balcão'],
   ['R$ 10 em compras', 'Farmácia Vida', 9, 300, null, 'Acima de R$ 40, exceto medicamentos controlados'], ['Corte com 50%', 'Barbearia Navalha', 5, 100, 3, null],
   ['Desconto 15% no açaí', 'Açaí da Praça', 12, null, null, null]]
    .forEach(([name, adv, weight, stock_total, daily_cap, description]) => DB.prizes.push({ id: uid(), advertiser_id: A(adv), name, description, color: null, weight, stock_total, stock_used: 0, daily_cap, active: true, created_at: new Date(now - 45 * DAY).toISOString() }));
  [['Padaria São José', 'sao-jose', 'Centro', 1.6], ['Panificadora Pão Quente', 'pao-quente', 'Bela Vista', 1.2], ['Padaria Estrela', 'estrela', 'Nova Santa Cruz', 1],
   ['Padaria Doce Lar', 'doce-lar', 'São Cristóvão', .7], ['Pão & Cia', 'pao-e-cia', 'Santa Terezinha', .5]]
    .forEach(([name, slug, neighborhood, w]) => DB.bakeries.push({ id: uid(), name, slug, neighborhood, active: true, _w: w, created_at: new Date(now - 45 * DAY).toISOString() }));

  const FN = ['Maria', 'José', 'Ana', 'João', 'Francisca', 'Antônio', 'Juliana', 'Carlos', 'Patrícia', 'Paulo', 'Aline', 'Lucas', 'Fernanda', 'Rafael', 'Camila', 'Bruno', 'Larissa', 'Pedro', 'Débora', 'Thiago', 'Rita', 'Severino', 'Gabriela', 'Edson'];
  const LN = ['Silva', 'Santos', 'Oliveira', 'Souza', 'Lima', 'Pereira', 'Costa', 'Ferreira', 'Almeida', 'Barbosa', 'Araújo', 'Nascimento'];
  const nbW = { 'Centro': 5, 'Bela Vista': 3, 'Nova Santa Cruz': 3, 'São Cristóvão': 2, 'Malaquias Cardoso': 1.5, 'Santa Terezinha': 1.5 };
  for (let i = 0; i < 360; i++) {
    const created = now - Math.floor(rnd() * 44 * DAY);
    DB.players.push({ id: uid(), name: pick(FN) + ' ' + pick(LN), phone: '55819' + String(Math.floor(rnd() * 1e8)).padStart(8, '0'),
      neighborhood: rnd() < .06 ? 'Vila Nova' : wpick(NB, n => nbW[n]), verified_at: new Date(created).toISOString(), blocked: false,
      created_at: new Date(created).toISOString(), _dev: Math.random().toString(36).slice(2, 12), _ip: Math.random().toString(36).slice(2, 12), _act: .2 + rnd() });
  }
  DB.players[3].blocked = true;
  const shared = DB.players.slice(10, 13); shared.forEach(p => p._dev = 'a9f3c1e7b2');   // um aparelho com 3 números

  const hourW = h => [0, 0, 0, 0, 0, .5, 4, 6, 5, 3, 2, 2, 2, 1.5, 1.5, 2, 3, 4.5, 4, 3, 2, 1, .5, .2][h];
  const tzDay = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Recife' });
  const tzHour = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Recife', hour: 'numeric', hourCycle: 'h23' });
  let code = 0;
  for (let d = 44; d >= 0; d--) {
    const base = 18 + (44 - d) * 1.4, dow = new Date(now - d * DAY).getDay();
    const count = Math.round(base * (dow === 0 || dow === 6 ? 1.35 : 1) * (.8 + rnd() * .4)) - (d === 0 ? Math.round(base * .4) : 0);
    const dayStart = new Date(tzDay.format(new Date(now - d * DAY)) + 'T00:00:00-03:00').getTime();
    const usedToday = new Set();
    for (let i = 0; i < count; i++) {
      const pl = wpick(DB.players.filter(p => !p.blocked && new Date(p.created_at).getTime() <= dayStart + DAY && !usedToday.has(p.id)), p => p._act);
      if (!pl) break; usedToday.add(pl.id);
      const h = wpick([...Array(24).keys()], hourW);
      let t = dayStart + h * 36e5 + Math.floor(rnd() * 36e5); if (t > now) t = now - Math.floor(rnd() * 36e5);
      const bk = wpick(DB.bakeries, b => b._w);
      const pool = DB.prizes.filter(p => p.stock_total == null || p.stock_used < p.stock_total);
      const tot = pool.reduce((a, p) => a + p.weight, 0) + 120;
      let r = rnd() * tot, prize = null; for (const p of pool) { r -= p.weight; if (r < 0) { prize = p; break; } }
      const spin = { id: DB.spins.length + 1, player_id: pl.id, bakery_id: bk.id, prize_id: prize?.id || null, won: !!prize, device_id: pl._dev, ip_hash: pl._ip, created_at: new Date(t).toISOString() };
      DB.spins.push(spin);
      if (prize) {
        prize.stock_used++;
        const exp = dayStart + 8 * DAY;
        const redeemed = (now - t > DAY) && rnd() < .62 ? new Date(Math.min(now, t + rnd() * 5 * DAY)).toISOString() : null;
        DB.claims.push({ id: uid(), spin_id: spin.id, prize_id: prize.id, advertiser_id: prize.advertiser_id, player_id: pl.id,
          code: 'AP-' + (code++).toString(36).toUpperCase().padStart(3, '0') + 'K7' + 'ABCDEFGHJK'[code % 10] + 'Q',
          prize_name: prize.name, expires_at: new Date(exp).toISOString(), redeemed_at: redeemed && redeemed < new Date(exp).toISOString() ? redeemed : null,
          redeemed_by: redeemed ? (rnd() < .9 ? 'anunciante' : 'painel') : null, created_at: spin.created_at });
      }
    }
  }

  for (let i = 0; i < 24; i++) {
    const created = now - Math.floor(rnd() * 6 * DAY);
    DB.waitlist.push({ id: uid(), name: pick(FN) + ' ' + pick(LN), phone: '55819' + String(Math.floor(rnd() * 1e8)).padStart(8, '0'),
      neighborhood: wpick(NB, n => nbW[n]), bakery_id: DB.bakeries.length ? pick(DB.bakeries).id : null,
      created_at: new Date(created).toISOString(), notified_at: i % 5 === 0 ? new Date(created + DAY).toISOString() : null });
  }

  const byId = (t, id) => DB[t].find(x => x.id === id);
  const count = (t, k, v) => DB[t].reduce((a, x) => a + (x[k] === v ? 1 : 0), 0);
  function enrich(t, r) {
    const o = { ...r };
    if (t === 'prizes') { const a = byId('advertisers', r.advertiser_id); o.advertisers = a && { name: a.name, color: a.color, active: a.active }; }
    if (t === 'advertisers') { o.prizes = [{ count: count('prizes', 'advertiser_id', r.id) }]; o.claims = [{ count: count('claims', 'advertiser_id', r.id) }]; }
    if (t === 'waitlist') { const b = byId('bakeries', r.bakery_id); o.bakeries = b && { name: b.name, slug: b.slug }; }
    if (t === 'bakeries') o.spins = [{ count: count('spins', 'bakery_id', r.id) }];
    if (t === 'players') { o.spins = [{ count: count('spins', 'player_id', r.id) }]; o.claims = [{ count: count('claims', 'player_id', r.id) }]; }
    if (t === 'claims') {
      const a = byId('advertisers', r.advertiser_id), p = byId('players', r.player_id), sp = DB.spins.find(s => s.id === r.spin_id), b = sp && byId('bakeries', sp.bakery_id);
      o.advertisers = a && { name: a.name }; o.players = p && { name: p.name, phone: p.phone, neighborhood: p.neighborhood }; o.spins = { bakeries: b && { name: b.name } };
    }
    return o;
  }

  class Q {
    constructor(t) { this.t = t; this.f = []; this.op = 'select'; }
    select() { return this; }
    insert(v) { this.op = 'insert'; this.v = v; return this; }
    update(v) { this.op = 'update'; this.v = v; return this; }
    delete() { this.op = 'delete'; return this; }
    eq(k, v) { this.f.push(r => String(r[k]) === String(v)); return this; }
    is(k) { this.f.push(r => r[k] == null); return this; }
    not(k) { this.f.push(r => r[k] != null); return this; }
    gt(k, v) { this.f.push(r => r[k] > v); return this; }
    lt(k, v) { this.f.push(r => r[k] < v); return this; }
    ilike(k, pat) { const p = pat.replace(/%/g, '').toLowerCase(); this.f.push(r => String(r[k] ?? '').toLowerCase().includes(p)); return this; }
    order(k, o = {}) { this.ord = [k, o.ascending !== false]; return this; }
    limit(n) { this.lim = n; return this; }
    single() { this.one = true; return this; }
    then(res, rej) { return new Promise(r => setTimeout(r, 120)).then(() => this.run()).then(res, rej); }
    run() {
      const T = DB[this.t]; const match = r => this.f.every(fn => fn(r));
      if (this.op === 'insert') {
        const row = { id: uid(), created_at: new Date().toISOString(), active: true, stock_used: 0, ...this.v };
        if (this.t === 'bakeries' && T.some(b => b.slug === row.slug)) return { data: null, error: { message: 'Já existe uma padaria com esse código no link.' } };
        T.push(row); return { data: this.one ? enrich(this.t, row) : [enrich(this.t, row)], error: null };
      }
      if (this.op === 'update') { T.filter(match).forEach(r => Object.assign(r, this.v)); return { data: null, error: null }; }
      if (this.op === 'delete') {
        const del = T.filter(match).map(r => r.id); DB[this.t] = T.filter(r => !del.includes(r.id));
        if (this.t === 'advertisers') DB.prizes = DB.prizes.filter(p => !del.includes(p.advertiser_id));
        return { data: null, error: null };
      }
      let rows = T.filter(match);
      if (this.ord) { const [k, asc] = this.ord; rows = rows.slice().sort((a, b) => (a[k] > b[k] ? 1 : a[k] < b[k] ? -1 : 0) * (asc ? 1 : -1)); }
      if (this.lim) rows = rows.slice(0, this.lim);
      rows = rows.map(r => enrich(this.t, r));
      return { data: this.one ? rows[0] : rows, error: null };
    }
  }

  function dashboard(days) {
    const from = new Date(now - days * DAY).toISOString(), today = tzDay.format(new Date());
    const sp = DB.spins.filter(s => s.created_at >= from), cl = DB.claims.filter(c => c.created_at >= from);
    const group = (arr, key, f) => { const m = new Map(); arr.forEach(x => { const k = key(x); if (!m.has(k)) m.set(k, []); m.get(k).push(x); }); return [...m].map(([k, v]) => f(k, v)); };
    const uniq = a => new Set(a).size;
    return {
      spins: sp.length, players: uniq(sp.map(s => s.player_id)), new_players: DB.players.filter(p => p.created_at >= from).length,
      won: cl.length, redeemed: cl.filter(c => c.redeemed_at).length,
      today: DB.spins.filter(s => tzDay.format(new Date(s.created_at)) === today).length,
      by_day: group(sp, s => tzDay.format(new Date(s.created_at)), (day, v) => ({ day, spins: v.length, won: v.filter(s => s.won).length })),
      by_bakery: group(sp, s => byId('bakeries', s.bakery_id)?.name || '—', (name, v) => ({ name, spins: v.length, players: uniq(v.map(s => s.player_id)) })).sort((a, b) => b.spins - a.spins),
      by_advertiser: group(cl, c => byId('advertisers', c.advertiser_id)?.name || '—', (name, v) => ({ name, won: v.length, redeemed: v.filter(c => c.redeemed_at).length })).sort((a, b) => b.won - a.won),
      by_neighborhood: group(sp, s => byId('players', s.player_id)?.neighborhood || 'Não informado', (name, v) => ({ name, players: uniq(v.map(s => s.player_id)), spins: v.length })).sort((a, b) => b.players - a.players),
      by_hour: group(sp, s => +tzHour.format(new Date(s.created_at)), (h, v) => ({ h, n: v.length })),
      suspicious_devices: group(sp, s => s.device_id, (device, v) => ({ device, phones: uniq(v.map(s => s.player_id)), spins: v.length })).filter(x => x.phones >= 2),
      suspicious_networks: []
    };
  }

  return {
    from: t => new Q(t),
    rpc: async (fn, args) => {
      await new Promise(r => setTimeout(r, 150));
      if (fn === 'is_admin') return { data: true, error: null };
      if (fn === 'dashboard') return { data: dashboard(args.p_days), error: null };
      if (fn === 'set_advertiser_pin') {
        if (!/^[0-9]{4,8}$/.test(args.p_pin)) return { data: null, error: { message: 'O PIN precisa ter de 4 a 8 números' } };
        byId('advertisers', args.p_id).redeem_pin_hash = 'x'; return { data: null, error: null };
      }
      return { data: null, error: { message: 'Indisponível na demonstração' } };
    },
    auth: { signOut: async () => {}, signInWithPassword: async () => ({ error: { message: 'demonstração' } }) }
  };
};
