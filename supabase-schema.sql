-- ============================================================
-- LAB DAME — CULTURA DE IA — Schema + RLS para Supabase
-- Rode este script inteiro no SQL Editor do Supabase.
--
-- Espelha o schema `public` do projeto de produção (dump de 04/11/2026).
-- É idempotente: pode ser rodado num projeto vazio ou por cima de uma
-- instalação antiga (cria o que falta e não mexe no que já existe).
-- ============================================================

-- ------------------------------------------------------------
-- 0. Como definir quem é ADMIN
-- ------------------------------------------------------------
-- Estratégia: um admin é qualquer usuário autenticado cujo
-- e-mail está na tabela `admins`. Simples de gerir e não depende
-- de custom claims / JWT hooks. A aba "Usuários" do app mantém
-- esta tabela pela Edge Function `usuarios`.
-- ------------------------------------------------------------

create table if not exists public.admins (
  email      text primary key,
  criado_em  timestamptz not null default now()
);

-- Primeiro admin (os demais entram pela aba Usuários):
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
-- 1. Tabelas principais
-- ------------------------------------------------------------

-- Sessões semanais de priorização
create table if not exists public.sessoes (
  id           uuid primary key default gen_random_uuid(),
  codigo       text unique,                 -- IA-S01 (gerado por trigger)
  data         date,
  numero       text,
  ancora       text,
  formato      text,
  problema     text,
  resultado    text,
  aprendizados text,
  criado_em    timestamptz not null default now()
);

-- Problemas enviados pelo formulário público
create table if not exists public.problemas (
  id            uuid primary key default gen_random_uuid(),
  codigo        text unique,                -- IA-P001 (gerado por trigger)
  titulo        text not null,
  solicitante   text not null,
  area          text not null,
  descricao     text not null,
  impacto       text not null,              -- categorias marcadas, separadas por vírgula
  gravidade     int  check (gravidade between 1 and 5),
  urgencia      int  check (urgencia  between 1 and 5),
  tendencia     int  check (tendencia between 1 and 5),
  gut           int  generated always as (coalesce(gravidade,0)*coalesce(urgencia,0)*coalesce(tendencia,0)) stored,
  status        text not null default 'Novo'
                  check (status in ('Novo','Em Análise','Priorizado','Recusado')),
  sessao_id     uuid references public.sessoes(id) on delete set null,
  esforco       int,                        -- definido na sessão (divisor do score)
  impactos_json jsonb not null default '{}'::jsonb,  -- {nome do impacto: intensidade}
  criado_em     timestamptz not null default now()
);

-- Colunas adicionadas depois da primeira versão (instalações antigas)
alter table public.problemas add column if not exists sessao_id     uuid references public.sessoes(id) on delete set null;
alter table public.problemas add column if not exists esforco       int;
alter table public.problemas add column if not exists impactos_json jsonb not null default '{}'::jsonb;
create index if not exists idx_problemas_sessao_id on public.problemas (sessao_id);

-- Iniciativas (problemas priorizados em andamento)
create table if not exists public.iniciativas (
  id            uuid primary key default gen_random_uuid(),
  codigo        text unique,                -- IA-I001 (gerado por trigger)
  problema_id   uuid references public.problemas(id) on delete set null,
  sessao_id     uuid constraint iniciativas_sessao_fk references public.sessoes(id) on delete set null,
  titulo        text not null,
  area          text,
  dono          text,
  -- Atenção: o app sempre informa o status; o default 'Priorizado' é herdado
  -- da primeira versão e NÃO passa no check abaixo (um insert sem status falha).
  status        text not null default 'Priorizado'
                  check (status in ('Nova','Em Implementação','Implementado','Descartado','Em Pausa')),
  data          date,
  problema      text,
  testado       text,
  bucket        text,                       -- categorias de impacto, separadas por vírgula
  resultado     text,
  ganho_fin     numeric default 0,          -- R$ / mês
  ganho_op      numeric default 0,          -- horas / mês
  custo         numeric default 0,          -- R$ total de implementação
  decisao       text,
  esforco       int,
  impactos_json jsonb not null default '{}'::jsonb,
  abordagem     text,                       -- nome da abordagem de resolução
  criado_em     timestamptz not null default now()
);

alter table public.iniciativas add column if not exists esforco       int;
alter table public.iniciativas add column if not exists impactos_json jsonb not null default '{}'::jsonb;
alter table public.iniciativas add column if not exists abordagem     text;

