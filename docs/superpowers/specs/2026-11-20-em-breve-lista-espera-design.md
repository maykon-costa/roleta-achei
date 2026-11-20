# Tela "Em breve" + lista de espera

## Por quê
A campanha está aberta, mas ainda sem prêmios. Hoje o cliente que escaneia o QR
(`https://roletaacheinopao.online/?b=acheinopao`) vê uma roleta só com "Não foi dessa vez",
preenche tudo, gira e perde sempre. Queremos avisar com clareza que os prêmios estão chegando
e transformar cada QR escaneado em um contato para chamar no lançamento.

## Objetivos
- Sem prêmios disponíveis (`segments` vazio) → tela "Em breve" no lugar do formulário de giro.
- Campanha que ainda não começou ou já fechou → mesma tela, com o texto certo.
- Nessa tela, o cliente deixa nome, WhatsApp e bairro para ser avisado.
- Você vê a lista no painel, chama cada um no WhatsApp e baixa CSV.
- Ao cadastrar o primeiro prêmio, a roleta volta sozinha.

## Fora do escopo
- Disparo automático em massa do aviso (pode usar o disparador de OTP depois).
- Tratar `padaria_invalida` como "em breve" — o QR real já leva `?b=`; continua como erro.

## Abordagens consideradas
1. **Tabela própria `waitlist` + ação `avisar` na API + aba no painel** — escolhida. Dados
   separados dos jogadores, mesmas proteções (telefone validado, 1 registro por WhatsApp,
   limite por rede, consentimento).
2. Reaproveitar `players` — mistura quem só quer aviso com quem girou; suja painel e anti-fraude.
3. Formulário externo — outra cara, contatos fora do painel.

## Como fica
- **Banco** (`supabase/migrations/20261120100000_lista_espera.sql`): tabela `waitlist`
  (phone único, nome, bairro normalizado igual ao giro, padaria, ip_hash, criado, `notified_at`),
  RLS só admin, função `waitlist_join` (só service_role) com limite de 20 cadastros por rede/hora.
- **API**: `POST { acao:"avisar", phone, name, bairro, b, consent, captcha? }`.
- **Roleta**: roleta fica visível, apagada, com selo "Em breve" no centro; cartão com título,
  explicação e formulário "Me avise quando abrir". Depois de cadastrar, mostra confirmação e lembra
  no aparelho ("Você já está na lista").
- **Painel**: aba "Lista de espera" com total, tabela, botão "Chamar no WhatsApp" (abre `wa.me`
  com mensagem pronta e marca como avisado) e "Exportar CSV".

Calls do Claude: textos das telas, limite de 20/hora por rede, mensagem pronta do WhatsApp.
