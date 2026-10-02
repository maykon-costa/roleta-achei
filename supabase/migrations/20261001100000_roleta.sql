-- Roleta Achei no Pão — anti-fraude
-- Todo acesso público passa pela edge function "roleta" (service role).
-- As tabelas só são legíveis/editáveis por administradores.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- =========================================================
-- Administradores
-- =========================================================
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;

-- =========================================================
-- Configurações (linha única)
-- =========================================================
create table public.settings (
  id                     int primary key default 1 check (id = 1),
  campaign_name          text not null default 'Roleta Achei no Pão',
  active                 boolean not null default true,
  starts_at              timestamptz,
  ends_at                timestamptz,
  spins_per_period       int not null default 1 check (spins_per_period between 1 and 100),
  period                 text not null default 'day' check (period in ('day','week','month','campaign')),
  max_spins_device_day   int not null default 3 check (max_spins_device_day >= 1),
  max_phones_per_device  int not null default 2 check (max_phones_per_device >= 1),
  max_spins_ip_hour      int not null default 30 check (max_spins_ip_hour >= 1),
  lose_weight            int not null default 60 check (lose_weight >= 0),
  lose_label             text not null default 'Não foi dessa vez',
  lose_slices            int not null default 3 check (lose_slices between 0 and 8),
  prize_valid_days       int not null default 7 check (prize_valid_days between 1 and 90),
  require_otp            boolean not null default false,
  trusted_device_days    int not null default 30,
  rules_text             text not null default 'Válido para clientes das padarias parceiras. Prêmios sujeitos à disponibilidade. Apresente o código no anunciante dentro da validade.',
  timezone               text not null default 'America/Recife',
  neighborhoods          text[] not null default '{}',   -- lista sugerida de bairros (editável no painel)
  updated_at             timestamptz not null default now()
);
insert into public.settings default values;

-- =========================================================
-- Cadastros
-- =========================================================
create table public.advertisers (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  segment          text,
  contact          text,
  color            text not null default '#E8402B',
  redeem_pin_hash  text,
  active           boolean not null default true,
  created_at       timestamptz not null default now()
);

