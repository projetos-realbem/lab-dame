-- Remove as colunas da Matriz GUT da tabela `problemas`.
-- O app prioriza pelo score de impacto (impactos_json + esforco) desde a
-- substituição da GUT; estas colunas não eram mais lidas nem gravadas.
--
-- Aplicado em produção em 05/11/2026 pelo SQL Editor do Supabase.
-- Antes de rodar, para saber quantos registros antigos ainda tinham GUT:
--   select count(*) from public.problemas where gravidade is not null;

begin;

alter table public.problemas drop column if exists gut;        -- coluna gerada; sai primeiro
alter table public.problemas drop column if exists gravidade;
alter table public.problemas drop column if exists urgencia;
alter table public.problemas drop column if exists tendencia;

commit;
