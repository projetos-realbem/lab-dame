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
Fila priorizada por score GUT (G × U × T)
        ↓
Sessão semanal → admin prioriza e promove para iniciativa
        ↓
Iniciativa acompanhada: status, ganho financeiro, ganho operacional, payback
        ↓
Dashboard consolidado: R$/mês, h/mês, ROI anualizado
```

---

## Acesso

| Perfil | O que pode fazer |
|---|---|
| Público (sem login) | Enviar um problema com classificação GUT |
| Admin (login) | Ver fila, priorizar, gerenciar iniciativas e sessões, ver dashboard |

---

## Campos obrigatórios no envio de problema

- Título
- Nome do solicitante
- Área / setor
- Gravidade, Urgência e Tendência (Matriz GUT)

Descrição da dor e impacto estimado são opcionais, mas ajudam muito na priorização.

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

---

## Observações

- **Plano free do Supabase:** projetos sem atividade por 7 dias são pausados automaticamente.
  Para uso interno com sessões semanais, o acesso regular evita a pausa.
- **Backup:** o plano free não inclui backup automático. Faça exports periódicos se necessário.