create table public.bakeries (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  neighborhood  text,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

create table public.prizes (
  id             uuid primary key default gen_random_uuid(),
  advertiser_id  uuid not null references public.advertisers(id) on delete cascade,
  name           text not null,
  description    text,
  color          text,
  weight         int not null default 10 check (weight >= 0),
  stock_total    int check (stock_total is null or stock_total >= 0),   -- null = ilimitado
  stock_used     int not null default 0,
  daily_cap      int check (daily_cap is null or daily_cap >= 0),       -- null = sem limite diário
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

-- =========================================================
-- Jogadores, giros, prêmios ganhos
-- =========================================================
create table public.players (
  id           uuid primary key default gen_random_uuid(),
  phone        text not null unique check (phone ~ '^55[1-9][0-9]9[0-9]{8}$'),
  name         text,
  neighborhood text,
  verified_at  timestamptz,
  blocked      boolean not null default false,
  created_at   timestamptz not null default now()
);

create table public.player_devices (
  player_id    uuid not null references public.players(id) on delete cascade,
  device_id    text not null,
  first_seen   timestamptz not null default now(),
  trusted_at   timestamptz,
  primary key (player_id, device_id)
);
create index player_devices_device_idx on public.player_devices (device_id);

create table public.spins (
  id          bigint generated always as identity primary key,
  player_id   uuid not null references public.players(id) on delete cascade,
  bakery_id   uuid references public.bakeries(id) on delete set null,
  prize_id    uuid references public.prizes(id) on delete set null,
  won         boolean not null,
  device_id   text,
  ip_hash     text,
  user_agent  text,
  created_at  timestamptz not null default now()
);
create index spins_player_idx on public.spins (player_id, created_at desc);
create index spins_device_idx on public.spins (device_id, created_at desc);
create index spins_ip_idx     on public.spins (ip_hash, created_at desc);
create index spins_time_idx   on public.spins (created_at desc);

create table public.claims (
  id             uuid primary key default gen_random_uuid(),
  spin_id        bigint not null unique references public.spins(id) on delete cascade,
  prize_id       uuid references public.prizes(id) on delete set null,
  advertiser_id  uuid references public.advertisers(id) on delete set null,
  player_id      uuid not null references public.players(id) on delete cascade,
  code           text not null unique,
  prize_name     text not null,     -- cópia, para o histórico não mudar se o prêmio for editado
  expires_at     timestamptz not null,
  redeemed_at    timestamptz,
  redeemed_by    text,              -- 'anunciante' ou 'painel'
  created_at     timestamptz not null default now()
);
create index claims_prize_day_idx on public.claims (prize_id, created_at);

create table public.otps (
  phone       text primary key,
  code_hash   text not null,
  expires_at  timestamptz not null,
  attempts    int not null default 0,
  sent_count  int not null default 1,
  window_start timestamptz not null default now()
);

create table public.redeem_failures (
  id         bigint generated always as identity primary key,
  ip_hash    text,
  created_at timestamptz not null default now()
);
create index redeem_failures_idx on public.redeem_failures (ip_hash, created_at desc);

-- =========================================================
-- RLS: tudo só para admin. Público só via edge function.
-- =========================================================
do $$
declare t text;
begin
  foreach t in array array['admins','settings','advertisers','bakeries','prizes','players','player_devices','spins','claims','otps','redeem_failures'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
  foreach t in array array['settings','advertisers','bakeries','prizes','players','claims'] loop
    execute format('create policy "admin total" on public.%I for all using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
  foreach t in array array['spins','player_devices'] loop
    execute format('create policy "admin lê" on public.%I for select using (public.is_admin())', t);
  end loop;
end $$;
create policy "admin vê admins" on public.admins for select using (public.is_admin());

-- =========================================================
-- Utilitários
-- =========================================================
create or replace function public._rand() returns double precision
language sql volatile set search_path = public, extensions as $$
  select ('x' || encode(gen_random_bytes(6), 'hex'))::bit(48)::bigint / 281474976710656.0
$$;

create or replace function public._code() returns text
language sql volatile set search_path = public, extensions as $$
  select 'AP-' || string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(b, i) % 32) + 1, 1), '')
  from (select gen_random_bytes(7) b) x, generate_series(0, 6) i
$$;

create or replace function public._period_start(p text, tz text, campaign_start timestamptz)
returns timestamptz language sql stable as $$
  select case p
    when 'day'   then date_trunc('day',   now() at time zone tz) at time zone tz
    when 'week'  then date_trunc('week',  now() at time zone tz) at time zone tz
    when 'month' then date_trunc('month', now() at time zone tz) at time zone tz
    else coalesce(campaign_start, '-infinity'::timestamptz)
  end
$$;

create or replace function public._period_end(p text, tz text) returns timestamptz
language sql stable as $$
  select case p
    when 'day'   then (date_trunc('day',   now() at time zone tz) + interval '1 day')   at time zone tz
    when 'week'  then (date_trunc('week',  now() at time zone tz) + interval '1 week')  at time zone tz
    when 'month' then (date_trunc('month', now() at time zone tz) + interval '1 month') at time zone tz
    else null
  end
$$;

-- =========================================================
-- Configuração pública da roleta (fatias)
-- =========================================================
create or replace function public.wheel_config(p_bakery text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare s settings; b bakeries; segs jsonb;
begin
  select * into s from settings where id = 1;
  select * into b from bakeries where slug = p_bakery and active;
  if b.id is null then return jsonb_build_object('error','padaria_invalida'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'key', p.id, 'label', p.name, 'advertiser', a.name,
           'color', coalesce(p.color, a.color)) order by p.created_at), '[]'::jsonb)
    into segs
  from prizes p join advertisers a on a.id = p.advertiser_id
  where p.active and a.active and p.weight > 0
    and (p.stock_total is null or p.stock_used < p.stock_total);

  return jsonb_build_object(
    'campaign', s.campaign_name,
    'open', s.active and (s.starts_at is null or now() >= s.starts_at) and (s.ends_at is null or now() < s.ends_at),
    'starts_at', s.starts_at, 'ends_at', s.ends_at,
    'bakery', b.name,
    'segments', segs,
    'lose_label', s.lose_label, 'lose_slices', s.lose_slices,
    'spins_per_period', s.spins_per_period, 'period', s.period,
    'require_otp', s.require_otp,
    'neighborhoods', s.neighborhoods,
    'rules', s.rules_text
  );
