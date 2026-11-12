window.FSM_NOTIF = (() => {
  'use strict';

  function usuario(perfil) {
    const A = window.FSM_AUTH;
    const id = A && A.usuarioId ? A.usuarioId() : '';
    return id || 'anonimo-' + perfil;
  }

  function hoje() {
    const d = new Date();
    return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
  }

  function chave(n) {
    const t = (n.dia ? hoje() + '|' : '') + n.tit + '|' + (n.ref || n.txt);
    let h1 = 0x811c9dc5;
    let h2 = 0x01000193;
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i);
      h1 = Math.imul(h1 ^ c, 16777619) >>> 0;
      h2 = Math.imul(h2 ^ c, 2246822519) >>> 0;
    }
    return h1.toString(36) + h2.toString(36);
  }

  function ler(uid) {
    try {
      const v = JSON.parse(localStorage.getItem('fsm_notif_' + uid) || '[]');
      return Array.isArray(v) ? v.filter(k => typeof k === 'string' && /^[0-9a-z]{2,16}$/.test(k)) : [];
    } catch (e) {
      return [];
    }
  }

  function gravar(uid, lista) {
    try {
      localStorage.setItem('fsm_notif_' + uid, JSON.stringify(lista.slice(-300)));
    } catch (e) {}
  }

  return { usuario, chave, ler, gravar };
})();
