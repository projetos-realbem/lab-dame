// Gestão de usuários do Lab Dame (aba "Usuários").
//
// Roda com a chave de serviço, por isso só atende administradores: o chamador
// precisa de uma sessão válida do Supabase Auth e de e-mail na tabela `admins`.
//
// Entrada (POST, JSON): { acao, ...parâmetros }
//   listar                       → lista todos os logins, com situação e último acesso
//   criar       { email, nome? } → cria o login (ou reaproveita um existente), inclui
//                                  na `admins`, desbloqueia e devolve uma SENHA
//                                  PROVISÓRIA (mostrada uma única vez na tela)
//   nova_senha  { id }           → troca a senha por uma provisória nova
//   bloquear    { id }           → impede o login (a pessoa continua na `admins`)
//   desbloquear { id }           → libera o login
//   remover     { id }           → tira da `admins` e bloqueia o login; a conta não é
//                                  apagada, então "criar" com o mesmo e-mail reativa
//
// Travas: ninguém age sobre a própria conta, e nunca fica menos de um admin ativo.
import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2'

// ---------------------------------------------------------------------------
// HTTP

/** Origens autorizadas (produção + testes locais do index.html). */
const ORIGENS_PRODUCAO = [
  'https://projetos-realbem.github.io',
  // Conta antiga: remover depois que a migração do repositório estiver concluída.
  'https://robertocassianoteixeira.github.io',
]

function origemPermitida(origem: string): boolean {
  if (ORIGENS_PRODUCAO.includes(origem)) return true
  return /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origem)
}

function cors(req: Request): HeadersInit {
  const origem = req.headers.get('origin') ?? ''
  return {
    'Access-Control-Allow-Origin': origemPermitida(origem) ? origem : 'null',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  }
}

function json(req: Request, status: number, corpo: unknown): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cors(req), 'Content-Type': 'application/json' },
  })
}

/** Erro de negócio: status HTTP + mensagem em português para a tela. */
class ErroHttp extends Error {
  status: number
  constructor(status: number, mensagem: string) {
    super(mensagem)
    this.status = status
  }
}

// ---------------------------------------------------------------------------
// Acesso

function clienteAdmin(): SupabaseClient {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

/** Valida a sessão do chamador e garante que ele é admin. Devolve o usuário. */
async function exigirAdmin(req: Request, admin: SupabaseClient): Promise<User> {
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token) throw new ErroHttp(401, 'Sessão não informada.')
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data.user?.email) throw new ErroHttp(401, 'Sessão inválida ou expirada. Entre de novo.')
  if (!(await ehAdmin(admin, data.user.email))) throw new ErroHttp(403, 'Somente administradores podem gerenciar usuários.')
  return data.user
}

async function ehAdmin(admin: SupabaseClient, email: string): Promise<boolean> {
  const { data, error } = await admin.from('admins').select('email').ilike('email', email).maybeSingle()
  if (error) throw error
  return !!data
}

function texto(v: unknown, campo: string): string {
  if (typeof v !== 'string' || v.trim() === '') throw new ErroHttp(400, `Campo obrigatório: ${campo}.`)
  return v.trim()
}

function uuid(v: unknown, campo: string): string {
  const s = texto(v, campo)
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s)) {
    throw new ErroHttp(400, `Identificador inválido: ${campo}.`)
  }
  return s
}

// ---------------------------------------------------------------------------
// Senha provisória: sem caracteres ambíguos (0/O, 1/l/I), para ditar sem erro.

const ALFABETO = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'

/** Ex.: "Kp7m-Xq2a-9rTz" (3 grupos de 4, ~69 bits de aleatoriedade). */
function gerarSenhaProvisoria(): string {
  const grupos: string[] = []
  for (let g = 0; g < 3; g++) {
    let s = ''
    while (s.length < 4) {
      const b = crypto.getRandomValues(new Uint8Array(1))[0]
      // rejeição de amostra: sem viés de módulo
      if (b < 256 - (256 % ALFABETO.length)) s += ALFABETO[b % ALFABETO.length]
    }
    grupos.push(s)
  }
  return grupos.join('-')
}

// ---------------------------------------------------------------------------
// Usuários

type Usuario = {
  id: string
  email: string
  nome: string | null
  admin: boolean
  bloqueado: boolean
  ultimo_acesso: string | null
  criado_em: string
}

function bloqueado(u: User): boolean {
  const ate = (u as unknown as { banned_until?: string | null }).banned_until
  return !!ate && new Date(ate).getTime() > Date.now()
}

async function todosUsuarios(admin: SupabaseClient): Promise<User[]> {
  const todos: User[] = []
  for (let page = 1; page <= 10; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 })
    if (error) throw error
    todos.push(...data.users)
    if (data.users.length < 200) break
  }
  return todos
}

async function listar(admin: SupabaseClient): Promise<Usuario[]> {
  const [usuarios, { data: admins, error }] = await Promise.all([
    todosUsuarios(admin),
    admin.from('admins').select('email'),
  ])
  if (error) throw error
  const emailsAdmin = new Set((admins ?? []).map((a) => String(a.email).toLowerCase()))
  return usuarios
    .filter((u) => !!u.email)
    .map((u) => ({
      id: u.id,
      email: u.email!,
      nome: (u.user_metadata?.nome as string | undefined) ?? null,
      admin: emailsAdmin.has(u.email!.toLowerCase()),
      bloqueado: bloqueado(u),
      ultimo_acesso: u.last_sign_in_at ?? null,
      criado_em: u.created_at,
    }))
    .sort((a, b) => a.email.localeCompare(b.email))
}

