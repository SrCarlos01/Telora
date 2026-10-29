"""Arma www/ (el webDir de Capacitor) con la misma lista permitida que publica telora.cl.

Uso (desde la raíz del repo):  py tools/armar_www.py
       py tools/armar_www.py --workflow RUTA   (compara contra otro pages.yml; para probar)

Después:  npx cap sync android

La app Android empaqueta exactamente lo que se publica en la web: ni tests.html, ni
tools/, ni documentos internos. La lista vive en dos lugares (ARCHIVOS/ICONOS aquí y
las líneas cp del paso «Armar _site con la lista permitida» de pages.yml), así que el
script compara ambas antes de copiar y se detiene si difieren (control de deriva): si
se agrega un archivo al sitio, hay que sumarlo en los dos lados.

En www/sw.js se reemplaza __BUILD__ por «cap-<hash corto de HEAD>» (o «…-dirty» si el
árbol tiene cambios sin commitear), igual que hace el deploy con _site/sw.js, para que sw.js
no quede con '__BUILD__'. Desde C3a la app nativa no registra el Service Worker (los archivos
vienen en el APK); www/sw.js se copia igual porque la lista es la misma de la web. Los
archivos fuente no se tocan.

www/ es derivado (está en .gitignore) y se rehace entero en cada corrida.
tools/ no se publica: el deploy (.github/workflows/pages.yml) copia una lista permitida.
"""
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
WWW = RAIZ / 'www'
WORKFLOW = RAIZ / '.github' / 'workflows' / 'pages.yml'
PASO = 'Armar _site con la lista permitida'

# Debe calzar con las líneas cp de pages.yml (destinos _site/ y _site/icons/).
ARCHIVOS = [
    'index.html', 'sw.js', 'manifest.json',
    'exceljs.min.js', 'supabase.min.js',
    'tutorial.html', 'privacidad.html', 'terminos.html', 'eliminar-cuenta.html',
]
ICONOS = [
    'icons/favicon-16.png', 'icons/favicon-32.png', 'icons/apple-touch-icon.png',
    'icons/icon-192.png', 'icons/icon-512.png',
    'icons/icon-maskable-192.png', 'icons/icon-maskable-512.png',
    'icons/og-image.png',
]


def lista_de_pages(ruta):
    """Devuelve {destino: [fuentes]} leyendo los cp del paso de la lista permitida.

    Se toma el bloque «run: |» de ese paso, se unen las líneas cortadas con «\\» y se
    lee cada comando que empieza con «cp». Lo que no se entienda (paso ausente, cp con
    opciones, destino desconocido) detiene el script: mejor fallar que comparar contra
    una lista mal leída.
    """
    lineas = ruta.read_text(encoding='utf-8').splitlines()
    try:
        i = next(n for n, l in enumerate(lineas) if l.strip() == f'- name: {PASO}')
    except StopIteration:
        sys.exit(f'{ruta.name}: no encuentro el paso «{PASO}»')
    if i + 1 >= len(lineas) or lineas[i + 1].strip() != 'run: |':
        sys.exit(f'{ruta.name}: el paso «{PASO}» no sigue con «run: |»')
    sangria = len(lineas[i + 1]) - len(lineas[i + 1].lstrip())
    bloque = []
    for l in lineas[i + 2:]:
        if l.strip() and len(l) - len(l.lstrip()) <= sangria:
            break
        bloque.append(l.strip())

    comandos, actual = [], ''
    for l in bloque:
        if l.endswith('\\'):
            actual += l[:-1] + ' '
        else:
            comandos.append(actual + l)
            actual = ''

    cps = {}
    for cmd in comandos:
        partes = shlex.split(cmd)
        if not partes or partes[0] != 'cp':
            continue
        if any(p.startswith('-') for p in partes[1:]):
            sys.exit(f'{ruta.name}: cp con opciones, no sé leerlo: {cmd}')
        destino, fuentes = partes[-1], partes[1:-1]
        if destino not in ('_site/', '_site/icons/'):
            sys.exit(f'{ruta.name}: destino de cp desconocido: {destino}')
        cps.setdefault(destino, []).extend(fuentes)
    if not cps:
        sys.exit(f'{ruta.name}: el paso «{PASO}» no tiene líneas cp')
    return cps


def controlar_deriva(ruta):
    cps = lista_de_pages(ruta)
    errores = []
    for destino, propia in (('_site/', ARCHIVOS), ('_site/icons/', ICONOS)):
        suya = cps.get(destino, [])
        if sorted(suya) != sorted(propia):
            solo_aqui = sorted(set(propia) - set(suya))
            solo_alla = sorted(set(suya) - set(propia))
            errores.append(f'  {destino}: solo en armar_www.py {solo_aqui}; '
                           f'solo en pages.yml {solo_alla}')
    if errores:
        sys.exit(f'La lista permitida de armar_www.py y la de {ruta.name} difieren:\n'
                 + '\n'.join(errores))


def build():
    """«cap-<hash>», o «cap-<hash>-dirty» si el árbol tiene cambios sin commitear: así el
    BUILD de un APK armado con cambios locales no se confunde con el de ese commit."""
    corto = subprocess.run(['git', 'rev-parse', '--short=7', 'HEAD'], cwd=RAIZ,
                           capture_output=True, text=True, check=True).stdout.strip()
    sucio = subprocess.run(['git', 'status', '--porcelain'], cwd=RAIZ,
                           capture_output=True, text=True, check=True).stdout.strip()
    return 'cap-' + corto + ('-dirty' if sucio else '')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    args = sys.argv[1:]
    ruta = Path(args[args.index('--workflow') + 1]) if '--workflow' in args else WORKFLOW
    controlar_deriva(ruta)

    faltantes = [f for f in ARCHIVOS + ICONOS if not (RAIZ / f).is_file()]
    if faltantes:
        sys.exit(f'Faltan archivos de la lista permitida: {faltantes}')

    if WWW.exists():
        shutil.rmtree(WWW)
    (WWW / 'icons').mkdir(parents=True)
    for f in ARCHIVOS + ICONOS:
        shutil.copy2(RAIZ / f, WWW / f)

    sw = WWW / 'sw.js'
    texto = sw.read_text(encoding='utf-8')
    if '__BUILD__' not in texto:
        sys.exit('sw.js no tiene el marcador __BUILD__')
    valor = build()
    sw.write_text(texto.replace('__BUILD__', valor), encoding='utf-8', newline='')
    print(f'www/ armado: {len(ARCHIVOS)} archivos + {len(ICONOS)} íconos; BUILD={valor}')


if __name__ == '__main__':
    main()
