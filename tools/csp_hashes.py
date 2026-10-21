"""Recalcula los hashes sha256 de los <script> inline y actualiza la CSP del <meta>.

Uso (desde la raíz del repo):  py tools/csp_hashes.py
       py tools/csp_hashes.py --check   (no escribe; sale con 1 si algún <meta> está desfasado)

La CSP va en <meta http-equiv="Content-Security-Policy"> porque GitHub Pages no deja
poner cabeceras. Cada página tiene su política completa en POLITICAS; este script la
reescribe entera con los hashes reales de sus <script> inline (los de src= los cubre
'self'). Hay que correrlo después de tocar CUALQUIER <script> inline: un solo carácter
distinto cambia el hash y el navegador bloquea ese script (index.html quedaría en blanco).
tests.html lo comprueba («CSP: hashes del <meta>»).

Los scripts se extraen con html.parser (no con una expresión regular): index.html
menciona «<script>» en comentarios y en cadenas de JS, y eso confundiría a una regex.
Los saltos CRLF se normalizan a LF antes del hash, igual que hace el navegador.

tools/ no se publica: el deploy (.github/workflows/pages.yml) copia una lista permitida.
"""
import base64
import hashlib
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SUPABASE = 'ekavuxaznjbvrzpxtslz.supabase.co'

# {HASHES} se reemplaza por los 'sha256-…' de los <script> inline de la página.
POLITICAS = {
    'index.html': (
        "default-src 'self'; script-src 'self' {HASHES}; style-src 'self' 'unsafe-inline'; "
        # Avatar de Google: sale de lh3…lh6.googleusercontent.com según la cuenta.
        "img-src 'self' data: blob: https://*.googleusercontent.com; font-src 'self'; "
        f"connect-src 'self' https://{SUPABASE} wss://{SUPABASE}; worker-src 'self'; "
        "manifest-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-src 'none'"
    ),
    'tutorial.html': (
        "default-src 'self'; script-src {HASHES}; style-src 'self' 'unsafe-inline'; img-src 'self'; "
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-src 'none'"
    ),
}
# Páginas sin JavaScript: ningún script permitido.
for _pag in ('privacidad.html', 'terminos.html', 'eliminar-cuenta.html'):
    POLITICAS[_pag] = (
        "default-src 'self'; script-src 'none'; style-src 'self' 'unsafe-inline'; img-src 'self'; "
        "object-src 'none'; base-uri 'self'; form-action 'self'; frame-src 'none'"
    )

META_RE = re.compile(r'<meta http-equiv="Content-Security-Policy" content="[^"]*">')
CHARSET = '<meta charset="UTF-8">'


class _Scripts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.inline, self._actual = [], None

    def handle_starttag(self, tag, attrs):
        if tag == 'script' and not any(k == 'src' for k, _ in attrs):
            self._actual = []

    def handle_data(self, data):
        if self._actual is not None:
            self._actual.append(data)

    def handle_endtag(self, tag):
        if tag == 'script' and self._actual is not None:
            self.inline.append(''.join(self._actual))
            self._actual = None


def hashes_inline(html):
    p = _Scripts()
    p.feed(html.replace('\r\n', '\n'))
    p.close()
    return ["'sha256-" + base64.b64encode(hashlib.sha256(s.encode('utf-8')).digest()).decode() + "'"
            for s in p.inline]


def meta_para(pagina, html):
    hashes = ' '.join(hashes_inline(html))
    politica = POLITICAS[pagina].replace(' {HASHES}', ' ' + hashes if hashes else '')
    politica = politica.replace('script-src {HASHES}', 'script-src ' + (hashes or "'none'"))
    return f'<meta http-equiv="Content-Security-Policy" content="{politica}">'


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    solo_revisar = '--check' in sys.argv[1:]
    desfasadas = []
    for pagina in POLITICAS:
        ruta = RAIZ / pagina
        html = ruta.read_text(encoding='utf-8')
        nuevo_meta = meta_para(pagina, html)
        if META_RE.search(html):
            nuevo = META_RE.sub(lambda _m: nuevo_meta, html, count=1)
        elif CHARSET in html:
            nuevo = html.replace(CHARSET, CHARSET + '\n' + nuevo_meta, 1)
        else:
            sys.exit(f'{pagina}: no tiene {CHARSET} para colgar la CSP')
        if nuevo == html:
            print(f'{pagina}: al día')
            continue
        desfasadas.append(pagina)
        if not solo_revisar:
            ruta.write_text(nuevo, encoding='utf-8', newline='')
            print(f'{pagina}: CSP actualizada ({len(hashes_inline(html))} script(s) inline)')
        else:
            print(f'{pagina}: CSP DESFASADA')
    if solo_revisar and desfasadas:
        sys.exit(1)


if __name__ == '__main__':
    main()