async function buscar(admin: SupabaseClient, id: string): Promise<User> {
  const { data, error } = await admin.auth.admin.getUserById(id)
  if (error || !data.user) throw new ErroHttp(404, 'Usuário não encontrado.')
  return data.user
}

/** Bloqueio "permanente" (100 anos) ou liberação. */
async function definirBloqueio(admin: SupabaseClient, id: string, bloquear: boolean) {
  const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: bloquear ? '876000h' : 'none' })
  if (error) throw error
}

async function definirSenhaProvisoria(admin: SupabaseClient, id: string): Promise<string> {
  const senha = gerarSenhaProvisoria()
  const { error } = await admin.auth.admin.updateUserById(id, { password: senha })
  if (error) throw error
  return senha
}

/** Garante que, sem contar `exceto`, ainda sobra pelo menos um admin que consegue entrar. */
async function exigirOutroAdminAtivo(admin: SupabaseClient, exceto: string) {
  const lista = await listar(admin)
  const restantes = lista.filter((u) => u.admin && !u.bloqueado && u.id !== exceto)
  if (restantes.length === 0) throw new ErroHttp(400, 'Não dá para deixar o sistema sem nenhum administrador ativo.')
}

// ---------------------------------------------------------------------------
// Ações

async function criar(admin: SupabaseClient, corpo: Record<string, unknown>) {
  const email = texto(corpo.email, 'e-mail').toLowerCase()
  const nome = typeof corpo.nome === 'string' && corpo.nome.trim() ? corpo.nome.trim() : null
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ErroHttp(400, 'E-mail inválido.')

  const existente = (await todosUsuarios(admin)).find((u) => u.email?.toLowerCase() === email)
  let id: string
  let novo = false
  if (existente) {
    id = existente.id
    if (nome) {
      const { error } = await admin.auth.admin.updateUserById(id, { user_metadata: { ...existente.user_metadata, nome } })
      if (error) throw error
    }
  } else {
    // Cria já confirmado (o projeto não envia e-mail), com uma senha aleatória que
    // ninguém conhece; logo abaixo ela vira a provisória que o admin vai entregar.
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: crypto.randomUUID() + crypto.randomUUID(),
      email_confirm: true,
      user_metadata: nome ? { nome } : undefined,
    })
    if (error || !data.user) throw new ErroHttp(502, `Não foi possível criar o login: ${error?.message ?? 'erro no Auth'}`)
    id = data.user.id
    novo = true
  }

  if (!(await ehAdmin(admin, email))) {
    const { error } = await admin.from('admins').insert({ email })
    if (error) throw error
  }
  await definirBloqueio(admin, id, false)
  const senha = await definirSenhaProvisoria(admin, id)
  return { ok: true, id, novo, senha_provisoria: senha }
}

async function sobreOutro(admin: SupabaseClient, chamador: User, corpo: Record<string, unknown>): Promise<User> {
  const id = uuid(corpo.id, 'id')
  if (id === chamador.id) throw new ErroHttp(400, 'Para a sua própria conta, use "alterar minha senha" no cabeçalho.')
  return await buscar(admin, id)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(req) })
  if (req.method !== 'POST') return json(req, 405, { erro: 'Método não permitido.' })
  try {
    const admin = clienteAdmin()
    const chamador = await exigirAdmin(req, admin)
    const corpo = (await req.json().catch(() => ({}))) as Record<string, unknown>
    const acao = texto(corpo.acao, 'acao')

    if (acao === 'listar') return json(req, 200, { ok: true, usuarios: await listar(admin) })
    if (acao === 'criar') return json(req, 200, await criar(admin, corpo))

    const alvo = await sobreOutro(admin, chamador, corpo)

    if (acao === 'nova_senha') {
      if (bloqueado(alvo)) throw new ErroHttp(400, 'Desbloqueie o usuário antes de gerar uma senha.')
      if (!(await ehAdmin(admin, alvo.email!))) throw new ErroHttp(400, 'Este e-mail não tem acesso. Use "Novo usuário" para reativar.')
      return json(req, 200, { ok: true, senha_provisoria: await definirSenhaProvisoria(admin, alvo.id) })
    }
    if (acao === 'bloquear') {
      await exigirOutroAdminAtivo(admin, alvo.id)
      await definirBloqueio(admin, alvo.id, true)
      return json(req, 200, { ok: true })
    }
    if (acao === 'desbloquear') {
      await definirBloqueio(admin, alvo.id, false)
      return json(req, 200, { ok: true })
    }
    if (acao === 'remover') {
      await exigirOutroAdminAtivo(admin, alvo.id)
      const { error } = await admin.from('admins').delete().ilike('email', alvo.email!)
      if (error) throw error
      await definirBloqueio(admin, alvo.id, true)
      return json(req, 200, { ok: true })
    }
    throw new ErroHttp(400, 'Ação inválida.')
  } catch (e) {
    if (e instanceof ErroHttp) return json(req, e.status, { erro: e.message })
    console.error(e)
    return json(req, 500, { erro: 'Erro interno. Tente novamente.' })
  }
})
