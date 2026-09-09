<div align="center">
  <img src="https://github.com/SantiagortegaDev/lessnet/blob/main/assets/lessnet.png" width=200px" alt="GitHub Readme Stats" />
  <h1 style="font-size: 28px; margin: 10px 0;">Less Net</h1>
  <p>Aplicacion offline para comunicacion por bluetooth, guardar informacion y herramientas utiles</p>
</div>
<p align="center">
  <img alt="Build APK" src="https://img.shields.io/github/contributors/SantiagortegaDev/lessnet?style=flat&label=Contributors&color=ffffff"/>

  <img alt="Build APK" src="https://img.shields.io/github/actions/workflow/status/SantiagortegaDev/lessnet/android.yml?style=flat&label=Build%20APK&color=%23ffffff"/>


  <img alt="Workflows" src="https://img.shields.io/badge/Workflows-131-white?style=flat&color=ffffff"/>


  <img alt="Workflows" src="https://img.shields.io/github/commit-activity/t/SantiagortegaDev/lessnet?style=flat&color=%23ffffff"/>


  <img alt="Stars" src="https://img.shields.io/github/stars/SantiagortegaDev/lessnet?style=flat&label=Repo%20Stars&color=ffffff"/>


  <img alt="GitHub pull requests" src="https://img.shields.io/github/contributors/SantiagortegaDev/lessnet?style=flat&label=Contributors&color=ffffff"/>

  <br />
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=black&color=ffffff"/>
  <img alt="Dart" src="https://img.shields.io/badge/Dart-ffffff.svg?style=flat&logo=Dart&logoColor=black&color=ffffff"/>
  <img alt="Kotlin" src="https://img.shields.io/badge/Kotlin-ffffff.svg?style=flat&logo=Kotlin&logoColor=black&color=ffffff"/>
  <img alt="JavaScript" src="https://img.shields.io/badge/JavaScript-ffffff.svg?style=flat&logo=JavaScript&logoColor=black&color=ffffff"/>
  <img alt="TypeScript" src="https://img.shields.io/badge/TypeScript-ffffff.svg?style=flat&logo=TypeScript&logoColor=black&color=ffffff"/>
  <img alt="Python" src="https://img.shields.io/badge/Python-ffffff.svg?style=flat&logo=Python&logoColor=black&color=ffffff"/>
  <img alt="LaTeX" src="https://img.shields.io/badge/LaTeX-ffffff.svg?style=flat&logo=LaTeX&logoColor=black&color=ffffff"/>
  <br />
</p>

> [!NOTE]
> Interfaz rediseñada con Material 3 (Material You), red mesh reescrita y
> seis formas de conectar dispositivos. Puedes
> [descargar la beta](https://github.com/SantiagortegaDev/lessnet/releases/).



# Prueba la app!

1. Descarga la beta en tu celular: https://github.com/SantiagortegaDev/lessnet/releases/

2. Permite instalar aplicaciones de fuentes desconocidas. No tiene virus :)

`Realiza lo anterior en otro dispositivo para probar el chat y la conexión bluetooth`

3. Activa bluetooth y el boton `Visible`

4. En el otro dispositivo Activa bluetooth y dale a `Buscar` (intenta conectarte, puede costar la primera vez pero intentando y oprimiendo el boton de buscar varias veces funciona)

5. Despues de conectarse, en los 2 dispositivos vallan a `Chat` y entren a `Chat Global` empiezen a mandar mensajes!

6. El boton SOS enviara a chat global informacion del dispositivo y activara su linterna

7. En el vault pueden ver contenido ya descargado por la app

8. En `Traductor offline` en la esquina superior derecha instala los idiomas que quiera y podras traducir sin internet!

9. En `Codigo Morse` escribe cualquier texto y al darle `Transmitir` se encendera y apagara la linterna con el mensaje en codigo morse

10. En `Perfil` abajo de todo dale `Actualizar` y veras tus coordenadas sin necesidad de internet

11. Prueba y disfruta la app!

> [!WARNING]
> Recuerda activar el Bluetooth para ser visible y poder conectarte a otros dispositivos, si no funciona intenta cerrar y volver a abrir la app o activar y desactivar el bluetooth

