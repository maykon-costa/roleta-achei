-- Lista de espera: quem chegou pelo QR enquanto a roleta ainda não tinha prêmios
-- (ou a campanha estava fechada) deixa o WhatsApp para ser avisado.

create table public.waitlist (
  id            uuid primary key default gen_random_uuid(),
  phone         text not null unique,
  name          text not null,
  neighborhood  text,
  bakery_id     uuid references public.bakeries(id) on delete set null,
  ip_hash       text,
  created_at    timestamptz not null default now(),
  notified_at   timestamptz
);
create index waitlist_ip_idx on public.waitlist (ip_hash, created_at desc);

alter table public.waitlist enable row level security;
create policy "admin total" on public.waitlist for all using (public.is_admin()) with check (public.is_admin());

create or replace function public.waitlist_join(
  p_phone text, p_name text, p_neighborhood text, p_bakery text, p_ip_hash text
) returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare s settings; b bakeries; v_nb text := nullif(regexp_replace(trim(coalesce(p_neighborhood,'')), '\s+', ' ', 'g'), '');
        v_name text := nullif(trim(coalesce(p_name,'')), ''); v_exists boolean;
begin
  if v_name is null then return jsonb_build_object('error','nome'); end if;
  if v_nb is null or length(v_nb) < 2 then return jsonb_build_object('error','bairro'); end if;

  select * into b from bakeries where slug = p_bakery and active;
  if b.id is null then return jsonb_build_object('error','padaria_invalida'); end if;

  select * into s from settings where id = 1;
  v_nb := coalesce((select n from unnest(s.neighborhoods) n where lower(n) = lower(v_nb) limit 1), initcap(v_nb));

  select exists(select 1 from waitlist where phone = p_phone) into v_exists;
  if not v_exists and (select count(*) from waitlist
       where ip_hash = p_ip_hash and created_at > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('error','limite_rede');
  end if;

  insert into waitlist (phone, name, neighborhood, bakery_id, ip_hash)
  values (p_phone, left(v_name,60), left(v_nb,60), b.id, p_ip_hash)
  on conflict (phone) do update set name = excluded.name, neighborhood = excluded.neighborhood,
    bakery_id = coalesce(excluded.bakery_id, waitlist.bakery_id);

  return jsonb_build_object('ok', true, 'already', v_exists);
end $$;

revoke all on function public.waitlist_join(text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.waitlist_join(text,text,text,text,text) to service_role;
