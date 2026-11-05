# Lab Dame — Cultura de IA · Gestão de Iniciativas

Sistema interno para estruturar a implantação da cultura de IA na empresa.
Permite captar problemas de qualquer colaborador, priorizá-los por um **score de impacto
ponderado** (peso × intensidade ÷ esforço),
conduzir sessões semanais de priorização e acompanhar as iniciativas com seus
ganhos financeiros e operacionais.

---

## Fluxo do sistema

```
Colaborador envia problema (público, sem login)
        ↓
Fila priorizada pelo score de impacto (Σ peso × intensidade ÷ esforço) — status inicial: Novo
        ↓
Sessão semanal → problema é vinculado à sessão para análise
        ↓
Na sessão: admin prioriza (→ vira iniciativa) ou recusa o problema
        ↓
Iniciativa acompanhada: status, ganho financeiro, ganho operacional, payback
        ↓
Dashboard consolidado: R$/mês, h/mês, ROI anualizado
```

> **Regra de negócio:** priorizar ou recusar um problema só é possível **depois** que
> ele foi vinculado a uma sessão. Antes disso, o problema permanece na fila com status `Novo`.

---

## Acesso

| Perfil | O que pode fazer |
|---|---|
| Público (sem login) | Enviar um problema informando a intensidade de cada impacto |
| Admin (login) | Ver fila, priorizar, gerenciar iniciativas, sessões e usuários, ver dashboard |

### Usuários (aba "Usuários")

Os administradores são gerenciados dentro do próprio app, sem passar pelo painel do Supabase:

- **Novo usuário**: informe o e-mail (e, se quiser, o nome). O sistema cria o login,
  inclui o e-mail na tabela `admins` e mostra **uma única vez** uma senha provisória
  (ex.: `Kp7m-Xq2a-9rTz`) para entregar pessoalmente. Se o e-mail já tinha login,
  o acesso é reativado e uma senha provisória nova é gerada.
- **Nova senha**: gera outra senha provisória para a pessoa (a atual deixa de valer).
- **Bloquear / Desbloquear**: impede ou libera o login, sem tirar da `admins`.
- **Remover**: tira da `admins` e bloqueia o login. A conta não é apagada; "Novo usuário"
  com o mesmo e-mail reativa.
- **Alterar minha senha** (cabeçalho): cada pessoa troca a própria senha. É assim que se
  sai da senha provisória.

Travas: ninguém age sobre a própria conta, e nunca fica menos de um administrador ativo.
O projeto não envia e-mail; toda senha é entregue em mãos.

---

## Ciclo de vida dos itens

### Problemas

`Novo` → (vinculado a uma sessão) → `Priorizado` **ou** `Recusado`

- **Novo:** recém-enviado, aguardando entrar em uma sessão.
- **Priorizado:** aprovado na sessão; normalmente vira uma iniciativa.
- **Recusado:** avaliado e descartado na sessão.

Priorizar/recusar só fica disponível quando o problema está vinculado a uma sessão.

### Iniciativas

`Nova` → `Em Implementação` → `Implementado`
(ou `Descartado` / `Em Pausa` a qualquer momento)

O banco só aceita esses cinco status. Registros antigos com `Priorizado` são tratados
pelo app como `Nova`.

O vínculo de uma iniciativa a uma sessão é feito **exclusivamente pela aba Sessões**
(não há mais campo de sessão dentro do formulário da iniciativa).

---

## Campos obrigatórios no envio de problema

- Título
- Nome do solicitante
- Área / setor
- Descrição da dor
- **Impacto estimado** — intensidade de cada impacto cadastrado (ver abaixo); ao menos
  um precisa estar acima de "Nenhum"

O **esforço** não é pedido ao colaborador: o admin define ao editar o problema
(normalmente na sessão). Até lá o score é calculado com esforço 1.

---

## Impactos e pesos

Os impactos são cadastrados na tabela `impactos` e gerenciados pelo admin na aba
**Configurações** (nome, peso, ordem e ativo/inativo). Se a tabela estiver vazia, o app
usa esta lista padrão:

