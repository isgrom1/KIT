// Verificación del pasaporte (fuera del HTML por la política de seguridad).
  (function () {
    var zona = document.getElementById('zona'), entrada = document.getElementById('archivo');
    var res = document.getElementById('res'), det = document.getElementById('detalle');
    function b64aBytes(b64) { var s = atob(b64.trim()), a = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) { a[i] = s.charCodeAt(i); } return a; }
    function texto(t) { var d = document.createElement('div'); d.textContent = t; return d.innerHTML; }
    function mostrar(ok, msg) { res.className = ok ? 'ok' : 'mal'; res.textContent = msg; }
    function revisar(contenido) {
      det.innerHTML = '';
      var doc = new DOMParser().parseFromString(contenido, 'text/html');
      var nd = doc.getElementById('pasaporte-datos'), nf = doc.getElementById('pasaporte-firma');
      if (!nd || !nf) { mostrar(false, '✕ Este archivo no es un pasaporte de ISGROM.'); return; }
      var json = nd.textContent, firma = nf.textContent;
      if (!window.crypto || !crypto.subtle) { mostrar(false, 'Tu navegador no permite comprobar firmas. Prueba con Chrome, Edge o Firefox actualizados.'); return; }
      fetch('paquetes.json', { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (j) {
        if (!j.llave) { throw new Error('sin llave'); }
        return crypto.subtle.importKey('jwk', j.llave, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
      }).then(function (llave) {
        return crypto.subtle.verify('RSASSA-PKCS1-v1_5', llave, b64aBytes(firma), new TextEncoder().encode(json));
      }).then(function (valida) {
        if (!valida) { mostrar(false, '✕ La firma NO calza: el pasaporte fue modificado o no es de ISGROM.'); return; }
        var d = JSON.parse(json);
        mostrar(true, '✓ Pasaporte auténtico, firmado por ISGROM y sin cambios.');
        // Se muestra lo FIRMADO, no lo que dice el archivo por fuera (eso se podría editar).
        var filas = [['Temperatura máxima con carga', 'temperatura_max_c', ' °C'], ['Salud del disco', 'disco_salud_pct', ' %'], ['Salud de la batería', 'bateria_salud_pct', ' %'], ['Encendido', 'encendido_seg', ' s']];
        function v(m, k, u) { return m && m[k] !== undefined && m[k] !== null ? Math.round(m[k]) + u : '–'; }
        var html = '<p style="color:#0f172a">Esto es lo que firmó ISGROM. <b>Si el archivo dice otra cosa, vale lo de aquí.</b></p>' +
          '<p style="color:#0f172a;font-size:16px"><b>' + texto((d.equipo.fabricante || '') + ' ' + (d.equipo.modelo || '')) + '</b><br>Serie ' + texto(d.equipo.serie || '') +
          (d.equipo.cpu ? ' · ' + texto(d.equipo.cpu) : '') + ' · emitido el ' + texto(d.emitido || '') + '</p>';
        (d.atenciones || []).forEach(function (a) {
          html += '<div style="border-left:4px solid #06b6d4;padding:6px 12px;margin:10px 0;background:#f8fafc;color:#0f172a"><b>' + texto(a.fecha) + '</b> · ' + texto((a.motivos || []).join(', '));
          if ((a.hecho || []).length) { html += '<ul style="margin:4px 0">' + a.hecho.map(function (x) { return '<li>' + texto(x) + '</li>'; }).join('') + '</ul>'; }
          var t = filas.filter(function (f) { return (a.antes && a.antes[f[1]] != null) || (a.despues && a.despues[f[1]] != null); });
          if (t.length) { html += '<table style="font-size:13px;border-collapse:collapse"><tr><th></th><th style="padding:2px 10px">Antes</th><th style="padding:2px 10px">Después</th></tr>' + t.map(function (f) { return '<tr><td>' + f[0] + '</td><td style="padding:2px 10px">' + v(a.antes, f[1], f[2]) + '</td><td style="padding:2px 10px">' + v(a.despues, f[1], f[2]) + '</td></tr>'; }).join('') + '</table>'; }
          if (a.garantia) { html += '<div style="font-size:12px;color:#64748b">Garantía hasta el ' + texto(a.garantia) + '</div>'; }
          html += '</div>';
        });
        html += '<p>Compara la serie con la etiqueta de abajo del equipo: tiene que ser la misma.</p>';
        det.innerHTML = html;
      }).catch(function () { mostrar(false, 'No se pudo comprobar ahora (sin conexión con la página). Inténtalo de nuevo.'); });
    }
    function leer(f) { if (!f) { return; } var r = new FileReader(); r.onload = function () { revisar(String(r.result)); }; r.readAsText(f, 'utf-8'); }
    entrada.addEventListener('change', function () { leer(entrada.files[0]); });
    ['dragenter', 'dragover'].forEach(function (e) { zona.addEventListener(e, function (ev) { ev.preventDefault(); zona.classList.add('encima'); }); });
    ['dragleave', 'drop'].forEach(function (e) { zona.addEventListener(e, function (ev) { ev.preventDefault(); zona.classList.remove('encima'); }); });
    zona.addEventListener('drop', function (ev) { leer(ev.dataTransfer.files[0]); });
  })();
