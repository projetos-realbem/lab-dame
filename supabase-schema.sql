-- ============================================================
-- SISTEMA CULTURA DE IA — Schema + RLS para Supabase
-- Rode este script inteiro no SQL Editor do Supabase.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Como definir quem é ADMIN
-- ------------------------------------------------------------
-- Estratégia: um admin é qualquer usuário autenticado cujo
-- e-mail está na tabela `admins`. Simples de gerir e não depende
-- de custom claims / JWT hooks.
-- ------------------------------------------------------------

create table if not exists public.admins (
  email text primary key,
  criado_em timestamptz not null default now()
);

-- Cadastre aqui os e-mails dos admins (os mesmos que terão conta em Auth):
-- insert into public.admins (email) values ('voce@empresa.com');

-- Função helper: o usuário logado é admin?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins a
    where a.email = auth.jwt() ->> 'email'
  );
$$;

-- ------------------------------------------------------------
-- 1. Tabelas
-- ------------------------------------------------------------

create table if not exists public.problemas (
  id           uuid primary key default gen_random_uuid(),
  codigo       text unique,
  titulo       text not null,
  solicitante  text,
  area         text,
  descricao    text,
  impacto      text,
  gravidade    int  check (gravidade between 1 and 5),
  urgencia     int  check (urgencia  between 1 and 5),
  tendencia    int  check (tendencia between 1 and 5),
  gut          int  generated always as (coalesce(gravidade,0)*coalesce(urgencia,0)*coalesce(tendencia,0)) stored,
  status       text not null default 'Novo'
                 check (status in ('Novo','Em Análise','Priorizado','Recusado')),
  criado_em    timestamptz not null default now()
);

create table if not exists public.iniciativas (
  id           uuid primary key default gen_random_uuid(),
  codigo       text unique,
  problema_id  uuid references public.problemas(id) on delete set null,
  sessao_id    uuid,  -- FK adicionada depois que sessoes existir
  titulo       text not null,
  area         text,
  dono         text,
  status       text not null default 'Priorizado'
                 check (status in ('Priorizado','Em Implementação','Implementado','Descartado','Em Pausa')),
  data         date,
  problema     text,
  testado      text,
  bucket       text,
  resultado    text,
  ganho_fin    numeric default 0,   -- R$ / mês
  ganho_op     numeric default 0,   -- horas / mês
  custo        numeric default 0,   -- R$ total de implementação
  decisao      text,
  criado_em    timestamptz not null default now()
);

create table if not exists public.sessoes (
  id           uuid primary key default gen_random_uuid(),
  codigo       text unique,
  data         date,
  numero       text,
  ancora       text,
  formato      text,
  problema     text,
  resultado    text,
  aprendizados text,
  criado_em    timestamptz not null default now()
);

-- FK de iniciativas -> sessoes (agora que a tabela existe)
do $$ begin
  alter table public.iniciativas
    add constraint iniciativas_sessao_fk
    foreign key (sessao_id) references public.sessoes(id) on delete set null;
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- 2. Geração automática de código (IA-P001, IA-I001, IA-S01)
-- ------------------------------------------------------------
create sequence if not exists seq_problema;
create sequence if not exists seq_iniciativa;
create sequence if not exists seq_sessao;

create or replace function public.gen_codigo_problema()
returns trigger language plpgsql as $$
begin
  if new.codigo is null then
    new.codigo := 'IA-P' || lpad(nextval('seq_problema')::text, 3, '0');
  end if;
  return new;
end $$;

create or replace function public.gen_codigo_iniciativa()
returns trigger language plpgsql as $$
begin
  if new.codigo is null then
    new.codigo := 'IA-I' || lpad(nextval('seq_iniciativa')::text, 3, '0');
  end if;
  return new;
end $$;

create or replace function public.gen_codigo_sessao()
returns trigger language plpgsql as $$
begin
  if new.codigo is null then
    new.codigo := 'IA-S' || lpad(nextval('seq_sessao')::text, 2, '0');
  end if;
  return new;
end $$;

drop trigger if exists trg_cod_problema on public.problemas;
create trigger trg_cod_problema before insert on public.problemas
  for each row execute function public.gen_codigo_problema();

drop trigger if exists trg_cod_iniciativa on public.iniciativas;
create trigger trg_cod_iniciativa before insert on public.iniciativas
  for each row execute function public.gen_codigo_iniciativa();

drop trigger if exists trg_cod_sessao on public.sessoes;
create trigger trg_cod_sessao before insert on public.sessoes
  for each row execute function public.gen_codigo_sessao();

-- ------------------------------------------------------------
-- 3. Row Level Security
-- ------------------------------------------------------------
alter table public.problemas   enable row level security;
alter table public.iniciativas enable row level security;
alter table public.sessoes     enable row level security;
alter table public.admins      enable row level security;

-- ---- admins: ninguém lê pela API pública; só o backend (service role) gere.
--     (is_admin() usa security definer, então enxerga a tabela mesmo com RLS on)
--     Sem policies = nenhum acesso via anon/authenticated. Gerencie admins pelo painel.

-- ---- problemas ----
-- INSERT: qualquer um (anon e authenticated) pode enviar um problema.
drop policy if exists problemas_insert_public on public.problemas;
create policy problemas_insert_public
  on public.problemas for insert
  to anon, authenticated
  with check (true);

-- SELECT: só admin vê a fila.
drop policy if exists problemas_select_admin on public.problemas;
create policy problemas_select_admin
  on public.problemas for select
  to authenticated
  using (public.is_admin());

-- UPDATE / DELETE: só admin.
drop policy if exists problemas_update_admin on public.problemas;
create policy problemas_update_admin
  on public.problemas for update
  to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists problemas_delete_admin on public.problemas;
create policy problemas_delete_admin
  on public.problemas for delete
  to authenticated
  using (public.is_admin());

-- ---- iniciativas ---- (tudo só admin)
drop policy if exists iniciativas_all_admin on public.iniciativas;
create policy iniciativas_all_admin
  on public.iniciativas for all
  to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---- sessoes ---- (tudo só admin)
drop policy if exists sessoes_all_admin on public.sessoes;
create policy sessoes_all_admin
  on public.sessoes for all
  to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- PRONTO. Próximos passos manuais:
--   1) Authentication > Providers: habilite Email (email+senha).
--      Desative "Confirm email" se quiser criar admins na mão sem verificação.
--   2) Authentication > Users: crie o usuário admin (email+senha).
--   3) insert into public.admins (email) values ('email-do-admin@empresa.com');
--   4) Cole a URL do projeto e a anon key no HTML.
-- ============================================================
