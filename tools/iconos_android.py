"""Genera los íconos y la imagen de arranque de la app Android desde icons/logo-maestro.svg.

Uso (desde la raíz del repo):  py tools/iconos_android.py [--chrome RUTA]

No hay Pillow ni cairosvg en este equipo: el SVG se dibuja en un <canvas> de Chrome headless
(el chrome.exe del sistema, con un perfil temporal para no tocar el del usuario), que respeta
los degradados, máscaras y filtros del logo. Los PNG vuelven como base64 en el DOM y se
escriben con la biblioteca estándar.

Escribe en android/app/src/main/res/:
  mipmap-<d>/ic_launcher_foreground.png   capa frontal adaptativa, 108 dp; el logo dentro del
                                          círculo seguro de 66 dp (mdpi 108 px … xxxhdpi 432 px)
  mipmap-<d>/ic_launcher_monochrome.png   capa del ícono temático (Android 13+): anillo y
                                          emblema en blanco, misma geometría
  mipmap-<d>/ic_launcher.png, _round.png  íconos legacy (API 24-25), 48 dp (mdpi 48 … 192 px)
  drawable-<d>/splash_logo.png            logo de la pantalla de arranque anterior a Android 12
  values/ic_launcher_background.xml       color de marca del fondo del ícono

Los XML que los usan (mipmap-anydpi-v26/ic_launcher*.xml, drawable/splash.xml, styles.xml)
se editan a mano. tools/ no se publica: el deploy (.github/workflows/pages.yml) copia una
lista permitida.
"""
import base64
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
LOGO = RAIZ / 'icons' / 'logo-maestro.svg'
RES = RAIZ / 'android' / 'app' / 'src' / 'main' / 'res'
CHROMES = [
    Path(r'C:\Program Files\Google\Chrome\Application\chrome.exe'),
    Path(r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'),
    Path(r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'),
]

# Fondo del ícono maskable de la PWA (icons/icon-maskable-512.png, color único del borde).
COLOR_MARCA = '#5C1F2E'
DENSIDADES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# En el viewBox de 100 la moneda mide r=38 más el trazo y el desenfoque del borde: se toma
# 78 de diámetro para que quepa entera en el círculo que se pida.
DIAMETRO_MONEDA = 78
SEGURO_DP = 66        # círculo seguro de la capa adaptativa de 108 dp
CAPA_DP = 108
LEGACY_DP = 48
LEGACY_MONEDA_DP = 34
SPLASH_DP = 192       # moneda de ~150 dp, como el ícono de la SplashScreen de Android 12+


def svg_monocromo(svg):
    """Anillo de la moneda y emblema (columna) en blanco, sin degradados ni filtros: el sistema
    usa solo el alfa de esta capa y le pone el color del tema."""
    caminos = re.findall(r'<path d="(M28,30h44[^"]*)"', svg)
    if not caminos:
        sys.exit('logo-maestro.svg: no encuentro el trazado del emblema (M28,30h44…)')
    emblema = max(caminos, key=len)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="1024" height="1024">'
            '<circle cx="50" cy="50" r="36.5" fill="none" stroke="#fff" stroke-width="3"/>'
            f'<path d="{emblema}" fill="#fff"/></svg>')


def trabajos():
    """Lista de {ruta, lado, fondo, forma, moneda, img}: lado y moneda en px."""
    t = []
    for d, f in DENSIDADES.items():
        capa, seguro = round(CAPA_DP * f), SEGURO_DP * f
        t.append(dict(ruta=f'mipmap-{d}/ic_launcher_foreground.png', lado=capa, moneda=seguro, img='logo'))
        t.append(dict(ruta=f'mipmap-{d}/ic_launcher_monochrome.png', lado=capa, moneda=seguro, img='mono'))
        leg, mon = round(LEGACY_DP * f), LEGACY_MONEDA_DP * f
        t.append(dict(ruta=f'mipmap-{d}/ic_launcher.png', lado=leg, moneda=mon, img='logo',
                      fondo=COLOR_MARCA, forma='cuadrado', margen=2 * f, radio=8 * f))
        t.append(dict(ruta=f'mipmap-{d}/ic_launcher_round.png', lado=leg, moneda=mon, img='logo',
                      fondo=COLOR_MARCA, forma='circulo', margen=2 * f))
        sp = round(SPLASH_DP * f)
        t.append(dict(ruta=f'drawable-{d}/splash_logo.png', lado=sp, moneda=sp * DIAMETRO_MONEDA / 100, img='logo'))
    return t


PAGINA = """<!doctype html><meta charset="utf-8"><pre id="salida">pendiente</pre><script>
const IMGS = %s, TRABAJOS = %s, DIAM = %s;
async function cargar(src){ const i = new Image(); i.src = src; await i.decode(); return i; }
(async () => {
  try{
    const imgs = {};
    for(const k in IMGS) imgs[k] = await cargar(IMGS[k]);
    const res = {};
    for(const t of TRABAJOS){
      const c = document.createElement('canvas'); c.width = c.height = t.lado;
      const x = c.getContext('2d');
      if(t.fondo){
        x.fillStyle = t.fondo; x.beginPath();
        const m = t.margen, l = t.lado - 2*m;
        if(t.forma === 'circulo') x.arc(t.lado/2, t.lado/2, l/2, 0, 2*Math.PI);
        else x.roundRect(m, m, l, l, t.radio);
        x.fill();
      }
      // El viewBox entero (100) se escala para que la moneda (DIAM) mida t.moneda px.
      const s = t.moneda * 100 / DIAM;
      x.drawImage(imgs[t.img], (t.lado - s)/2, (t.lado - s)/2, s, s);
      res[t.ruta] = c.toDataURL('image/png').split(',')[1];
    }
    document.getElementById('salida').textContent = 'OK' + JSON.stringify(res);
  }catch(e){ document.getElementById('salida').textContent = 'ERROR ' + e; }
})();
</script>"""


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    args = sys.argv[1:]
    chrome = Path(args[args.index('--chrome') + 1]) if '--chrome' in args else next((c for c in CHROMES if c.is_file()), None)
    if not chrome or not chrome.is_file():
        sys.exit('No encuentro Chrome/Edge; indícalo con --chrome RUTA')

    svg = LOGO.read_text(encoding='utf-8')
    data = lambda s: 'data:image/svg+xml;base64,' + base64.b64encode(s.encode('utf-8')).decode('ascii')
    lista = trabajos()
    html = PAGINA % (json.dumps({'logo': data(svg), 'mono': data(svg_monocromo(svg))}),
                     json.dumps(lista), DIAMETRO_MONEDA)

    tmp = Path(tempfile.mkdtemp(prefix='telora-iconos-'))
    try:
        pagina = tmp / 'iconos.html'
        pagina.write_text(html, encoding='utf-8')
        salida = subprocess.run(
            [str(chrome), '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
             f'--user-data-dir={tmp / "perfil"}', '--virtual-time-budget=20000', '--dump-dom', pagina.as_uri()],
            capture_output=True, text=True, encoding='utf-8', timeout=120).stdout
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    m = re.search(r'<pre id="salida">(.*?)</pre>', salida, re.S)
    texto = m.group(1) if m else ''
    if not texto.startswith('OK'):
        sys.exit('Chrome no devolvió los PNG: ' + (texto[:300] or salida[:300]))
    pngs = json.loads(texto[2:].replace('&quot;', '"').replace('&amp;', '&'))
    if sorted(pngs) != sorted(t['ruta'] for t in lista):
        sys.exit('Chrome devolvió una lista de PNG distinta de la pedida')

    for ruta, b64 in sorted(pngs.items()):
        destino = RES / ruta
        destino.parent.mkdir(parents=True, exist_ok=True)
        destino.write_bytes(base64.b64decode(b64))
    (RES / 'values' / 'ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{COLOR_MARCA}</color>\n</resources>\n',
        encoding='utf-8', newline='\n')
    print(f'{len(pngs)} PNG escritos en {RES.relative_to(RAIZ)} con {chrome.name}; fondo del ícono {COLOR_MARCA}')


if __name__ == '__main__':
    main()
