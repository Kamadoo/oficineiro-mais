export const ASSUNTO = 'Seu acesso ao Oficineiro+ está liberado';

const FONTE = "Inter,'Segoe UI',Arial,sans-serif";

export function escapar(v: string): string {
  return v.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

function primeiroNome(nome: string): string {
  return (nome || '').trim().split(/\s+/)[0] || '';
}

const PASSOS = [
  'Acesse o site do Oficineiro+ pelo botão abaixo.',
  'Clique em <b>Primeiro acesso? Ative sua conta aqui</b>.',
  'Informe o seu CPF (ou CNPJ). Enviaremos um código para este e-mail.',
  'Digite o código e siga as orientações da tela para criar a sua senha.',
];

export function modeloHtml(nome: string, site: string): string {
  const ola = nome ? `Olá, ${escapar(primeiroNome(nome))}!` : 'Olá!';
  const endereco = escapar(site);
  const passos = PASSOS.map(
    (p, i) =>
      `<tr><td width="28" valign="top" style="width:28px;padding:0 0 12px;"><div style="width:22px;height:22px;border-radius:11px;background-color:#E3F4F9;color:#0B7EA3;font-size:12px;line-height:22px;font-weight:700;text-align:center;">${
        i + 1
      }</div></td><td valign="top" style="padding:1px 0 12px 8px;font-size:14px;line-height:1.55;color:#34464D;">${p}</td></tr>`,
  ).join('\n');
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light only">
<meta name="supported-color-schemes" content="light only">
<title>${ASSUNTO}</title>
</head>
<body style="margin:0;padding:0;background-color:#EAF0F1;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:#EAF0F1;">Sua conta foi criada. Faça o primeiro acesso com o seu CPF.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#EAF0F1;">
  <tr>
    <td align="center" style="padding:32px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">
        <tr>
          <td style="background-color:#13252C;border-radius:16px 16px 0 0;padding:24px 32px;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td style="padding-right:12px;vertical-align:middle;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td width="12" height="12" style="width:12px;height:12px;background-color:#DD2287;border-radius:3px;font-size:0;line-height:0;">&nbsp;</td>
                      <td width="3" style="width:3px;font-size:0;line-height:0;">&nbsp;</td>
                      <td width="12" height="12" style="width:12px;height:12px;background-color:#6C60E6;border-radius:3px;font-size:0;line-height:0;">&nbsp;</td>
                    </tr>
                    <tr><td colspan="3" height="3" style="height:3px;font-size:0;line-height:0;">&nbsp;</td></tr>
                    <tr>
                      <td width="12" height="12" style="width:12px;height:12px;background-color:#3ECDF3;border-radius:3px;font-size:0;line-height:0;">&nbsp;</td>
                      <td width="3" style="width:3px;font-size:0;line-height:0;">&nbsp;</td>
                      <td width="12" height="12" style="width:12px;height:12px;background-color:#35E47D;border-radius:3px;font-size:0;line-height:0;">&nbsp;</td>
                    </tr>
                  </table>
                </td>
                <td style="vertical-align:middle;font-family:${FONTE};font-size:20px;font-weight:800;color:#FFFFFF;letter-spacing:-0.4px;">Oficineiro<span style="color:#3ECDF3;">+</span></td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="background-color:#FFFFFF;padding:36px 32px 28px;font-family:${FONTE};color:#1A2B33;">
            <h1 style="margin:0 0 12px;font-size:22px;line-height:1.3;font-weight:700;color:#13252C;">${ola}</h1>
            <p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#34464D;">O <b>Oficineiro+</b> é a plataforma de gestão das oficinas e atividades da rede municipal. Nele você acompanha a sua agenda, registra presenças e atividades e encontra as informações do seu trabalho em um só lugar.</p>
            <p style="margin:0 0 22px;font-size:15px;line-height:1.6;color:#34464D;">A sua conta já foi criada. Para começar a usar, faça o primeiro acesso:</p>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
${passos}
            </table>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:14px 0 6px;">
              <tr>
                <td align="center" style="background-color:#0B7EA3;border-radius:10px;">
                  <a href="${endereco}" target="_blank" style="display:inline-block;padding:13px 26px;font-family:${FONTE};font-size:15px;font-weight:700;line-height:1.2;color:#FFFFFF;text-decoration:none;">Fazer o primeiro acesso</a>
                </td>
              </tr>
            </table>
            <p style="margin:10px 0 0;font-size:12px;line-height:1.6;color:#5B6B70;">Se o botão não abrir, copie este endereço no navegador: <span style="color:#0B7EA3;word-break:break-all;">${endereco}</span></p>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:24px;">
              <tr>
                <td style="border-left:4px solid #E0A21B;background-color:#FAEFD9;border-radius:0 8px 8px 0;padding:12px 16px;font-size:13px;line-height:1.55;color:#5C3B08;">
                  <b>Segurança:</b> ninguém da equipe vai pedir a sua senha ou o código de acesso. Se você não esperava este convite, ignore este e-mail.
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="background-color:#FFFFFF;border-top:1px solid #E8EEF0;border-radius:0 0 16px 16px;padding:18px 32px 24px;font-family:${FONTE};font-size:12px;line-height:1.6;color:#5B6B70;">
            Oficineiro+ · Gestão de oficinas e atividades<br>
            Mensagem automática, não é preciso responder.
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>
`;
}

export function modeloTexto(nome: string, site: string): string {
  const ola = nome ? `Olá, ${primeiroNome(nome)}!` : 'Olá!';
  const passos = PASSOS.map((p, i) => `${i + 1}. ${p.replace(/<\/?b>/g, '')}`).join('\n');
  return `${ola}

O Oficineiro+ é a plataforma de gestão das oficinas e atividades da rede municipal. Nele você acompanha a sua agenda, registra presenças e atividades e encontra as informações do seu trabalho em um só lugar.

A sua conta já foi criada. Para começar a usar, faça o primeiro acesso:

${passos}

${site}

Segurança: ninguém da equipe vai pedir a sua senha ou o código de acesso. Se você não esperava este convite, ignore este e-mail.

Oficineiro+ · Mensagem automática, não é preciso responder.
`;
}