| Impacto | Peso |
|---|---|
| Geração de receita ou conversão | 5 |
| Redução de custo | 5 |
| Redução de risco ou inadimplência | 4 |
| Tempo economizado | 3 |
| Qualidade de entrega | 3 |
| Velocidade de decisão | 2 |

Tanto o problema quanto a iniciativa recebem, para **cada** impacto ativo, uma
intensidade: `Nenhum` (0), `Baixo` (1), `Médio` (2) ou `Alto` (3). A iniciativa criada
a partir de um problema herda as intensidades dele.

As intensidades são gravadas em `problemas.impactos_json` e `iniciativas.impactos_json`
(`{"nome do impacto": intensidade}`). Os campos de texto `problemas.impacto` e
`iniciativas.bucket` continuam sendo preenchidos com os nomes marcados, só para leitura
e para registros antigos.

A mesma aba Configurações mantém as **abordagens** de resolução (tabela `abordagens`:
desenvolvimento com IA, solução de mercado, melhoria de processo etc.), escolhidas na
iniciativa.

---

## Score de impacto

```
score = Σ (peso do impacto × intensidade) ÷ esforço
```

- **Esforço** estimado de implementação: `Baixo` (1), `Médio` (2) ou `Alto` (3),
  definido pelo admin no problema e na iniciativa. Sem esforço definido, divide por 1.
- A fila é ordenada automaticamente do maior para o menor score.

| Faixa | Classificação |
|---|---|
| ≥ 20 | Altíssimo |
| ≥ 10 | Alto |
| ≥ 4 | Médio |
| < 4 | Baixo |

As colunas da Matriz GUT (`gravidade`, `urgencia`, `tendencia`, `gut`) foram removidas
da tabela `problemas` em 05/11/2026 (`supabase/migrations/20261105_remover_colunas_gut.sql`).

---

## Sessões de priorização

Ao criar ou editar uma sessão, o admin pode vincular itens que estão disponíveis:

- **Problemas** com status `Novo` **ou** `Priorizado` que ainda não estejam em nenhuma sessão.
- **Iniciativas** com status `Priorizado` que ainda não estejam em nenhuma sessão.

Um item vinculado a uma sessão deixa de aparecer como candidato para outras sessões
(exceto ao editar a sessão à qual ele já pertence).

### Ao excluir uma sessão

Os itens tratados nela são **liberados** automaticamente antes de a sessão ser apagada:

- **Problemas** voltam para o status `Novo` e ficam sem sessão (voltam à fila) —
  exceto os que já foram promovidos a iniciativa, que apenas perdem o vínculo de sessão.
- **Iniciativas** são desvinculadas (mantêm o status atual).

Isso garante que nada fique "órfão", independentemente da configuração de chave
estrangeira no banco.

---

## Dashboard — ganhos consolidados

Os cards de **Ganho financeiro / mês**, **Ganho operacional / mês** e
**Retorno anualizado (ROI)** consideram tanto as iniciativas `Implementado`
quanto as `Em Implementação` (ou seja, tudo que já está ativo). O custo somado e o
ROI também incluem ambas.

Os campos de valor (ganho financeiro, ganho operacional e custo) aceitam qualquer
valor e usam **máscara monetária** no padrão brasileiro (ex.: `R$ 42.111.141,41`).
Os valores são gravados como número puro no banco.

O bloco de **impactos** do dashboard mostra uma barra por impacto ativo, com a soma de
`peso × intensidade` das iniciativas ativas, e o resumo das abordagens escolhidas.

---

## Stack

