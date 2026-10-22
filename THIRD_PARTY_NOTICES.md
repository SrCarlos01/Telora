# Avisos de terceros

Telora incluye software de terceros distribuido bajo la licencia MIT. Se reproduce abajo
el aviso de copyright y el texto de la licencia, como exige la MIT.

| Componente | Versión | Dónde está en Telora | Licencia | Copyright |
|---|---|---|---|---|
| [Feather Icons](https://github.com/feathericons/feather) | 4.x (trazos SVG copiados; la versión exacta no quedó registrada) | `ICONS` en `index.html` | MIT | Copyright (c) 2013-2023 Cole Bemis |
| [@supabase/supabase-js](https://github.com/supabase/supabase-js) | 2.117.1 (build UMD) | `supabase.min.js` | MIT | Copyright (c) 2020 Supabase |
| [ExcelJS](https://github.com/exceljs/exceljs) | 4.4.0 | `exceljs.min.js` | MIT | Copyright (c) 2014-2019 Guyon Roche |
| [@capacitor/android](https://github.com/ionic-team/capacitor) | 8.5.3 | App Android (`android/`): runtime nativo y puente JS empaquetados en el APK | MIT | Copyright (c) 2017-present Drifty Co. |
| [@capacitor/core](https://github.com/ionic-team/capacitor) | 8.5.3 | App Android: dependencia de compilación (la web aún no la importa) | MIT | Copyright (c) 2017-present Drifty Co. |
| [@capacitor/cli](https://github.com/ionic-team/capacitor) | 8.5.3 | Herramienta de desarrollo (`npx cap`); no se distribuye | MIT | Copyright (c) 2017-present Drifty Co. |

`supabase.min.js` empaqueta también los subpaquetes del monorepo supabase-js (auth-js,
postgrest-js, realtime-js, storage-js y functions-js), con la misma licencia y el mismo
titular.

## Texto de la licencia MIT

Se aplica a cada componente de la tabla, con su propia línea de copyright.

```
MIT License

Copyright (c) <año> <titular>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
