-- Dados: recadastra na tabela `sessao_pendencias` as pendências que estavam
-- digitadas como texto no campo Aprendizados da Sessão 03 (04/11/2026).
-- Rode DEPOIS de 20261125_sessao_pendencias.sql, no SQL Editor do Supabase.
-- É idempotente: não duplica se rodar duas vezes.
--
-- Responsável e prazo não constavam no texto; ficam vazios para preencher
-- pelo app (Sessões > Sessão 03 > Editar > Pendências).

begin;

with s as (
  select id from public.sessoes where numero = '03' and data = '2026-11-04' limit 1
),
itens(ordem, descricao, concluida) as (
  values
    (0, 'Trazer app para o Claude corporativo', true),
    (1, 'Avaliação do arquiteto de software sobre estrutura e tecnologia', false),
    (2, 'Buscar dados na fonte oficial (Snowflake)', false),
    (3, 'Internalizar na infra interna da Realbem (plataforma)', false),
    (4, 'Segurança da aplicação e de compartilhamento', false)
)
insert into public.sessao_pendencias (sessao_id, descricao, concluida, concluida_em, ordem)
select s.id, i.descricao, i.concluida, case when i.concluida then now() end, i.ordem
from s cross join itens i
where not exists (
  select 1 from public.sessao_pendencias p
  where p.sessao_id = s.id and p.descricao = i.descricao
);

-- Tira o bloco "Pendências:" do texto de Aprendizados (o que vem antes fica igual).
update public.sessoes
set aprendizados = rtrim(split_part(aprendizados, 'Pendências:', 1))
where numero = '03' and data = '2026-11-04' and aprendizados like '%Pendências:%';

commit;

-- Conferir:
-- select descricao, concluida, ordem from public.sessao_pendencias p
--   join public.sessoes s on s.id = p.sessao_id where s.numero = '03' order by ordem;
