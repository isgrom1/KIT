// Scripts de la página (fuera del HTML para que la política de seguridad solo permita scripts de este sitio).
  // Link de descarga (Drive). Vacío mientras no esté publicado el ZIP.
  var DESCARGA = 'https://drive.google.com/file/d/1TCOkMSqL-Zxz9qUz79uobWepj-yh-6QY/view?usp=sharing';
  var b = document.getElementById('descargar');
  if (DESCARGA) { b.href = DESCARGA; b.removeAttribute('aria-disabled'); b.setAttribute('rel', 'noopener'); }
  else { b.textContent = 'Descarga disponible pronto'; }

  // Verificador del sello: compara con los paquetes publicados (paquetes.json, lo escribe armar_paquete.ps1).
  (function () {
    var CODIGO = '54A8-32F4', lista = [];
    var txt = document.getElementById('ver-txt'), res = document.getElementById('ver-res'), tabla = document.getElementById('ver-tabla');
    function esc(s) { var d = document.createElement('div'); d.textContent = String(s == null ? '' : s); return d.innerHTML; }
    function norm(s) { return (s || '').replace(/^\s*ISGROM\s*[·.:-]?\s*/i, '').replace(/\s+/g, '').toUpperCase(); }
    function revisar() {
      var v = norm(txt.value);
      if (!v) { res.textContent = ''; return; }
      var hash = /^[0-9A-F]{64}$/.test(v);
      var ok = hash ? lista.some(function (p) { return (p.sha256 || '').toUpperCase() === v; }) : (v === CODIGO || lista.some(function (p) { return (p.codigo || '').toUpperCase() === v; }));
      res.style.color = ok ? '#047857' : '#b91c1c';
      res.textContent = ok ? (hash ? '✓ Es un paquete publicado por ISGROM.' : '✓ Es el código de ISGROM. Puedes seguir.') : (hash ? '✕ Esa huella no es de ningún paquete publicado. No lo abras y avísame.' : '✕ Ese no es el código de ISGROM. No lo abras y avísame.');
    }
    txt.addEventListener('input', revisar);
    fetch('paquetes.json', { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (j) {
      lista = (j && j.paquetes) || [];
      if (j && j.codigo) { CODIGO = j.codigo; }
      tabla.innerHTML = '<tr><th style="text-align:left;padding:3px 8px">Fecha</th><th style="text-align:left;padding:3px 8px">Archivo</th><th style="text-align:left;padding:3px 8px">SHA-256</th></tr>' +
        lista.slice().reverse().map(function (p) { return '<tr><td style="padding:3px 8px">' + esc(p.fecha) + '</td><td style="padding:3px 8px">' + esc(p.archivo) + '</td><td style="padding:3px 8px;font-family:Consolas,monospace;word-break:break-all">' + esc(p.sha256) + '</td></tr>'; }).join('');
      if (lista.length) { document.getElementById('huella').textContent = lista[lista.length - 1].sha256; }
      revisar();
    }).catch(function () { tabla.innerHTML = '<tr><td>No se pudo cargar la lista.</td></tr>'; });
  })();
