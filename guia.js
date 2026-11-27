/* Guía animada en pixel art (8/16 bits) del diagnóstico a distancia.
   Todo se dibuja aquí con rectángulos sobre un lienzo de 192x120 que se agranda sin suavizar:
   sin imágenes, sin fuentes externas, sin seguimiento. */
(function () {
  'use strict';
  var cv = document.getElementById('guia-lienzo');
  if (!cv || !cv.getContext) return;
  var W = 192, H = 120;
  var ctx = cv.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  var cap = document.getElementById('guia-texto');
  var btnPlay = document.getElementById('guia-play');
  var btnAnt = document.getElementById('guia-ant');
  var btnSig = document.getElementById('guia-sig');
  var puntos = document.getElementById('guia-puntos');

  // Paleta
  var C = {
    negro: '#0b0d17', blanco: '#fff1e8', gris: '#c2c3c7', grisO: '#5f574f', marino: '#1d2b53',
    azul: '#29adff', cian: '#22d3ee', violeta: '#9b5cff', verde: '#00e436', verdeO: '#008751',
    amarillo: '#ffec27', naranjo: '#ffa300', rojo: '#ff004d', madera: '#ab5236', maderaO: '#6b3020',
    beige: '#e8d9b5', beigeO: '#b8a98a', teal: '#127a80', noche: '#0b1a3a', pantalla: '#222831'
  };

  // Fuente de 5x7
  var FUENTE = {};
  ('A 01110.10001.10001.11111.10001.10001.10001|B 11110.10001.10001.11110.10001.10001.11110|' +
   'C 01110.10001.10000.10000.10000.10001.01110|D 11110.10001.10001.10001.10001.10001.11110|' +
   'E 11111.10000.10000.11110.10000.10000.11111|F 11111.10000.10000.11110.10000.10000.10000|' +
   'G 01110.10001.10000.10111.10001.10001.01111|H 10001.10001.10001.11111.10001.10001.10001|' +
   'I 01110.00100.00100.00100.00100.00100.01110|J 00111.00010.00010.00010.00010.10010.01100|' +
   'K 10001.10010.10100.11000.10100.10010.10001|L 10000.10000.10000.10000.10000.10000.11111|' +
   'M 10001.11011.10101.10101.10001.10001.10001|N 10001.10001.11001.10101.10011.10001.10001|' +
   'O 01110.10001.10001.10001.10001.10001.01110|P 11110.10001.10001.11110.10000.10000.10000|' +
   'Q 01110.10001.10001.10001.10101.10010.01101|R 11110.10001.10001.11110.10100.10010.10001|' +
   'S 01111.10000.10000.01110.00001.00001.11110|T 11111.00100.00100.00100.00100.00100.00100|' +
   'U 10001.10001.10001.10001.10001.10001.01110|V 10001.10001.10001.10001.10001.01010.00100|' +
   'W 10001.10001.10001.10101.10101.10101.01010|X 10001.10001.01010.00100.01010.10001.10001|' +
   'Y 10001.10001.01010.00100.00100.00100.00100|Z 11111.00001.00010.00100.01000.10000.11111|' +
   '0 01110.10001.10011.10101.11001.10001.01110|1 00100.01100.00100.00100.00100.00100.01110|' +
   '2 01110.10001.00001.00010.00100.01000.11111|3 11111.00010.00100.00010.00001.10001.01110|' +
   '4 00010.00110.01010.10010.11111.00010.00010|5 11111.10000.11110.00001.00001.10001.01110|' +
   '6 00110.01000.10000.11110.10001.10001.01110|7 11111.00001.00010.00100.01000.01000.01000|' +
   '8 01110.10001.10001.01110.10001.10001.01110|9 01110.10001.10001.01111.00001.00010.01100|' +
   '. 00000.00000.00000.00000.00000.01100.01100|: 00000.01100.01100.00000.01100.01100.00000|' +
   '- 00000.00000.00000.11111.00000.00000.00000|/ 00001.00010.00010.00100.01000.01000.10000|' +
   '! 00100.00100.00100.00100.00100.00000.00100|? 01110.10001.00001.00010.00100.00000.00100|' +
   '% 11001.11010.00010.00100.01000.01011.10011|, 00000.00000.00000.00000.01100.00100.01000|' +
   '_ 00000.00000.00000.00000.00000.00000.11111|* 00000.00001.00010.10100.01000.00000.00000|' +
   '# 00000.00000.00000.00100.00000.00000.00000').split('|').forEach(function (d) {
    FUENTE[d.charAt(0)] = d.substring(2).split('.');
  });

  function R(x, y, w, h, c) { ctx.fillStyle = c; ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h)); }
  function T(s, x, y, c, e) {
    e = e || 1; s = String(s).toUpperCase(); ctx.fillStyle = c;
    for (var i = 0; i < s.length; i++) {
      var g = FUENTE[s.charAt(i)];
      if (g) for (var f = 0; f < 7; f++) for (var k = 0; k < 5; k++) if (g[f].charAt(k) === '1') ctx.fillRect(Math.round(x) + (i * 6 + k) * e, Math.round(y) + f * e, e, e);
    }
  }
  function anchoT(s, e) { return (String(s).length * 6 - 1) * (e || 1); }
  function Tc(s, cx, y, c, e) { T(s, cx - anchoT(s, e) / 2, y, c, e); }
  function lim(t) { return t < 0 ? 0 : t > 1 ? 1 : t; }
  function tramo(t, a, b) { return lim((t - a) / (b - a)); }
  function suave(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; }
  function mezcla(a, b, t) { return a + (b - a) * t; }
  function parpadea(ms, p) { return Math.floor(ms / (p || 400)) % 2 === 0; }

  // Cursor (1 = negro, 2 = blanco)
  var CURSOR = ['1', '11', '121', '1221', '12221', '122221', '1222221', '12222221', '1222111', '12121', '11 121', '1  121', '    1'];
  function cursor(x, y) {
    for (var f = 0; f < CURSOR.length; f++) for (var k = 0; k < CURSOR[f].length; k++) {
      var p = CURSOR[f].charAt(k);
      if (p === '1') R(x + k, y + f, 1, 1, C.negro); else if (p === '2') R(x + k, y + f, 1, 1, C.blanco);
    }
  }
  function clic(x, y, p) {
    if (p <= 0 || p >= 1) return;
    var r = 2 + Math.round(p * 7);
    ctx.strokeStyle = C.amarillo; ctx.lineWidth = 1;
    ctx.strokeRect(Math.round(x - r) + 0.5, Math.round(y - r) + 0.5, r * 2, r * 2);
  }
  function mover(x0, y0, x1, y1, t) { var e = suave(lim(t)); return [mezcla(x0, x1, e), mezcla(y0, y1, e)]; }

  // Ventana estilo 16 bits
  function ventana(x, y, w, h, titulo, colorTitulo) {
    R(x + 2, y + 2, w, h, 'rgba(0,0,0,.35)');
    R(x, y, w, h, C.negro); R(x, y, w - 1, h - 1, C.blanco); R(x + 1, y + 1, w - 2, h - 2, C.grisO); R(x + 1, y + 1, w - 3, h - 3, C.gris);
    R(x + 3, y + 3, w - 6, 9, colorTitulo || C.marino);
    T(titulo, x + 5, y + 4, C.blanco);
    R(x + w - 12, y + 4, 7, 7, C.gris); R(x + w - 10, y + 6, 3, 3, C.grisO);
  }
  function boton(x, y, w, h, txt, apretado, color, colorTxt) {
    R(x, y, w, h, C.negro);
    R(x, y, w - 1, h - 1, apretado ? C.grisO : C.blanco);
    R(x + 1, y + 1, w - 2, h - 2, apretado ? C.blanco : C.grisO);
    R(x + 1, y + 1, w - 3, h - 3, color || C.gris);
    Tc(txt, x + w / 2 + (apretado ? 1 : 0), y + (h - 7) / 2 + (apretado ? 1 : 0), colorTxt || C.negro);
  }

  // Íconos
  function carpeta(x, y, zip) {
    R(x, y + 2, 7, 3, C.naranjo); R(x, y + 4, 16, 11, C.naranjo); R(x + 1, y + 5, 14, 9, C.amarillo);
    if (zip) { for (var i = 0; i < 9; i += 2) R(x + 7, y + 5 + i, 2, 1, C.grisO); R(x + 6, y + 9, 4, 3, C.grisO); }
  }
  function archivoCmd(x, y) {
    R(x, y, 14, 14, C.negro); R(x + 1, y + 1, 12, 12, C.gris); R(x + 1, y + 1, 12, 3, C.marino);
    R(x + 4, y + 6, 6, 6, C.grisO); R(x + 5, y + 7, 4, 4, C.gris); R(x + 6, y + 8, 2, 2, C.grisO);
    R(x + 6, y + 5, 2, 1, C.grisO); R(x + 6, y + 12, 2, 1, C.grisO); R(x + 3, y + 8, 1, 2, C.grisO); R(x + 10, y + 8, 1, 2, C.grisO);
  }
  function hoja(x, y) { R(x, y, 11, 14, C.negro); R(x + 1, y + 1, 9, 12, C.blanco); for (var i = 0; i < 4; i++) R(x + 2, y + 3 + i * 2, 7, 1, C.grisO); }
  function kitdiag(x, y) {
    R(x, y, 12, 15, C.negro); R(x + 1, y + 1, 10, 13, C.blanco); R(x + 1, y + 1, 10, 3, C.violeta);
    R(x + 4, y + 6, 4, 3, C.negro); R(x + 5, y + 7, 2, 1, C.blanco); R(x + 3, y + 9, 6, 4, C.naranjo); R(x + 5, y + 10, 2, 2, C.negro);
  }
  function brillo(x, y, ms) {
    var f = Math.floor(ms / 150) % 3;
    var c = [C.blanco, C.amarillo, C.cian][f];
    R(x, y - 3, 1, 7, c); R(x - 3, y, 7, 1, c);
  }
  function etiqueta(txt, cx, y) { var w = anchoT(txt); R(cx - w / 2 - 1, y - 1, w + 2, 9, 'rgba(0,0,0,.35)'); Tc(txt, cx, y, C.blanco); }

  // Escritorio
  function escritorio(ms) {
    R(0, 0, W, H, C.teal);
    for (var y = 0; y < H - 9; y += 4) for (var x = (y / 4) % 2 * 2; x < W; x += 4) R(x, y, 1, 1, 'rgba(255,255,255,.06)');
    R(0, H - 9, W, 9, C.gris); R(0, H - 9, W, 1, C.blanco);
    R(2, H - 8, 28, 7, C.gris); R(2, H - 8, 28, 1, C.blanco); R(2, H - 2, 28, 1, C.negro);
    R(4, H - 6, 3, 3, C.rojo); R(7, H - 6, 3, 3, C.verde); R(4, H - 3, 3, 1, C.azul); R(7, H - 3, 3, 1, C.amarillo);
    T('INICIO', 12, H - 8, C.negro);
    R(W - 32, H - 8, 30, 7, C.grisO); R(W - 31, H - 7, 28, 5, C.gris);
    T('12:00', W - 30, H - 8, C.negro);
    // papelera
    R(8, 8, 10, 12, C.gris); R(7, 7, 12, 2, C.grisO); R(10, 10, 1, 8, C.grisO); R(13, 10, 1, 8, C.grisO); R(16, 10, 1, 8, C.grisO);
  }

  // Cuarto con el computador antiguo (se dibuja una vez y se usa para el zoom)
  var cuarto = document.createElement('canvas'); cuarto.width = W; cuarto.height = H;
  var PANT = { x: 72, y: 30, w: 48, h: 30 };
  (function () {
    var real = ctx; ctx = cuarto.getContext('2d');
    R(0, 0, W, H, C.marino);
    for (var i = 0; i < W; i += 12) R(i, 0, 1, 84, 'rgba(255,255,255,.04)');
    // ventana con estrellas
    R(12, 12, 36, 28, C.gris); R(14, 14, 32, 24, C.noche); R(29, 14, 2, 24, C.gris); R(14, 25, 32, 2, C.gris);
    R(38, 16, 5, 5, C.amarillo); R(40, 16, 3, 3, C.noche);
    [[17, 17], [24, 20], [19, 30], [34, 31], [42, 33], [26, 34]].forEach(function (p) { R(p[0], p[1], 1, 1, C.blanco); });
    // lámpara
    R(160, 30, 3, 54, C.grisO); R(150, 22, 22, 10, C.naranjo); R(152, 32, 18, 2, C.amarillo);
    // escritorio
    R(0, 84, W, 6, C.madera); R(0, 90, W, 30, C.maderaO); R(0, 84, W, 1, '#d97a4a');
    R(8, 90, 4, 30, '#4f2217'); R(W - 12, 90, 4, 30, '#4f2217');
    // planta
    R(20, 72, 16, 12, C.naranjo); R(19, 72, 18, 2, '#d97a00');
    [[27, 54, 2, 18], [22, 58, 6, 3], [29, 60, 7, 3], [20, 64, 8, 3], [29, 66, 8, 3], [25, 50, 3, 6]].forEach(function (p) { R(p[0], p[1], p[2], p[3], C.verdeO); });
    // taza
    R(46, 77, 7, 7, C.blanco); R(53, 79, 2, 3, C.blanco); R(47, 78, 5, 1, C.madera);
    // torre
    R(138, 36, 24, 48, C.beigeO); R(138, 36, 23, 47, C.beige); R(142, 42, 16, 3, C.grisO); R(142, 48, 16, 3, C.grisO); R(144, 72, 3, 3, C.verde);
    // monitor
    R(62, 20, 68, 52, C.beigeO); R(62, 20, 67, 51, C.beige);
    R(68, 26, 56, 38, C.pantalla);
    R(PANT.x, PANT.y, PANT.w, PANT.h, C.teal); R(PANT.x, PANT.y + PANT.h - 3, PANT.w, 3, C.gris);
    R(PANT.x + 2, PANT.y + 2, 3, 3, C.gris);
    R(66, 67, 4, 2, C.verde); R(110, 67, 14, 2, C.beigeO);
    R(88, 72, 16, 6, C.beigeO); R(78, 78, 36, 5, C.beige);
    // teclado y mouse
    R(64, 85, 64, 6, C.beigeO); R(64, 85, 63, 5, C.beige);
    for (var k = 66; k < 126; k += 4) R(k, 86, 3, 1, C.beigeO), R(k + 1, 88, 3, 1, C.beigeO);
    R(134, 86, 7, 5, C.beige); R(137, 86, 1, 2, C.beigeO);
    ctx = real;
  })();

  // ---------------------------------------------------------------- escenas
  var ESCENAS = [
    { d: 5200, txt: 'Este es tu computador. Veamos cómo se hace el diagnóstico, paso a paso.', f: function (t, ms) {
      var z = suave(tramo(t, 0.45, 1));
      var cx = mezcla(0, PANT.x, z), cy = mezcla(0, PANT.y, z), cw = mezcla(W, PANT.w, z), ch = mezcla(H, PANT.h, z);
      ctx.drawImage(cuarto, cx, cy, cw, ch, 0, 0, W, H);
      if (t < 0.45) {
        Tc('ASI SE HACE', W / 2 + 1, 5, C.negro, 2); Tc('ASI SE HACE', W / 2, 4, C.amarillo, 2);
        if (parpadea(ms, 350)) Tc('DIAGNOSTICO A DISTANCIA', W / 2, 104, C.cian);
      }
    } },
    { d: 6000, txt: '1. En esta página, haz clic en «Descargar» (pesa menos de 1 MB).', f: function (t, ms) {
      escritorio(ms);
      ventana(14, 6, 164, 98, 'NAVEGADOR');
      R(17, 19, 158, 9, C.blanco); R(17, 19, 158, 1, C.grisO); T('ISGROM1.GITHUB.IO/KIT', 20, 20, C.marino);
      R(17, 29, 158, 72, '#f4f6fb');
      Tc('DIAGNOSTICO', 96, 34, C.marino, 2); Tc('A DISTANCIA', 96, 50, C.violeta);
      var ap = t > 0.5 && t < 0.58;
      R(50, 64, 92, 15, C.negro); R(50, 64, 91, 14, ap ? C.violeta : C.cian); R(51 + 45, 65, 45, 13, ap ? C.cian : C.violeta);
      Tc('DESCARGAR', 96 + (ap ? 1 : 0), 68 + (ap ? 1 : 0), C.blanco);
      if (t > 0.6) {
        R(17, 88, 158, 12, C.gris); R(17, 88, 158, 1, C.grisO);
        carpeta(20, 87, true);
        T('DIAGNOSTICO.ZIP', 40, 90, C.negro);
        R(132, 91, 40, 5, C.grisO); R(133, 92, 38 * tramo(t, 0.6, 0.95), 3, C.verde);
      }
      var p = mover(160, 112, 98, 72, tramo(t, 0.1, 0.48));
      cursor(p[0], p[1]); clic(p[0], p[1], tramo(t, 0.5, 0.62));
    } },
    { d: 6000, txt: '2. Extrae el ZIP que bajaste: clic derecho → Extraer todo → Extraer.', f: function (t, ms) {
      escritorio(ms);
      // Clic DERECHO en el ZIP → «Extraer todo…» → «Extraer» (no doble clic: abierto adentro del ZIP no funciona).
      carpeta(40, 58, true); etiqueta('DIAGNOSTICO.ZIP', 48, 77);
      var p;
      if (t < 0.62) {
        p = mover(150, 100, 48, 64, tramo(t, 0.05, 0.3));
        if (t > 0.35) {
          R(64, 30, 98, 36, C.negro); R(64, 30, 97, 35, C.blanco);
          T('ABRIR', 68, 33, C.grisO);
          if (t > 0.5) R(65, 42, 95, 11, C.azul);
          T('EXTRAER TODO...', 68, 44, t > 0.5 ? C.blanco : C.negro);
          T('COPIAR', 68, 56, C.grisO);
        }
        if (t > 0.42) p = mover(48, 64, 90, 47, tramo(t, 0.42, 0.52));
      } else {
        ventana(30, 20, 150, 70, 'EXTRAER');
        R(33, 33, 144, 54, C.blanco); T('SE CREA LA CARPETA', 37, 38, C.negro); T('DIAGNOSTICO', 37, 49, C.marino);
        var ap = t > 0.85;
        R(124, 70, 50, 13, ap ? C.violeta : C.azul); Tc('EXTRAER', 149, 73, C.blanco);
        if (t > 0.92) brillo(149, 60, ms);
        p = mover(90, 47, 149, 76, tramo(t, 0.62, 0.8));
      }
      cursor(p[0], p[1]);
      clic(48, 64, tramo(t, 0.3, 0.38)); clic(149, 76, tramo(t, 0.82, 0.9));
    } },
    { d: 6000, txt: '3. En la carpeta que se abre hay un solo archivo: doble clic en DIAGNOSTICO.cmd.', f: function (t, ms) {
      escritorio(ms);
      ventana(24, 10, 144, 90, 'DIAGNOSTICO');
      R(27, 23, 138, 74, C.blanco);
      var filas = [['cmd', 'DIAGNOSTICO.CMD']];
      filas.forEach(function (f, i) {
        var y = 27 + i * 17;
        if (i === 0 && t > 0.5) R(28, y - 2, 136, 17, C.azul);
        if (f[0] === 'carpeta') carpeta(32, y - 2, false); else if (f[0] === 'cmd') archivoCmd(33, y - 1); else hoja(34, y - 1);
        T(f[1], 54, y + 3, i === 0 && t > 0.5 ? C.blanco : C.negro);
      });
      var p = mover(150, 110, 80, 32, tramo(t, 0.1, 0.45));
      cursor(p[0], p[1]); clic(p[0], p[1], tramo(t, 0.5, 0.6)); clic(p[0], p[1], tramo(t, 0.6, 0.7));
    } },
    { d: 7500, txt: '4. Comprueba que arriba diga ✓ Paquete de ISGROM · 54A8-32F4, elige rápida o con temperatura, escribe tu nombre, marca «Acepto» y haz clic en «Empezar».', f: function (t, ms) {
      escritorio(ms);
      ventana(14, 4, 164, 104, 'DIAGNOSTICO PARA ISGROM');
      R(17, 15, 158, 90, C.blanco);
      // logo: media esfera
      R(22, 26, 18, 1, C.violeta); R(24, 21, 14, 5, C.gris); R(26, 19, 10, 2, C.gris); R(28, 18, 6, 1, C.gris); R(20, 27, 22, 2, C.cian);
      var sello = t > 0.15 && t < 0.4 ? parpadea(ms, 200) : true;
      R(108, 18, 64, 9, sello ? '#d1fae5' : C.verde); T('*54A8-32F4', 110, 19, C.verdeO);
      T('HOLA!', 46, 20, C.marino);
      T('* MIDE TU EQUIPO', 22, 36, C.verdeO);
      T('X NO MIRA TUS ARCHIVOS', 22, 46, C.rojo);
      T('X NO USA INTERNET', 22, 56, C.rojo);
      R(22, 70, 9, 9, C.negro); R(23, 71, 7, 7, C.blanco);
      var marcado = t > 0.5;
      if (marcado) { R(24, 75, 2, 2, C.verdeO); R(26, 76, 2, 2, C.verdeO); R(28, 72, 2, 4, C.verdeO); }
      T('ACEPTO', 35, 71, C.negro);
      var listo = marcado, ap = t > 0.8 && t < 0.88;
      if (listo) { R(110, 86, 62, 15, C.negro); R(110, 86, 61, 14, ap ? C.violeta : C.cian); R(141, 87, 30, 13, ap ? C.cian : C.violeta); Tc('EMPEZAR', 141 + (ap ? 1 : 0), 90 + (ap ? 1 : 0), C.blanco); }
      else boton(110, 86, 62, 15, 'EMPEZAR', false, C.gris, C.grisO);
      var p = t < 0.55 ? mover(170, 112, 26, 74, tramo(t, 0.3, 0.48)) : mover(26, 74, 140, 93, tramo(t, 0.55, 0.78));
      cursor(p[0], p[1]); clic(26, 74, tramo(t, 0.48, 0.58)); clic(140, 93, tramo(t, 0.8, 0.9));
    } },
    { d: 6000, txt: '5. Solo si eliges la prueba de temperatura, Windows te pide permiso: haz clic en «Sí». Es normal.', f: function (t, ms) {
      escritorio(ms);
      for (var y = 0; y < H; y++) for (var x = y % 2; x < W; x += 2) R(x, y, 1, 1, 'rgba(0,0,0,.55)');
      R(24, 22, 144, 72, C.negro); R(25, 23, 142, 70, C.blanco);
      R(25, 23, 142, 12, C.azul); T('CONTROL DE CUENTAS', 30, 26, C.blanco);
      T('PERMITIR QUE ESTA APP', 32, 42, C.negro); T('HAGA CAMBIOS?', 32, 51, C.negro);
      R(32, 61, 128, 1, C.gris); T('ISGROM - DIAGNOSTICO', 32, 65, C.grisO);
      var ap = t > 0.62 && t < 0.7;
      boton(60, 76, 40, 13, 'SI', ap, C.azul, C.blanco); boton(106, 76, 40, 13, 'NO', false);
      var p = mover(170, 112, 80, 82, tramo(t, 0.15, 0.55));
      cursor(p[0], p[1]); clic(p[0], p[1], tramo(t, 0.62, 0.74));
    } },
    { d: 8500, txt: '6. La revisión rápida tarda unos 3 minutos. La de temperatura, unos 25: ahí no cierres los programas de medición.', f: function (t, ms) {
      escritorio(ms);
      ventana(6, 6, 104, 62, 'HWINFO');
      R(9, 18, 98, 47, C.negro);
      for (var gx = 9; gx < 107; gx += 10) R(gx, 18, 1, 47, '#11331b');
      var prev = null;
      for (var x = 0; x < 96; x++) {
        var k = x + ms / 60;
        var v = 30 + Math.sin(k / 6) * 6 + Math.sin(k / 2.3) * 3 + (x > 40 ? 8 * tramo(t, 0, 0.5) : 0);
        var y = 62 - v * 0.7;
        R(10 + x, y, 1, 2, C.verde);
      }
      T('CPU 59 C', 12, 20, C.amarillo);
      ventana(86, 38, 100, 52, 'OCCT');
      R(89, 50, 94, 37, '#1a1c2c');
      T('PRUEBA CPU', 93, 54, C.blanco);
      R(93, 66, 86, 8, C.grisO); R(94, 67, 84 * tramo(t, 0, 1), 6, C.naranjo);
      T(Math.min(100, Math.round(tramo(t, 0, 1) * 100)) + '%', 93, 77, C.naranjo);
      // reloj de arena y aviso
      var g = Math.floor(ms / 500) % 2;
      R(20, 80, 9, 2, C.beige); R(20, 94, 9, 2, C.beige); R(21, 82, 7, 3, g ? C.amarillo : C.blanco); R(23, 85, 3, 3, C.amarillo); R(21, 88, 7, 6, g ? C.blanco : C.amarillo);
      T('20 MIN', 33, 82, C.blanco);
      if (parpadea(ms, 500)) T('NO TOCAR', 33, 92, C.amarillo);
    } },
    { d: 7000, txt: '7. Al terminar se abre tu informe y queda un archivo .kitdiag (va cifrado: solo ISGROM lo puede abrir).', f: function (t, ms) {
      escritorio(ms);
      ventana(50, 4, 136, 102, 'TU INFORME');
      R(53, 15, 130, 88, '#f4f6fb');
      var n = Math.round(82 * tramo(t, 0.05, 0.5));
      R(58, 24, 34, 34, C.verdeO); R(60, 26, 30, 30, '#f4f6fb');
      Tc(String(n), 75, 34, C.verdeO, 2);
      T('SALUD', 60, 62, C.marino);
      var barras = [['DISCO', C.verde, 0.9], ['TEMP', C.amarillo, 0.6], ['RAM', C.verde, 0.8], ['SEGURIDAD', C.verde, 0.95]];
      barras.forEach(function (b, i) {
        var y = 26 + i * 12;
        T(b[0], 98, y, C.marino);
        R(98, y + 8, 80, 2, C.gris); R(98, y + 8, 80 * b[2] * tramo(t, 0.1 + i * 0.08, 0.5 + i * 0.08), 2, b[1]);
      });
      T('LO QUE SIGUE:', 58, 78, C.violeta); T('ENVIALO A ISGROM', 58, 88, C.marino);
      if (t > 0.55) { kitdiag(16, 40); Tc('KITDIAG', 22, 58, C.blanco); if (t < 0.9) brillo(28, 38, ms); }
    } },
    { d: 7500, txt: '8. Si dejaste marcada la casilla del envío, a ISGROM le llega solo; si no, mándalo tú por WhatsApp. ¡Listo! Él te responde con lo que tiene tu equipo.', f: function (t, ms) {
      escritorio(ms);
      kitdiag(20, 34); Tc('KITDIAG', 26, 52, C.blanco);
      // teléfono
      R(124, 6, 50, 100, C.negro); R(127, 12, 44, 86, '#ece5dd');
      R(127, 12, 44, 12, C.verdeO); T('ISGROM', 131, 15, C.blanco);
      R(144, 100, 10, 2, C.grisO);
      // vuela el archivo
      var v = tramo(t, 0.15, 0.6);
      if (v > 0 && v < 1) {
        var x = mezcla(26, 150, v), y = mezcla(40, 50, v) - Math.sin(v * Math.PI) * 26;
        kitdiag(x - 6, y - 7);
        R(x - 10 - 4, y, 3, 1, C.amarillo); R(x - 16 - 4, y + 2, 2, 1, C.amarillo);
      }
      if (t >= 0.6) {
        R(136, 36, 32, 22, '#d9fdd3'); kitdiag(140, 39); T('OK', 155, 44, C.verdeO);
        R(158, 52, 2, 2, C.azul); R(162, 52, 2, 2, C.azul);
      }
      if (t > 0.75) { R(129, 64, 40, 14, C.blanco); T('GENIAL', 131, 68, C.marino); }
      if (t > 0.8 && parpadea(ms, 300)) Tc('LISTO!', 62, 76, C.amarillo, 2);
    } }
  ];

  // ---------------------------------------------------------------- reproducción
  var actual = 0, inicio = 0, pausado = false, visible = true, ultimo = 0, pausaMs = 0;
  var reducido = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  ESCENAS.forEach(function (_, i) {
    var b = document.createElement('button');
    b.type = 'button'; b.setAttribute('aria-label', 'Paso ' + i);
    b.addEventListener('click', function () { ir(i); });
    puntos.appendChild(b);
  });
  function ir(i) {
    actual = (i + ESCENAS.length) % ESCENAS.length;
    inicio = performance.now(); pausaMs = pausado ? ESCENAS[actual].d * 0.98 : 0;   // en pausa se ve el paso terminado
    cap.textContent = ESCENAS[actual].txt;
    var bs = puntos.querySelectorAll('button');
    for (var k = 0; k < bs.length; k++) bs[k].className = k === actual ? 'activo' : '';
    if (pausado) dibujar(performance.now());
  }
  function poner(p) {
    pausado = p;
    btnPlay.textContent = p ? '▶' : '❚❚';
    btnPlay.setAttribute('aria-label', p ? 'Reproducir' : 'Pausar');
  }
  function lineas() { for (var y = 1; y < H; y += 2) R(0, y, W, 1, 'rgba(0,0,0,.10)'); }
  function dibujar(ahora) {
    var e = ESCENAS[actual];
    var trans = pausado ? (reducido ? e.d * 0.98 : pausaMs) : ahora - inicio;
    var t = lim(trans / e.d);
    e.f(t, ahora);
    lineas();
  }
  function cuadro(ahora) {
    requestAnimationFrame(cuadro);
    if (!visible || ahora - ultimo < 50) return;   // ~20 cuadros por segundo: se ve más "de época"
    ultimo = ahora;
    if (pausado) return;
    if (ahora - inicio > ESCENAS[actual].d + 600) { ir(actual + 1); return; }
    dibujar(ahora);
  }
  btnPlay.addEventListener('click', function () {
    if (pausado) { inicio = performance.now() - pausaMs; poner(false); }
    else { pausaMs = performance.now() - inicio; poner(true); }
  });
  btnAnt.addEventListener('click', function () { ir(actual - 1); });
  btnSig.addEventListener('click', function () { ir(actual + 1); });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (es) { visible = es[0].isIntersecting; }, { threshold: 0.2 }).observe(cv);
  }
  // Para revisar los cuadros (pruebas): guiaKit.cuadro(escena, t) dibuja ese momento.
  window.guiaKit = { escenas: ESCENAS.length, info: ESCENAS.map(function (e) { return { d: e.d, txt: e.txt }; }), cuadro: function (i, t, ms) { ESCENAS[i].f(t, ms || 1000); lineas(); } };
  poner(!!reducido);
  ir(0);
  if (reducido) dibujar(performance.now());
  requestAnimationFrame(cuadro);
})();