end $$;

-- =========================================================
-- OTP (código por WhatsApp)
-- =========================================================
create or replace function public.otp_issue(p_phone text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare code text := lpad(((public._rand() * 1000000)::int % 1000000)::text, 6, '0'); o otps;
begin
  select * into o from otps where phone = p_phone for update;
  if o.phone is not null and o.window_start > now() - interval '1 hour' and o.sent_count >= 4 then
    return jsonb_build_object('error','muitos_codigos');
  end if;
  if o.phone is not null and o.expires_at > now() + interval '9 minutes' then
    return jsonb_build_object('error','aguarde');  -- reenvio no máximo a cada 1 min
  end if;
  insert into otps (phone, code_hash, expires_at, attempts, sent_count, window_start)
  values (p_phone, crypt(code, gen_salt('bf', 6)), now() + interval '10 minutes', 0, 1, now())
  on conflict (phone) do update set
    code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0,
    sent_count = case when otps.window_start > now() - interval '1 hour' then otps.sent_count + 1 else 1 end,
    window_start = case when otps.window_start > now() - interval '1 hour' then otps.window_start else now() end;
  return jsonb_build_object('code', code);
end $$;

create or replace function public._otp_check(p_phone text, p_code text)
returns boolean language plpgsql volatile security definer set search_path = public, extensions as $$
declare o otps;
begin
  select * into o from otps where phone = p_phone for update;
  if o.phone is null or o.expires_at < now() or o.attempts >= 5 then return false; end if;
  if o.code_hash = crypt(p_code, o.code_hash) then
    delete from otps where phone = p_phone; return true;
  end if;
  update otps set attempts = attempts + 1 where phone = p_phone;
  return false;
end $$;

-- =========================================================
-- GIRO — tudo atômico, com trava no jogador e no prêmio
-- =========================================================
create or replace function public.do_spin(
  p_phone text, p_name text, p_bakery text, p_device text, p_ip_hash text, p_ua text, p_otp text default null,
  p_neighborhood text default null
) returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  s settings; b bakeries; pl players; pr record;
  v_start timestamptz; v_used int; v_dev int; v_ip int; v_phones int;
  v_trusted boolean; v_total numeric; v_r numeric; v_acc numeric := 0;
  v_prize uuid; v_spin bigint; v_code text; v_exp timestamptz; v_adv text; v_desc text; v_pname text;
  v_today timestamptz; v_nb text;
begin
  select * into s from settings where id = 1;
  if not s.active or (s.starts_at is not null and now() < s.starts_at) or (s.ends_at is not null and now() >= s.ends_at) then
    return jsonb_build_object('error','campanha_fechada');
  end if;

  select * into b from bakeries where slug = p_bakery and active;
  if b.id is null then return jsonb_build_object('error','padaria_invalida'); end if;
  if coalesce(length(p_device), 0) < 16 then return jsonb_build_object('error','aparelho_invalido'); end if;

  -- Limite por rede (IP) por hora
  select count(*) into v_ip from spins where ip_hash = p_ip_hash and created_at > now() - interval '1 hour';
  if v_ip >= s.max_spins_ip_hour then return jsonb_build_object('error','limite_rede'); end if;

  -- Jogador: cria ou reaproveita, e TRAVA a linha (dois giros simultâneos do mesmo número esperam um ao outro)
  -- Bairro: usa a grafia da lista oficial se bater; senão padroniza ("vila nova" -> "Vila Nova")
  v_nb := nullif(left(regexp_replace(trim(coalesce(p_neighborhood, '')), '\s+', ' ', 'g'), 60), '');
  if v_nb is not null then
    v_nb := coalesce((select n from unnest(s.neighborhoods) n where lower(n) = lower(v_nb) limit 1), initcap(v_nb));
  end if;

  insert into players (phone, name, neighborhood) values (p_phone, nullif(trim(p_name), ''), v_nb)
  on conflict (phone) do update set
    name = coalesce(nullif(trim(excluded.name), ''), players.name),
    neighborhood = coalesce(excluded.neighborhood, players.neighborhood);
  select * into pl from players where phone = p_phone for update;
  if pl.blocked then return jsonb_build_object('error','bloqueado'); end if;

  -- Telefones distintos neste aparelho (barra quem troca de número para jogar de novo)
  select count(distinct player_id) into v_phones from player_devices
   where device_id = p_device and player_id <> pl.id and first_seen > now() - interval '30 days';
  if v_phones >= s.max_phones_per_device then return jsonb_build_object('error','aparelho_com_muitos_numeros'); end if;

  -- Verificação por WhatsApp (se exigida), com aparelho confiável por N dias
  select (trusted_at is not null and trusted_at > now() - make_interval(days => s.trusted_device_days)) into v_trusted
    from player_devices where player_id = pl.id and device_id = p_device;
  if s.require_otp and not coalesce(v_trusted, false) then
    if p_otp is null then return jsonb_build_object('error','otp_necessario'); end if;
    if not public._otp_check(p_phone, p_otp) then return jsonb_build_object('error','otp_invalido'); end if;
    update players set verified_at = now() where id = pl.id;
    v_trusted := true;
  end if;

  insert into player_devices (player_id, device_id, trusted_at)
  values (pl.id, p_device, case when v_trusted then now() end)
  on conflict (player_id, device_id) do update set trusted_at = coalesce(case when v_trusted then now() end, player_devices.trusted_at);

  -- Limite por telefone no período
  v_start := public._period_start(s.period, s.timezone, s.starts_at);
  select count(*) into v_used from spins where player_id = pl.id and created_at >= v_start;
  if v_used >= s.spins_per_period then
    return jsonb_build_object('error','limite', 'next_at', public._period_end(s.period, s.timezone));
  end if;

  -- Limite por aparelho por dia
  v_today := public._period_start('day', s.timezone, null);
  select count(*) into v_dev from spins where device_id = p_device and created_at >= v_today;
  if v_dev >= s.max_spins_device_day then return jsonb_build_object('error','limite_aparelho'); end if;

  -- Sorteio ponderado, só entre prêmios com estoque e dentro do limite diário
  create temporary table if not exists _cand (id uuid, weight int) on commit drop;
  truncate _cand;
  insert into _cand
  select p.id, p.weight from prizes p join advertisers a on a.id = p.advertiser_id
  where p.active and a.active and p.weight > 0
    and (p.stock_total is null or p.stock_used < p.stock_total)
    and (p.daily_cap is null or (select count(*) from claims c where c.prize_id = p.id and c.created_at >= v_today) < p.daily_cap);

  select coalesce(sum(weight), 0) + s.lose_weight into v_total from _cand;
  if v_total > 0 then
    v_r := public._rand() * v_total;
    for pr in select * from _cand order by id loop
      v_acc := v_acc + pr.weight;
      if v_r < v_acc then v_prize := pr.id; exit; end if;
    end loop;
  end if;

  -- Baixa de estoque com trava (se esgotou no meio do caminho, vira "não foi dessa vez")
  if v_prize is not null then
    update prizes set stock_used = stock_used + 1
     where id = v_prize and (stock_total is null or stock_used < stock_total)
     returning name, description into v_pname, v_desc;
    if not found then v_prize := null; end if;
  end if;

  insert into spins (player_id, bakery_id, prize_id, won, device_id, ip_hash, user_agent)
  values (pl.id, b.id, v_prize, v_prize is not null, p_device, p_ip_hash, left(p_ua, 300))
  returning id into v_spin;

  if v_prize is not null then
    select a.name into v_adv from prizes p join advertisers a on a.id = p.advertiser_id where p.id = v_prize;
    v_exp := (date_trunc('day', now() at time zone s.timezone) + make_interval(days => s.prize_valid_days + 1)) at time zone s.timezone;
    loop
      begin
        v_code := public._code();
        insert into claims (spin_id, prize_id, advertiser_id, player_id, code, prize_name, expires_at)
        select v_spin, v_prize, p.advertiser_id, pl.id, v_code, v_pname, v_exp from prizes p where p.id = v_prize;
        exit;
      exception when unique_violation then -- código repetido: tenta outro
      end;
    end loop;
  end if;

  return jsonb_build_object(
    'won', v_prize is not null,
    'key', coalesce(v_prize::text, 'lose'),
    'prize', v_pname, 'description', v_desc, 'advertiser', v_adv,
    'code', v_code, 'expires_at', v_exp,
    'remaining', s.spins_per_period - v_used - 1,
    'next_at', public._period_end(s.period, s.timezone)
  );
end $$;

-- =========================================================
-- RESGATE no anunciante (código + PIN do anunciante)
-- =========================================================
create or replace function public.redeem(p_code text, p_pin text, p_ip_hash text, p_confirm boolean)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare c claims; a advertisers; pl players; v_fails int;
begin
  select count(*) into v_fails from redeem_failures where ip_hash = p_ip_hash and created_at > now() - interval '1 hour';
  if v_fails >= 10 then return jsonb_build_object('error','muitas_tentativas'); end if;

  select * into c from claims where code = upper(trim(p_code)) for update;
  if c.id is not null then select * into a from advertisers where id = c.advertiser_id; end if;

  if c.id is null or a.redeem_pin_hash is null or a.redeem_pin_hash <> crypt(p_pin, a.redeem_pin_hash) then
    insert into redeem_failures (ip_hash) values (p_ip_hash);
    return jsonb_build_object('error','codigo_ou_pin_invalido');
  end if;

  select * into pl from players where id = c.player_id;
  if c.redeemed_at is not null then
    return jsonb_build_object('error','ja_resgatado', 'redeemed_at', c.redeemed_at, 'prize', c.prize_name);
  end if;
  if c.expires_at < now() then
    return jsonb_build_object('error','expirado', 'expires_at', c.expires_at, 'prize', c.prize_name);
  end if;

  if p_confirm then
    update claims set redeemed_at = now(), redeemed_by = 'anunciante' where id = c.id;
  end if;

  return jsonb_build_object(
    'ok', true, 'redeemed', p_confirm,
    'prize', c.prize_name, 'advertiser', a.name,
    'player', coalesce(pl.name, 'Cliente'), 'phone_end', right(pl.phone, 4),
    'won_at', c.created_at, 'expires_at', c.expires_at
  );
end $$;

-- =========================================================
-- Funções do painel (admin)
-- =========================================================
create or replace function public.set_advertiser_pin(p_id uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'sem permissão'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'O PIN precisa ter de 4 a 8 números'; end if;
  update advertisers set redeem_pin_hash = crypt(p_pin, gen_salt('bf', 8)) where id = p_id;
end $$;

create or replace function public.dashboard(p_days int default 30)
returns jsonb language plpgsql stable security invoker set search_path = public, extensions as $$
declare s settings; v_from timestamptz; tz text;
begin
  if not public.is_admin() then raise exception 'sem permissão'; end if;
  select * into s from settings where id = 1; tz := s.timezone;
  v_from := now() - make_interval(days => p_days);
  return jsonb_build_object(
    'spins',     (select count(*) from spins where created_at >= v_from),
    'players',   (select count(distinct player_id) from spins where created_at >= v_from),
    'new_players',(select count(*) from players where created_at >= v_from),
    'won',       (select count(*) from claims where created_at >= v_from),
    'redeemed',  (select count(*) from claims where created_at >= v_from and redeemed_at is not null),
    'today',     (select count(*) from spins where created_at >= public._period_start('day', tz, null)),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'spins', n, 'won', w) order by d) from (
        select (created_at at time zone tz)::date d, count(*) n, count(*) filter (where won) w
        from spins where created_at >= v_from group by 1) x), '[]'::jsonb),
    'by_bakery', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'spins', n, 'players', u) order by n desc) from (
        select coalesce(b.name, '—') name, count(*) n, count(distinct sp.player_id) u
        from spins sp left join bakeries b on b.id = sp.bakery_id where sp.created_at >= v_from group by 1) x), '[]'::jsonb),
    'by_advertiser', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'won', w, 'redeemed', r) order by w desc) from (
        select coalesce(a.name, '—') name, count(*) w, count(*) filter (where c.redeemed_at is not null) r
        from claims c left join advertisers a on a.id = c.advertiser_id where c.created_at >= v_from group by 1) x), '[]'::jsonb),
    'by_neighborhood', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'players', u, 'spins', n) order by u desc) from (
        select coalesce(pl.neighborhood, 'Não informado') name, count(distinct sp.player_id) u, count(*) n
        from spins sp join players pl on pl.id = sp.player_id where sp.created_at >= v_from group by 1) x), '[]'::jsonb),
    'by_hour', coalesce((select jsonb_agg(jsonb_build_object('h', h, 'n', n) order by h) from (
        select extract(hour from created_at at time zone tz)::int h, count(*) n
        from spins where created_at >= v_from group by 1) x), '[]'::jsonb),
    'suspicious_devices', coalesce((select jsonb_agg(jsonb_build_object('device', left(device_id, 10), 'phones', n, 'spins', sp) order by n desc) from (
        select device_id, count(distinct player_id) n, count(*) sp from spins
        where created_at >= v_from group by device_id having count(distinct player_id) >= 2 limit 20) x), '[]'::jsonb),
    'suspicious_networks', coalesce((select jsonb_agg(jsonb_build_object('network', left(ip_hash, 10), 'phones', n, 'spins', sp) order by n desc) from (
        select ip_hash, count(distinct player_id) n, count(*) sp from spins
        where created_at >= v_from group by ip_hash having count(distinct player_id) >= 5 limit 20) x), '[]'::jsonb)
  );
end $$;

-- =========================================================
-- Permissões: funções públicas só para a service role (edge function)
-- =========================================================
revoke all on function public.do_spin(text,text,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.redeem(text,text,text,boolean)           from public, anon, authenticated;
revoke all on function public.otp_issue(text)                          from public, anon, authenticated;
revoke all on function public._otp_check(text,text)                    from public, anon, authenticated;
revoke all on function public.wheel_config(text)                       from public, anon, authenticated;
grant execute on function public.do_spin(text,text,text,text,text,text,text,text) to service_role;
grant execute on function public.redeem(text,text,text,boolean)           to service_role;
grant execute on function public.otp_issue(text)                          to service_role;
grant execute on function public.wheel_config(text)                       to service_role;
grant execute on function public.set_advertiser_pin(uuid,text) to authenticated;
grant execute on function public.dashboard(int) to authenticated;
