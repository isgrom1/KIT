// Scripts de la página (fuera del HTML para que la política de seguridad solo permita scripts de este sitio).

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
      contador(j && j.contador);
    }).catch(function () { tabla.innerHTML = '<tr><td>No se pudo cargar la lista.</td></tr>'; });
  })();

  // Contador de visitas y descargas: manda solo "visita" o "descarga" al buzón de ISGROM. Sin cookies, sin
  // guardar nada en el navegador y sin datos de la persona (el buzón guarda una cifra por día y nada más).
  function contador(url) {
    if (!/^https:\/\/script\.google\.com\/macros\/s\/[\w-]+\/exec$/.test(url || '')) { return; }
    // fetch sin cookies ni respuesta (Brave bloquea sendBeacon); si el navegador no tiene fetch, sendBeacon.
    function contar(tipo) {
      var cuerpo = JSON.stringify({ accion: 'contar', tipo: tipo });
      try {
        if (window.fetch) { fetch(url, { method: 'POST', mode: 'no-cors', credentials: 'omit', keepalive: true, headers: { 'Content-Type': 'text/plain' }, body: cuerpo }).catch(function () { /* sin contador */ }); }
        else if (navigator.sendBeacon) { navigator.sendBeacon(url, cuerpo); }
      } catch (e) { /* sin contador */ }
    }
    contar('visita');
    var boton = document.getElementById('descargar-rapido');
    if (boton) { boton.addEventListener('click', function () { contar('descarga'); }); }
    mostrarTotales(url);
  }

  // Totales visibles bajo el botón ("N visitas · M descargas"). Solo desde MINIMO visitas: con pocas, un
  // número chico resta confianza en vez de sumarla. Si el buzón no responde, no se muestra nada.
  function mostrarTotales(url) {
    var MINIMO = 100, el = document.getElementById('contador-publico');
    if (!el || !window.fetch) { return; }
    fetch(url + '?accion=publico', { credentials: 'omit', cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (j) {
      var v = Number(j && j.visitas) || 0, d = Number(j && j.descargas) || 0;
      if (!j || !j.ok || v < MINIMO) { return; }
      var f = function (n) { return n.toLocaleString('es-CL'); };
      el.textContent = f(v) + ' visitas · ' + f(d) + ' descargas del diagnóstico';
      el.hidden = false;
    }).catch(function () { /* sin totales */ });
  }

  // Reseñas reales de Google (resenas.json, las copia ISGROM de su perfil). Sin reseñas, la sección queda
  // escondida. Todo se escribe con textContent: un texto de reseña nunca se interpreta como HTML.
  (function () {
    var sec = document.getElementById('resenas'), lista = document.getElementById('resenas-lista');
    if (!sec || !lista || !window.fetch) { return; }
    function linkGoogle(id, url) {
      var a = document.getElementById(id);
      if (a && /^https:\/\/(g\.page|maps\.app\.goo\.gl|(www\.)?google\.[a-z.]+|search\.google\.com)\//.test(url || '')) { a.href = url; a.hidden = false; }
    }
    fetch('resenas.json', { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (j) {
      var rs = ((j && j.resenas) || []).filter(function (x) { return x && x.texto && x.nombre; });
      if (!rs.length) { return; }
      rs.slice(0, 6).forEach(function (x) {
        var c = document.createElement('div'); c.className = 'resena';
        var e = document.createElement('div'); e.className = 'estrellas';
        var n = Math.max(1, Math.min(5, Math.round(Number(x.estrellas) || 5)));
        e.textContent = '★★★★★'.slice(0, n) + '☆☆☆☆☆'.slice(0, 5 - n); e.setAttribute('aria-label', n + ' de 5 estrellas');
        var p = document.createElement('p'); p.style.margin = '6px 0 0'; p.textContent = '“' + String(x.texto) + '”';
        var q = document.createElement('div'); q.className = 'quien'; q.textContent = String(x.nombre) + (x.fecha ? ' · ' + String(x.fecha) : '');
        c.appendChild(e); c.appendChild(p); c.appendChild(q); lista.appendChild(c);
      });
      linkGoogle('resenas-ver', j.perfil); linkGoogle('resenas-dejar', j.resenar);
      sec.hidden = false;
    }).catch(function () { /* sin reseñas */ });
  })();
