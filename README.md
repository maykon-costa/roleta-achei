# Roleta Achei no Pão

Roleta de prêmios para clientes das padarias parceiras, com prêmios dos anunciantes,
limites de giro definidos por você e anti-fraude no servidor.

```
QR na padaria ──► roleta.html?b=padaria ──► edge function "roleta" ──► do_spin() no Postgres
                                                                         │ sorteio + limites + estoque
cliente ganha código AP-XXXXXXX ◄────────────────────────────────────────┘
        │
        └─► vai ao anunciante ──► resgate.html (código + PIN do anunciante) ──► marcado como entregue

painel.html ──► você controla prêmios, anunciantes, padarias, limites e vê os dados
```

## Arquivos

| Arquivo | O que é |
|---|---|
| `supabase/migrations/…_roleta.sql` | Tabelas, RLS, sorteio atômico, OTP, resgate, dashboard |
| `supabase/functions/roleta/index.ts` | API pública (config, código WhatsApp, girar, resgatar) |
| `web/index.html` | Redireciona a raiz do site para a roleta (é o endereço do QR do saco de pão) |
| `web/roleta.html` | Página do cliente (sem `?b=`, usa a origem `saco`; abre em modo demonstração enquanto não estiver configurada) |
| `web/resgate.html` | Página do anunciante para validar códigos |
| `web/painel.html` | Seu painel administrativo |
| `web/painel-demo-data.js` | Dados fictícios do modo demonstração do painel (pode apagar em produção) |

## Como o anti-fraude funciona

1. **Sorteio no servidor.** O navegador só recebe o resultado e anima até a fatia certa. Mexer no
   JavaScript não muda nada.
2. **Limite por WhatsApp** (N giros por dia/semana/mês/campanha). A linha do jogador é travada
   (`FOR UPDATE`) durante o giro, então abrir 10 abas e clicar ao mesmo tempo não dá 10 giros.
3. **Limite por aparelho**: giros por dia e quantos WhatsApps diferentes o mesmo aparelho pode usar
   (30 dias). Barra quem troca de número para jogar de novo.
4. **Limite por rede** (giros por hora no mesmo IP). Deixe folga se a padaria tiver Wi-Fi aberto.
5. **Código por WhatsApp (opcional, recomendado)**: barra números falsos. Depois de verificado,
   o aparelho fica confiável por N dias e não pede código de novo.
6. **Estoque e limite diário** por prêmio, com baixa atômica — o último item nunca sai duas vezes.
7. **Código de prêmio único** (`AP-` + 7 caracteres, ~34 bilhões de combinações), com validade, que só
   o anunciante consegue dar baixa com o PIN dele. 10 erros de PIN por hora bloqueiam a rede.
8. **Privacidade**: IP e identificador do aparelho são guardados só como hash com sal.
9. **Relatório de suspeitos** no painel: aparelhos e redes com muitos números. Dá para bloquear o
   jogador com um clique.
10. **Captcha opcional** (Cloudflare Turnstile, grátis) contra robôs.

Limitação honesta: sem o código por WhatsApp, quem limpar os dados do navegador ganha um "aparelho
novo". O limite por WhatsApp e por rede continuam valendo, mas o OTP é o que fecha essa porta.

## Subindo

```bash
supabase link --project-ref SEU-PROJETO
supabase db push
supabase secrets set SPIN_SALT="$(openssl rand -hex 24)"
supabase functions deploy roleta --no-verify-jwt
```

**Seu acesso de administrador** — o painel entra com e-mail e senha. Crie o usuário em
Authentication → Users → Add user → Create new user (com senha e "Auto Confirm User" marcado)
e rode no SQL Editor:

```sql
insert into public.admins (user_id)
select id from auth.users where email = 'seu@email.com';
```

**Configure as páginas** (bloco no topo de cada uma): `API_URL`/`ANON_KEY` em `roleta.html` e
`resgate.html`; `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`ROLETA_URL` em `painel.html`. Hospede a pasta
`web/` (Vercel, Netlify…).

**Restrinja a origem** (recomendado em produção):
`supabase secrets set ALLOWED_ORIGINS="https://seudominio.com"`

Ordem de cadastro no painel: anunciantes → PIN de cada um → prêmios → padarias → baixar o QR de cada
padaria → ajustar Regras e limites (incluindo a lista de bairros).

**Bairros:** o cliente escolhe na lista cadastrada em Regras e limites ou digita em "Outro bairro".
O banco corrige a grafia ("  bela   VISTA " vira "Bela Vista"; um bairro fora da lista vira "Vila Nova"),
para os dados por bairro não se espalharem em variações.

**Modo demonstração:** enquanto `SUPABASE_URL` estiver com o valor de exemplo, `roleta.html` e
`painel.html` abrem com dados fictícios — útil para mostrar a anunciantes e padarias.

## Código por WhatsApp (opcional)

A função não depende de um provedor específico. Defina:

```bash
supabase secrets set OTP_WEBHOOK_URL="https://seu-disparador/enviar" OTP_WEBHOOK_TOKEN="segredo"
```

Ela faz `POST` com `Authorization: Bearer <token>` e o corpo:

```json
{ "phone": "5581999999999", "code": "123456", "message": "Seu código da Roleta Achei no Pão é 123456. Não compartilhe." }
```

Aponte para um fluxo do n8n, uma Evolution API, Z-API ou um endpoint seu que repasse a mensagem.
Depois ligue "Exigir código por WhatsApp" em Regras e limites. Limites embutidos: 1 reenvio por
minuto, 4 códigos por hora por número, 5 tentativas por código, validade de 10 minutos.

## Captcha (opcional)

Crie um widget no Cloudflare Turnstile, coloque a *site key* em `TURNSTILE_SITEKEY` na
`roleta.html` e a *secret* em `supabase secrets set TURNSTILE_SECRET=...`.

## Atenção: autorização da promoção

Distribuição gratuita de prêmios por sorteio ou vale-brinde para o público, feita por empresas,
em geral depende de autorização prévia do Ministério da Fazenda (Lei 5.768/1971; hoje pela
Secretaria de Prêmios e Apostas). Antes de lançar, valide o formato com seu contador ou advogado —
há modelos que mudam o enquadramento, e isso define até o texto do regulamento.
