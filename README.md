# Lab Dame — Cultura de IA · Gestão de Iniciativas

Sistema interno para estruturar a implantação da cultura de IA na empresa.
Permite captar problemas de qualquer colaborador, priorizá-los pela **Matriz GUT**,
conduzir sessões semanais de priorização e acompanhar as iniciativas com seus
ganhos financeiros e operacionais.

---

## Fluxo do sistema

```
Colaborador envia problema (público, sem login)
        ↓
Fila priorizada por score GUT (G × U × T) — status inicial: Novo
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
| Público (sem login) | Enviar um problema com classificação GUT |
| Admin (login) | Ver fila, priorizar, gerenciar iniciativas e sessões, ver dashboard |

---

## Ciclo de vida dos itens

### Problemas

`Novo` → (vinculado a uma sessão) → `Priorizado` **ou** `Recusado`

- **Novo:** recém-enviado, aguardando entrar em uma sessão.
- **Priorizado:** aprovado na sessão; normalmente vira uma iniciativa.
- **Recusado:** avaliado e descartado na sessão.

Priorizar/recusar só fica disponível quando o problema está vinculado a uma sessão.

### Iniciativas

`Priorizado` → `Em Implementação` → `Implementado`
(ou `Descartado` / `Em Pausa` a qualquer momento)

O vínculo de uma iniciativa a uma sessão é feito **exclusivamente pela aba Sessões**
(não há mais campo de sessão dentro do formulário da iniciativa).

---

## Campos obrigatórios no envio de problema

- Título
- Nome do solicitante
- Área / setor
- Gravidade, Urgência e Tendência (Matriz GUT)
- **Impacto estimado** — uma ou mais categorias de ganho (ver abaixo)

Descrição da dor é opcional, mas ajuda na priorização.

---

## Categorias de impacto

Tanto o **Impacto estimado** do problema quanto a **Categoria de impacto** da iniciativa
usam a mesma lista de categorias, selecionadas por **caixas de seleção (múltipla escolha)**:

- Tempo economizado
- Custo reduzido
- Solução construída internamente
- Qualidade de entrega
- Velocidade de decisão
- Redução de risco ou inadimplência
- Geração de receita ou conversão

As categorias marcadas são gravadas como texto separado por vírgula nos campos
`problemas.impacto` e `iniciativas.bucket`. O dashboard conta cada iniciativa em
**todas** as categorias que ela marcou.

---

## Matriz GUT

Score = G × U × T (máximo 125). A fila é ordenada automaticamente do maior para o menor score.

| Faixa | Classificação |
|---|---|
| ≥ 64 | Crítico |
| ≥ 27 | Alto |
| ≥ 8 | Médio |
| < 8 | Baixo |

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

---

## Stack

- **Frontend:** HTML + CSS + JS vanilla — arquivo único (`index.html`), sem build
- **Backend:** [Supabase](https://supabase.com) — Postgres + Auth + RLS
- **Hospedagem:** GitHub Pages (repositório privado)
- **Auth:** Email + senha via Supabase Auth (somente admins cadastrados)

---

## Estrutura do repositório

```
index.html              App completo (UI + lógica)
config.example.js       Modelo de config sem credenciais
supabase-schema.sql     Schema, triggers e políticas RLS
README.md
```

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

## Como adicionar um admin

1. **Authentication → Users → Add user** no Supabase (marque Auto Confirm User).
2. SQL Editor:
   ```sql
   insert into public.admins (email) values ('novo@empresa.com');
   ```

## Como remover um admin

```sql
delete from public.admins where email = 'email@empresa.com';
```

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
- **Chave estrangeira de sessão (recomendado):** para robustez extra, deixe a coluna
  `sessao_id` com `on delete set null`, servindo de rede de segurança caso uma sessão
  seja apagada por fora da aplicação.

---

## Observações

- **Plano free do Supabase:** projetos sem atividade por 7 dias são pausados automaticamente.
  Para uso interno com sessões semanais, o acesso regular evita a pausa.
- **Backup:** o plano free não inclui backup automático. Faça exports periódicos se necessário.

---

## Histórico de mudanças recentes

- Impacto estimado (problema) e Categoria de impacto (iniciativa) passaram a ser
  seleção por **checkbox de múltipla escolha** com categorias padronizadas.
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