- **Frontend:** HTML + CSS + JS vanilla — arquivo único (`index.html`), sem build
- **Backend:** [Supabase](https://supabase.com) — Postgres + Auth + RLS
- **Edge Function `usuarios`:** gestão de usuários (precisa da chave de serviço, por isso
  roda no Supabase e não no navegador)
- **Projeto Supabase compartilhado:** o projeto `labdame` também hospeda o "My Notes",
  outro sistema, que usa o schema `mynotes` e a Edge Function `agente`. Nada disso é do
  Lab Dame e nada disso fica neste repositório (ver "Notas técnicas").
- **Hospedagem:** GitHub Pages, publicado da `main` do repositório público
  `projetos-realbem/lab-dame`
- **Auth:** Email + senha via Supabase Auth (somente admins cadastrados)

---

## Estrutura do repositório

```
index.html                        App completo (UI + lógica)
supabase-schema.sql               Schema, triggers e políticas RLS (espelho da produção)
supabase/config.toml              Configuração mínima do Supabase CLI
supabase/migrations/              Alterações pontuais já aplicadas em produção (histórico)
supabase/functions/usuarios/      Edge Function de gestão de usuários
README.md
```

A Edge Function `agente`, que aparece no painel do mesmo projeto Supabase, é do
"My Notes" e fica de fora de propósito (ver "Notas técnicas").

## Publicar a Edge Function `usuarios`

Sempre que `supabase/functions/usuarios/index.ts` mudar, publique antes de fazer o merge
do site (a aba Usuários chama a função em produção). Pré-requisito: [Supabase CLI](https://supabase.com/docs/guides/local-development).

```bash
supabase login
```

```bash
supabase functions deploy usuarios --project-ref gcdrjkqexfbuenpkvovo
```

A função usa `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY`, que o Supabase injeta sozinho.
Ela só atende quem tem sessão válida **e** e-mail na tabela `admins`, e aceita chamadas
apenas de `https://projetos-realbem.github.io` (e, até a migração terminar, também de
`https://robertocassianoteixeira.github.io`) e de `localhost`.

Para testar o `index.html` localmente, sirva a pasta por HTTP (ex.: `npx serve .`) e
abra `http://localhost:3000`. Abrir o arquivo direto (`file://`) não funciona com a função.

---

## Setup inicial (para replicar em outro ambiente)

### 1. Supabase

1. Crie um projeto novo (região: South America — São Paulo).
2. **SQL Editor → New query** → cole o conteúdo de `supabase-schema.sql` → Run.
3. **Authentication → Sign In / Providers → Supabase Auth:**
   - Desative **Confirm email**.
4. **Authentication → Users → Add user → Create new user:**
   - Preencha email + senha e marque **Auto Confirm User**.
5. Registre o admin na tabela (mesmo email do passo 4):
   ```sql
   insert into public.admins (email) values ('email@empresa.com');
   ```
6. **Settings → API:** copie a **Project URL** e a **anon/public key**.

> Use sempre a chave `anon` — nunca a `service_role`.

### 2. index.html

Abra o `index.html` e substitua os valores nas linhas:

```js
const SUPABASE_URL      = 'https://SEU-PROJETO.supabase.co';
const SUPABASE_ANON_KEY = 'SUA_ANON_KEY_AQUI';
```

### 3. GitHub Pages

```bash
git init
git add .
git commit -m "primeiro commit"
git branch -M main
git remote add origin git@github.com:SEU-USUARIO/SEU-REPO.git
git push -u origin main
```

**Settings → Pages → Source: Deploy from a branch → main / (root) → Save.**

---

## Como adicionar ou remover um admin

Pela aba **Usuários** do app (ver "Acesso" acima). O caminho manual pelo painel do
Supabase continua valendo como plano B:

1. **Authentication → Users → Add user** (marque Auto Confirm User).
2. SQL Editor:
   ```sql
   insert into public.admins (email) values ('novo@empresa.com');
   ```

Para remover manualmente: `delete from public.admins where email = 'email@empresa.com';`
e, em **Authentication → Users**, bloqueie (Ban) o usuário.

---

## Segurança (RLS)

| Tabela | INSERT | SELECT | UPDATE / DELETE |
|---|---|---|---|
| `problemas` | público (anon) | só admin | só admin |
| `iniciativas` | só admin | só admin | só admin |
| `sessoes` | só admin | só admin | só admin |
| `admins` | sem acesso via API | sem acesso via API | sem acesso via API |

A `admins` é lida internamente pela função `is_admin()` com `security definer`.
Nenhum acesso externo chega nela.

> **Exclusão de registros:** a interface não oferece mais o botão de excluir problemas
> e iniciativas — o ciclo correto é recusar/descartar via status. A exclusão de
> **sessões** continua disponível (e libera os itens vinculados, como descrito acima).

---

## Notas técnicas

- **Comparação de status tolerante:** filtros e agregações comparam status de forma
  normalizada (ignorando espaços extras e maiúsculas/minúsculas). Isso evita que
  dados legados com pequenas variações de texto (ex.: `"em implementação "`) quebrem
  filtros, contagens ou o dashboard. Ainda assim, o ideal é manter os valores exatos.
- **Diagnóstico de dados:** se uma contagem parecer errada, verifique os status
  distintos no banco antes de suspeitar do código:
  ```sql
  select distinct status from problemas;
  select distinct status from iniciativas;
  ```
- **Chave estrangeira de sessão:** `problemas.sessao_id` e `iniciativas.sessao_id` têm
  `on delete set null`, rede de segurança caso uma sessão seja apagada por fora da
  aplicação. Comentários são apagados junto com o item (`on delete cascade`).
- **`supabase-schema.sql` é o espelho do banco de produção** (dump de 04/11/2026) e é
  idempotente: pode ser rodado de novo para completar uma instalação antiga. Depois de
  mudar o schema pelo painel, atualize o arquivo (`supabase db dump --linked --schema public`
  com o Docker aberto) para o repositório não ficar para trás.
- **O projeto Supabase é dividido com o "My Notes":** no painel do projeto `labdame`
  aparecem o schema `mynotes` (tabelas `membros`, `notas`, `conversas`, `eventos`) e a
  Edge Function `agente`, que pertencem a esse outro sistema. O Lab Dame só usa o schema
  `public` e a função `usuarios`; o dump do schema (`--schema public`) já ignora o
  `mynotes`. Não publique nem apague a `agente` a partir deste repositório, e não a
  registre no `supabase/config.toml`: um `supabase functions deploy` sem nome de função
  publica tudo que está em `supabase/functions/`, e só a `usuarios` deve estar lá.

---

## Observações

- **Plano free do Supabase:** projetos sem atividade por 7 dias são pausados automaticamente.
  Para uso interno com sessões semanais, o acesso regular evita a pausa.
- **Backup:** o plano free não inclui backup automático. Faça exports periódicos se necessário.

---

## Histórico de mudanças recentes

- Repositório transferido para a conta `projetos-realbem`; o site passou a
  `https://projetos-realbem.github.io/lab-dame/`.
- **Matriz GUT substituída pelo score de impacto ponderado**: impactos com peso
  (configuráveis na aba Configurações), intensidade por impacto e esforço como divisor.
  As colunas GUT foram removidas do banco.
- Impacto estimado (problema) e Categoria de impacto (iniciativa) passaram a ser
  seleção por **checkbox de múltipla escolha** com categorias padronizadas
  (depois evoluída para intensidade por impacto).
- Campos de valor com **máscara monetária** que aceitam qualquer valor.
- Removida a exclusão de problemas e iniciativas pela interface.
- Priorizar/recusar um problema só é permitido **após vínculo a uma sessão**.
- Vínculo de iniciativa a uma sessão passou a ser feito **somente pela aba Sessões**.
- Filtros de status corrigidos, sem a opção "Todos" — padrão `Novo` (Problemas) e
  `Priorizado` (Iniciativas); clicar num filtro funciona mesmo com um item aberto.
- Dashboard passou a incluir iniciativas **Em Implementação** nos ganhos, custo e ROI.
- Excluir uma sessão **libera** os itens tratados (problemas voltam a `Novo`;
  iniciativas são desvinculadas).
- Candidatos de sessão agora incluem problemas `Novo` **ou** `Priorizado` sem sessão.
