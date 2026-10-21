"""Servidor estático para tests.html: igual a `py -m http.server`, pero sin la CSP en los iframes.

Uso (desde la raíz del repo):  py tools/servidor_pruebas.py [puerto] [host]
                               py tools/servidor_pruebas.py 8743              (127.0.0.1)
                               py tools/servidor_pruebas.py 8742 0.0.0.0      (red local, iPhone)

Por qué existe: tests.html carga index.html en iframes y les inyecta fixtures con
`iframe.contentWindow.eval(...)`. La CSP del <meta> de index.html no permite
'unsafe-eval' (ni debe permitirlo), así que con la página tal cual el harness no corre.
Este servidor quita SOLO el <meta http-equiv="Content-Security-Policy"> de index.html y
SOLO cuando el navegador lo pide para un iframe (Sec-Fetch-Dest: iframe; en navegadores
sin esa cabecera, Referer tests.html + Accept text/html). Abrir index.html directo en una
pestaña, o el fetch() de tests.html que revisa los hashes, reciben la página intacta, con
su CSP. Todo va con Cache-Control: no-store para que una copia sin CSP nunca quede en
caché y se use en una navegación normal.

/sw.js responde 404: sin service worker en este origen (las pruebas corren con el SW
desregistrado). Un iframe controlado por sw.js recibiría la navegación reenviada con
fetch(req), sin «Sec-Fetch-Dest: iframe», y la CSP volvería a bloquear win.eval().
index.html ya tolera que el registro falle (la app funciona igual sin SW). En la red
local (http://192.168…) tampoco hay SW: exige contexto seguro.

Producción (GitHub Pages) no pasa por aquí: tools/ no se publica.
"""
import re
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

RAIZ = Path(__file__).resolve().parent.parent
META_CSP = re.compile(rb'<meta http-equiv="Content-Security-Policy" content="[^"]*">\r?\n?')


class Manejador(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def _es_iframe_de_pruebas(self):
        dest = self.headers.get('Sec-Fetch-Dest')
        if dest is not None:
            return dest == 'iframe'
        # Sin Sec-Fetch-Dest (Safari < 16.4): Referer tests.html y pide HTML (el fetch() de los
        # hashes en tests.html pide */*).
        referer = urlsplit(self.headers.get('Referer', '')).path
        return referer.endswith('/tests.html') and 'text/html' in self.headers.get('Accept', '')

    def do_GET(self):
        ruta = urlsplit(self.path).path
        if ruta == '/sw.js':
            self.send_error(404, 'Sin service worker en el servidor de pruebas')
            return
        if ruta in ('/', '/index.html') and self._es_iframe_de_pruebas():
            cuerpo = META_CSP.sub(b'', (RAIZ / 'index.html').read_bytes(), count=1)
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(cuerpo)))
            self.end_headers()
            self.wfile.write(cuerpo)
            return
        super().do_GET()


def main():
    puerto = int(sys.argv[1]) if len(sys.argv) > 1 else 8743
    host = sys.argv[2] if len(sys.argv) > 2 else '127.0.0.1'
    servidor = ThreadingHTTPServer((host, puerto), partial(Manejador, directory=str(RAIZ)))
    print(f'Sirviendo {RAIZ} en http://{host}:{puerto}/ (index.html sin CSP solo dentro de iframes)', flush=True)
    servidor.serve_forever()


if __name__ == '__main__':
    main()
