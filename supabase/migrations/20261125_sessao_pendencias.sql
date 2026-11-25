-- Pendências das sessões de priorização.
-- Cada sessão passa a ter uma lista de ações para verificar depois
-- (descrição, responsável, prazo e check de conclusão). Antes, essas
-- pendências eram digitadas como texto no campo Aprendizados.
--
-- Rode no SQL Editor do Supabase (projeto labdame) antes de publicar o app.

begin;

create table if not exists public.sessao_pendencias (
  id           uuid primary key default gen_random_uuid(),
  sessao_id    uuid not null references public.sessoes(id) on delete cascade,
  descricao    text not null,
  responsavel  text,
  prazo        date,
  concluida    boolean not null default false,
  concluida_em timestamptz,
  ordem        int not null default 0,
  criado_em    timestamptz not null default now()
);

create index if not exists idx_sessao_pendencias_sessao_id on public.sessao_pendencias (sessao_id);

alter table public.sessao_pendencias enable row level security;

drop policy if exists sessao_pendencias_all_admin on public.sessao_pendencias;
create policy sessao_pendencias_all_admin
  on public.sessao_pendencias for all
  to authenticated
  using (public.is_admin()) with check (public.is_admin());

commit;