[![Less net App Demo - YouTube](https://res.cloudinary.com/marcomontalbano/image/upload/v1779230459/video_to_markdown/images/youtube--Gn064fZsrx8-c05b58ac6eb4c4700831b2b3070cd403.jpg)](https://www.youtube.com/watch?v=Gn064fZsrx8 "Less net App Demo - YouTube")

---

## Conexión entre dispositivos

LessNet ya no depende de una sola radio ni de una lista de direcciones MAC.
Hay **seis formas de conectarse**, ordenadas en la app por lo que tardan de
verdad en dejarte hablando:

| Método | Tiempo típico | Cuándo conviene |
|---|---|---|
| **Escanear QR** | ~3 s | Lo más rápido. Un teléfono muestra, el otro apunta la cámara |
| **Misma red Wi-Fi** | ~4 s | Si ya comparten router, es instantáneo y el más veloz |
| **Cerca de mí** | ~6 s | Detecta por proximidad (RSSI) quién está a menos de ~10 m |
| **Código de 6 dígitos** | ~8 s | Ambos escriben el mismo código. Se puede decir en voz alta |
| **Wi-Fi Direct** | ~12 s | Sin router. Ideal para fotos y videos |
| **Punto de acceso** | ~20 s | Cuando no hay red: un teléfono la crea para el resto |

### El código de grupo lo une todo

Un código como `K7M-2QX` no es solo un PIN: de él se **derivan** de forma
determinista todos los parámetros de cada transporte, así que los dos
teléfonos los calculan por separado y se encuentran sin negociar nada.

```
código ──┬─ etiqueta de servicio BLE   → el escaneo solo muestra tu grupo
         ├─ nombre de servicio NSD      → descubrimiento en la LAN
         ├─ SSID del hotspot            → LessNet-K7M2QX
         ├─ contraseña del hotspot      → derivada, nunca viaja por el aire
         └─ puerto TCP                  → ambos coinciden sin acordarlo
```

El alfabeto excluye `0 O 1 I L U`, para que el código se pueda gritar en un
albergue sin que nadie lo confunda.

### Selección automática del mejor medio

Cada enlace se puntúa continuamente y el mejor gana, por destino:

- **ancho de banda** del medio (comprimido logarítmicamente: el salto de BLE
  a Wi-Fi pesa mucho más que LAN vs Wi-Fi Direct)
- **calidad de señal** real (RSSI en BLE, porcentaje en Wi-Fi)
- **saltos** hasta el destino (cada salto añade latencia y un punto de fallo)
- **fiabilidad observada** (tasa de éxito y fallos recientes)
- **consumo de batería**, solo como desempate
- **histéresis** para el enlace en uso, para que la app no salte de radio
  cada pocos segundos

En `Red` puedes ver el puntaje de cada enlace y cuál está en uso, o forzar
`Auto` / `Bluetooth` / `Wi-Fi` a mano.

---

## Red mesh

El formato anterior (`[MESH:saltos:origen]`) tenía dos fallos que la hacían
inservible con más de dos dispositivos:

1. Al retransmitir un mensaje global se **reenvolvía con una cabecera nueva**,
   reiniciando el contador de saltos a su máximo. El TTL nunca llegaba a cero
   y los mensajes circulaban para siempre en cualquier topología con ciclos.
2. La deduplicación hasheaba la trama completa **incluyendo el número de
   saltos**, así que el mismo mensaje llegando por un camino de 2 y otro de 3
   producía dos hashes distintos y se mostraba duplicado.

El formato nuevo es una sola línea por paquete:

```
LN1|tipo|msgId|ttl|origen|destino|seq|cargaBase64
```

- `msgId` se genera **una sola vez en el origen** y ningún repetidor lo
  reescribe. La deduplicación usa solo ese id.
- El TTL **solo decrece**, nunca se reinicia.
- Hay **un único punto** en el código que retransmite, y nunca devuelve el
  paquete por el enlace del que llegó.
- Los mensajes directos se enrutan por el **mejor enlace conocido** en vez de
  inundar toda la malla.

Está cubierto por tests que verifican, entre otros casos, que una topología
en ciclo (A–B, B–C, C–A) no genera tormenta y que un mismo mensaje que llega
por dos caminos distintos se entrega **una sola vez**.

---

## Mensajes que no se pierden

Antes, enviar sin nadie conectado ejecutaba `if (!isConnected) return;` y el
mensaje desaparecía sin aviso. Ahora todo mensaje se **persiste primero** en
una cola en disco y se reintenta con espera creciente (2 s, 5 s, 15 s, 45 s,
2 min, 5 min…) hasta que aparece un enlace.

Cada burbuja muestra su estado real: `En cola`, `Enviando`, `Enviado`,
`Entregado` (con acuse de recibo de verdad) o `Falló`.

Como el reintento reenvía el paquete **idéntico**, con el mismo `msgId`, el
receptor lo deduplica solo: reintentar siempre es seguro.

---

## Envío de archivos

| | Antes | Ahora |
|---|---|---|
| Formato | Todo el archivo en **un** mensaje base64 | Trozos numerados con acuse |
| Tamaño de trozo | Fijo de 200 bytes, ignorando el MTU | Del MTU real (BLE) o decenas de KB (Wi-Fi) |
| Pérdida de un trozo | Se pierde la transferencia entera | Se piden **solo los que faltan** |
| Límite | 2 MB siempre | 4 MB por BLE, 64 MB por Wi-Fi |
| Verificación | CRC32 del total | CRC32 del total, y reintento si falla |

---

## Identidad y nombres

Cada persona tiene un **id estable** que es el mismo por BLE, LAN, Wi-Fi
Direct y hotspot, así que una conversación sigue a la persona y no a la radio.
En `Perfil` se elige nombre, emoji de avatar, color de la app y tema
claro/oscuro/automático.
---

## Conexion entre dispositivos

LessNet ya no depende de una sola radio ni de una lista de direcciones MAC.
Hay **seis formas de conectarse**, ordenadas en la app por lo que tardan de
verdad en dejarte hablando:

| Metodo | Tiempo tipico | Cuando conviene |
|---|---|---|
| **Escanear QR** | ~3 s | Lo mas rapido. Un telefono muestra, el otro apunta la camara |
| **Misma red Wi-Fi** | ~4 s | Si ya comparten router, es instantaneo y el mas veloz |
| **Cerca de mi** | ~6 s | Detecta por proximidad (RSSI) quien esta a menos de ~10 m |
| **Codigo de 6 digitos** | ~8 s | Ambos escriben el mismo codigo. Se puede decir en voz alta |
| **Wi-Fi Direct** | ~12 s | Sin router. Ideal para fotos y videos |
| **Punto de acceso** | ~20 s | Cuando no hay red: un telefono la crea para el resto |

### El codigo de grupo lo une todo

Un codigo como `K7M-2QX` no es solo un PIN: de el se **derivan** de forma
determinista todos los parametros de cada transporte, asi que los dos
telefonos los calculan por separado y se encuentran sin negociar nada.

```
codigo --+- etiqueta de servicio BLE   -> el escaneo solo muestra tu grupo
         +- nombre de servicio NSD      -> descubrimiento en la LAN
         +- SSID del hotspot            -> LessNet-K7M2QX
         +- contrasena del hotspot      -> derivada, nunca viaja por el aire
         +- puerto TCP                  -> ambos coinciden sin acordarlo
```

El alfabeto excluye `0 O 1 I L U`, para que el codigo se pueda gritar en un
albergue sin que nadie lo confunda.

### Seleccion automatica del mejor medio

Cada enlace se puntua continuamente y el mejor gana, por destino:

- **ancho de banda** del medio (comprimido logaritmicamente: el salto de BLE
  a Wi-Fi pesa mucho mas que LAN vs Wi-Fi Direct)
- **calidad de senal** real (RSSI en BLE, porcentaje en Wi-Fi)
- **saltos** hasta el destino (cada salto anade latencia y un punto de fallo)
- **fiabilidad observada** (tasa de exito y fallos recientes)
- **consumo de bateria**, solo como desempate
- **histeresis** para el enlace en uso, para que la app no salte de radio
  cada pocos segundos

En `Red` puedes ver el puntaje de cada enlace y cual esta en uso, o forzar
`Auto` / `Bluetooth` / `Wi-Fi` a mano.

---

## Red mesh

El formato anterior (`[MESH:saltos:origen]`) tenia dos fallos que la hacian
inservible con mas de dos dispositivos:

1. Al retransmitir un mensaje global se **reenvolvia con una cabecera nueva**,
   reiniciando el contador de saltos a su maximo. El TTL nunca llegaba a cero
   y los mensajes circulaban para siempre en cualquier topologia con ciclos.
2. La deduplicacion hasheaba la trama completa **incluyendo el numero de
   saltos**, asi que el mismo mensaje llegando por un camino de 2 y otro de 3
   producia dos hashes distintos y se mostraba duplicado.

El formato nuevo es una sola linea por paquete:

```
LN1|tipo|msgId|ttl|origen|destino|seq|cargaBase64
```

- `msgId` se genera **una sola vez en el origen** y ningun repetidor lo
  reescribe. La deduplicacion usa solo ese id.
- El TTL **solo decrece**, nunca se reinicia.
- Hay **un unico punto** en el codigo que retransmite, y nunca devuelve el
  paquete por el enlace del que llego.
- Los mensajes directos se enrutan por el **mejor enlace conocido** en vez de
  inundar toda la malla.

Esta cubierto por tests que verifican, entre otros casos, que una topologia
en ciclo (A-B, B-C, C-A) no genera tormenta y que un mismo mensaje que llega
por dos caminos distintos se entrega **una sola vez**.

---

## Mensajes que no se pierden

Antes, enviar sin nadie conectado ejecutaba `if (!isConnected) return;` y el
mensaje desaparecia sin aviso. Ahora todo mensaje se **persiste primero** en
una cola en disco y se reintenta con espera creciente (2 s, 5 s, 15 s, 45 s,
2 min, 5 min...) hasta que aparece un enlace.

Cada burbuja muestra su estado real: `En cola`, `Enviando`, `Enviado`,
`Entregado` (con acuse de recibo de verdad) o `Fallo`.

Como el reintento reenvia el paquete **identico**, con el mismo `msgId`, el
receptor lo deduplica solo: reintentar siempre es seguro.

---

## Envio de archivos

| | Antes | Ahora |
|---|---|---|
| Formato | Todo el archivo en **un** mensaje base64 | Trozos numerados con acuse |
| Tamano de trozo | Fijo de 200 bytes, ignorando el MTU | Del MTU real (BLE) o decenas de KB (Wi-Fi) |
| Perdida de un trozo | Se pierde la transferencia entera | Se piden **solo los que faltan** |
| Limite | 2 MB siempre | 4 MB por BLE, 64 MB por Wi-Fi |

---

## Identidad y nombres

Cada persona tiene un **id estable** que es el mismo por BLE, LAN, Wi-Fi
Direct y hotspot, asi que una conversacion sigue a la persona y no a la radio.
En `Perfil` se elige nombre, emoji de avatar, color de la app y tema
claro/oscuro/automatico.



---

### Mensajes de texto

Cada mensaje se codifica en UTF-8 y se fragmenta en chunks de **200 bytes** (MTU-safe). Un byte nulo `0x00` actúa como terminador — el receptor reconstruye el buffer hasta encontrarlo.

- **Chat personal** → texto plano al dispositivo activo
- **Chat Global** → prefijo `[GLOBAL]` + broadcast simultáneo a todos los dispositivos conectados

---

### Transferencia de archivos

Los archivos se codifican en Base64 y se envían como un único mensaje:

```
[FILE:TYPE:FILENAME:SIZE:CRC32]<base64data>
```

> [!NOTE]
> El receptor verifica integridad con **CRC32** antes de guardar. Tamaño máximo: **2 MB** por transferencia.

---

### Red mesh

Los mensajes se propagan automáticamente entre nodos con el formato:

```
[MESH:hopCount:originId]<payload>
```

> [!IMPORTANT]
> Máximo **5 saltos**. Los mensajes ya vistos se descartan por 5 minutos usando deduplicación SHA-256, evitando bucles infinitos.

---

### Señal SOS 

<!-- screenshot vertical aquí -->
<!-- <img src="screenshots/sos.png" width="260" align="right"> -->

Al presionar el botón **SOS**:

1. Se obtienen las coordenadas GPS del dispositivo
2. Inicia una **cuenta regresiva de 5 segundos** (cancelable)
3. Se activan vibración continua, alarma de sonido y linterna
4. Se transmite al Chat Global:

```
[SOS:latitud:longitud:userId:timestamp]
```

Todos los dispositivos conectados muestran una notificación de alta prioridad y el mensaje se propaga por toda la red mesh disponible.

> [!WARNING]
> El SOS no se puede cancelar una vez enviado. Usa el botón **CANCELAR** antes de que termine la cuenta regresiva.

---

## Vault — Recursos offline

Todo el contenido funciona **sin conexión a internet**. Los datos están almacenados localmente como archivos JSON en `assets/vault/`.

---

### Primeros Auxilios

<!-- screenshot vertical aquí -->
<!-- <img src="screenshots/first_aid.png" width="260" align="right"> -->

12 protocolos de emergencia médica. Cada uno incluye pasos numerados, advertencias por paso, indicaciones de cuándo buscar ayuda y referencias.

**Cómo usarlo:**
- Busca por nombre o síntoma con la barra de búsqueda
- Toca un protocolo para ver los pasos detallados
- Usa el ícono de bookmark para guardarlo en favoritos

> [!TIP]
> Los protocolos marcados como `CRITICA` o `ALTA` aparecen resaltados en rojo/naranja para identificarlos rápido en emergencias.

---

### Guías de supervivencia

<!-- screenshot vertical aquí -->
<!-- <img src="screenshots/guides.png" width="260" align="right"> -->

15 guías esenciales organizadas por categoría (orientación, refugio, agua, fuego, señalización, etc.).

**Cómo usarlo:**
- Filtra por categoría con los chips horizontales
- Navega la lista completa con el filtro **Todo**
- Misma estructura de pasos y advertencias que primeros auxilios

---

### Diccionario médico

298 términos médicos con definición, categoría y sinónimos.

**Cómo usarlo:**
- Escribe en la barra para filtrar en tiempo real por palabra o definición
- Toca un término para ver definición completa y sinónimos

---

### Wikipedia Offline

<!-- screenshot vertical aquí -->
<!-- <img src="screenshots/wiki.png" width="260" align="right"> -->

61 artículos en 6 categorías temáticas. Cada artículo tiene resumen y secciones con contenido expandido.

**Cómo usarlo:**
- Filtra por categoría o busca por título/contenido
- Toca un artículo para leerlo completo
- Usa el ícono 🔖 para marcarlo como favorito

---

### Mapa de emergencias

<!-- screenshot vertical aquí -->
<!-- <img src="screenshots/map.png" width="260" align="right"> -->

Mapa interactivo de Colombia con **74 puntos de referencia**: capitales, ciudades principales y hospitales. Usa OpenStreetMap con descarga automática de tiles en segundo plano (zoom 5–7) para uso offline.

**Cómo usarlo:**
- Alterna entre **mapa** y **lista** con el ícono superior derecho
- Toca un marcador para ver la info del punto
- Toca la tarjeta emergente para ver detalle completo
- Filtra con los chips: `Capitales` `Hospitales` `Ciudades`

| Color del marcador | Tipo |
|--------------------|------|
| ⚪ Blanco | Capital nacional |
| ⚫ Gris | Capital departamental |
| 🔴 Rojo | Hospital de referencia |
| 🟢 Verde | Ciudad principal |

> [!NOTE]
> Los tiles del mapa se descargan automáticamente en segundo plano la primera vez que abres esta sección con internet disponible.

---

### Traductor offline

<!-- screenshot vertical aquí -->
<!-- <img src="screenshots/translator.png" width="260" align="right"> -->

Traducción con IA ejecutada **completamente en el dispositivo** usando ML Kit de Google. Soporta 18 idiomas.

**Cómo usarlo:**
1. Toca el ícono de descarga (arriba a la derecha) para gestionar modelos
2. Descarga los idiomas que necesitas (~30 MB cada uno)
3. Selecciona idioma origen y destino
4. Escribe el texto y toca **Traducir**

> [!IMPORTANT]
> Los modelos deben descargarse con internet **una sola vez**. Después, la traducción funciona completamente offline.

**Idiomas disponibles:**
`Español` `Inglés` `Portugués` `Francés` `Alemán` `Italiano` `Ruso` `Chino` `Japonés` `Coreano` `Árabe` `Hindi` `Turco` `Holandés` `Polaco` `Tailandés` `Vietnamita` `Indonesio`

---

### Código Morse

Convierte texto a código Morse y lo transmite con la **linterna del dispositivo**.

**Cómo usarlo:**
- Escribe tu mensaje — el código aparece en tiempo real
- Toca **Transmitir** para iniciar el parpadeo
- Usa el botón ⏹ para detener en cualquier momento

**Tiempos estándar:**

| Símbolo | Duración |
|---------|----------|
| `.` Punto | 200 ms |
| `-` Raya | 600 ms |
| Separación entre símbolos | 200 ms |
| Separación entre letras | 600 ms |
| Separación entre palabras | 1400 ms |

> [!NOTE]
> Si tu dispositivo no tiene linterna, el botón **Transmitir** estará deshabilitado.

---

### Cargar desde URL

Obtiene contenido JSON desde cualquier URL externa y lo muestra formateado. Guarda historial de las últimas 10 URLs.

**Cómo usarlo:**
- Ingresa la URL de un endpoint JSON
- Toca **Obtener** para cargar el contenido
- Copia el resultado con el botón **Copiar**
- Las URLs recientes aparecen abajo para acceso rápido

> [!WARNING]
> Esta función **requiere internet** en el momento de la descarga.

---

### Búsqueda Global

Busca simultáneamente en **todas las secciones** del Vault con una sola consulta: primeros auxilios, guías, diccionario y Wikipedia.

Accesible desde el botón **Búsqueda Global** al final de la pantalla principal del Vault.