-- ------------------------------------------------------------
-- 2. Configurações (aba "Configurações" do app)
-- ------------------------------------------------------------

-- Impactos e pesos: score = (Σ peso × intensidade) ÷ esforço
create table if not exists public.impactos (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  peso       int  not null default 1,
  ativo      boolean not null default true,
  ordem      int  not null default 0,
  criado_em  timestamptz not null default now()
);

-- Abordagens de resolução (uso de IA, compra de mercado, melhoria de processo...)
create table if not exists public.abordagens (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  ativo      boolean not null default true,
  ordem      int  not null default 0,
  criado_em  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3. Comentários e linha do tempo
-- ------------------------------------------------------------
-- Um registro aponta para UM item (problema, iniciativa ou sessão).
-- tipo 'status' é gerado pelo app a cada mudança de status.

create table if not exists public.comentarios (
  id            uuid primary key default gen_random_uuid(),
  problema_id   uuid references public.problemas(id)   on delete cascade,
  iniciativa_id uuid references public.iniciativas(id) on delete cascade,
  sessao_id     uuid references public.sessoes(id)     on delete cascade,
  tipo          text not null default 'comentario' check (tipo in ('comentario','status')),
  texto         text not null,
  autor         text,                       -- e-mail do admin
  criado_em     timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 4. Geração automática de código (IA-P001, IA-I001, IA-S01)
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
-- 5. Row Level Security
-- ------------------------------------------------------------
alter table public.admins      enable row level security;
alter table public.problemas   enable row level security;
alter table public.iniciativas enable row level security;
alter table public.sessoes     enable row level security;
alter table public.impactos    enable row level security;
alter table public.abordagens  enable row level security;
alter table public.comentarios enable row level security;

-- ---- admins: sem policies = nenhum acesso via anon/authenticated.
--     (is_admin() usa security definer, então enxerga a tabela mesmo com RLS on.)
--     A Edge Function `usuarios` mantém esta tabela com a chave de serviço.

-- ---- problemas ----
-- INSERT: qualquer um (anon e authenticated) pode enviar um problema.
drop policy if exists problemas_insert_public on public.problemas;
create policy problemas_insert_public
  on public.problemas for insert
  to anon, authenticated
  with check (true);

-- SELECT / UPDATE / DELETE: só admin.
drop policy if exists problemas_select_admin on public.problemas;
create policy problemas_select_admin
  on public.problemas for select
  to authenticated
  using (public.is_admin());

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

-- ---- impactos / abordagens ----
-- SELECT: público (o formulário de envio mostra os impactos e seus pesos).
-- Escrita: só admin.
drop policy if exists impactos_select_all on public.impactos;
create policy impactos_select_all
  on public.impactos for select
  using (true);

drop policy if exists impactos_write_admin on public.impactos;
create policy impactos_write_admin
  on public.impactos for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists abordagens_select_all on public.abordagens;
create policy abordagens_select_all
  on public.abordagens for select
  using (true);

drop policy if exists abordagens_write_admin on public.abordagens;
create policy abordagens_write_admin
  on public.abordagens for all
  using (public.is_admin()) with check (public.is_admin());

-- ---- comentarios ---- (ler, inserir e apagar: só admin; não há update)
drop policy if exists comentarios_select_admin on public.comentarios;
create policy comentarios_select_admin
  on public.comentarios for select
  to authenticated
  using (public.is_admin());

drop policy if exists comentarios_insert_admin on public.comentarios;
create policy comentarios_insert_admin
  on public.comentarios for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists comentarios_delete_admin on public.comentarios;
create policy comentarios_delete_admin
  on public.comentarios for delete
  to authenticated
  using (public.is_admin());

-- ============================================================
-- PRONTO. Próximos passos manuais (projeto novo):
--   1) Authentication > Providers: habilite Email (email+senha) e
--      desative "Confirm email" (o projeto não envia e-mail).
--   2) Authentication > Users: crie o primeiro usuário admin (Auto Confirm).
--   3) insert into public.admins (email) values ('email-do-admin@empresa.com');
--   4) Cole a URL do projeto e a anon key no index.html.
--   5) Publique a Edge Function `usuarios` (ver README).
--   6) Cadastre impactos e abordagens na aba Configurações.
-- ============================================================
