[README.md](https://github.com/user-attachments/files/27857629/README.md)
# Red Mesh Vault - Contenido Offline

**Version:** 2.0.0
**Fecha:** 2026-05-17
**Idioma:** Espanol (Colombia)

---

## Descripcion

Este vault contiene todo el contenido necesario para que la aplicacion **Red Mesh sin Internet** funcione completamente offline. Disenado para escenarios de emergencias, apagones, desastres naturales y situaciones de censura donde la conectividad a internet no esta disponible.

El vault es ligero (~1 MB base) y puede descomprimirse directamente en la carpeta de assets de la aplicacion Android. Con el traductor NLLB-200, el tamano total es ~351 MB.

---

## Novedades en v2.0

- **Traductor actualizado**: Reemplazado Hy-MT (33 idiomas) por **NLLB-200 de Meta AI** (200 idiomas)
- **39,800 direcciones de traduccion** vs 1,056 anteriores
- **Modelo mas pequeno**: ~350 MB (Q4_K_M) vs 462 MB
- **Menor RAM**: ~900 MB vs ~2 GB
- **Sistema de language packs**: Descarga idiomas individualmente
- **10 idiomas builtin** sin descarga adicional

---

## Contenido del Vault

### 1. Guias de Supervivencia (`guides/supervivencia.json`)

15 guias detalladas para situaciones de emergencia:

- **Agua potable** - Como encontrar, purificar y almacenar agua
- **Refugio** - Construccion de refugios improvisados
- **Fuego** - Metodos para encender fuego sin cerillas
- **Senales de emergencia** - Comunicacion cuando no hay ayuda disponible
- **Navegacion** - Orientacion sin GPS ni brujula
- **Desastres naturales** - Terremotos, inundaciones, huracanes
- **Evacuacion** - Planes y protocolos de evacuacion
- **Comunicacion mesh** - Uso de la red mesh sin internet
- **Alimentacion** - Nutricion en situaciones de crisis
- **Seguridad en protestas** - Proteccion en disturbios civiles
- **Sobrevivir apagones** - Manejo de cortes de electricidad prolongados
- **Primeros auxilios psicologicos** - Apoyo emocional en emergencias
- **Optimizar red mesh** - Tecnicas avanzadas para mejor rendimiento
- **Cifrado y privacidad** - Proteccion de comunicaciones
- **Supervivencia urbana** - Guia general de supervivencia

### 2. Primeros Auxilios (`first_aid/primeros_auxilios.json`)

12 protocolos medicos de emergencia:

- **RCP** - Reanimacion cardiopulmonar
- **Hemorragias** - Control de sangrados severos
- **Quemaduras** - Tratamiento de quemaduras termicas y quimicas
- **Maniobra de Heimlich** - Desobstruccion de vias respiratorias
- **Shock** - Manejo del shock circulatorio
- **Fracturas** - Inmovilizacion y estabilizacion
- **Mordeduras de serpiente** - Protocolo antiofidico
- **Envenenamiento** - Intoxicaciones diversas
- **Hipotermia** - Tratamiento de exposicion al frio
- **Golpe de calor** - Emergencia por hipertermia
- **Intoxicacion por CO** - Monoxido de carbono
- **Convulsiones** - Manejo de crisis epilepticas

### 3. Diccionario (`dictionary/`)

- **diccionario.db** - Base de datos SQLite con FTS5 para busqueda full-text
- **diccionario_index.json** - Indice JSON para busqueda rapida

298 terminos organizados en categorias:
- Medicina (RCP, hemorragia, quemadura, etc.)
- Supervivencia (agua, refugio, fuego, etc.)
- Tecnologia (mesh, WiFi Direct, cifrado, etc.)
- Comunicacion (senales, frecuencias, etc.)
- Seguridad (OPSEC, amenazas, etc.)
- Salud mental (trauma, resiliencia, etc.)

### 4. Wikipedia Offline (`wikipedia/wikipedia_offline.json`)

100 articulos esenciales de Wikipedia en espanol:

- **Medicina**: 20 articulos de salud y primeros auxilios
- **Supervivencia**: 9 articulos de tecnicas de supervivencia
- **Geografia**: 10 articulos de Colombia y regiones
- **Tecnologia**: 10 articulos de tecnologia mesh y comunicaciones
- **Historia**: 5 articulos de historia colombiana y latinoamericana
- **Ciencia**: 7 articulos de ciencia general

### 5. Mapas de Colombia (`maps/colombia_emergencias.geojson`)

55 ciudades principales de Colombia incluyendo:
- Coordenadas GPS (lat/lng)
- Poblacion y altitud
- Tipo (capital, municipio)
- Servicios disponibles (aeropuerto, hospital)

20 rutas principales entre ciudades con distancias.

### 6. Traductor Offline NLLB-200 (`translator/`)

Modelo de traduccion **NLLB-200 Distilled 600M** de Meta AI:

- **Tamanio**: ~350 MB (Q4_K_M, descarga separada)
- **Idiomas**: 200 idiomas
- **Direcciones**: 39,800 traducciones posibles
- **RAM**: ~900 MB
- **Sistema de language packs**: Descarga idiomas individualmente

#### Idiomas builtin (10, sin descarga adicional):

| Idioma | Codigo | Codigo FLORES |
|--------|--------|---------------|
| Espanol | `es` | `spa_Latn` |
| Ingles | `en` | `eng_Latn` |
| Frances | `fr` | `fra_Latn` |
| Portugues | `pt` | `por_Latn` |
| Aleman | `de` | `deu_Latn` |
| Italiano | `it` | `ita_Latn` |
| Chino (simplificado) | `zh` | `zho_Hans` |
| Japones | `ja` | `jpn_Jpan` |
| Coreano | `ko` | `kor_Hang` |
| Ruso | `ru` | `rus_Cyrl` |

#### Idiomas descargables (190 adicionales):
Arabe, Hindi, Suajili, Yoruba, Catalan, Euskera, Gallego, Kurdo, Ucraniano, Cantonés, y muchos mas. Cada pack pesa ~5 KB.

**Descarga del modelo**: Ejecutar `translator/download_model.sh` o descargar desde Hugging Face.

Para mas informacion, ver `translator/README.md`.

---

## Requisitos de Instalacion

### Requisitos del dispositivo (base):
- **Android 8.0 (API 26)** o superior
- **500 MB** de almacenamiento libre
- **2 GB RAM** minimo recomendado

### Requisitos del dispositivo (con traductor NLLB-200):
- **Android 8.0 (API 26)** o superior
- **800 MB** de almacenamiento libre
- **2.5 GB RAM** minimo recomendado

### Requisitos de la aplicacion:
- Compatible con **Kiwix SDK** para navegacion Wikipedia
- Compatible con **MapLibre** para mapas offline
- Compatible con **llama.cpp** para traductor NLLB-200 offline
- Funciona **100% offline**

---

## Instalacion

### Metodo automatico (desde la app):
1. Descarga el archivo `Red_Mesh_Vault.zip`
2. La aplicacion detectara e instalara automaticamente

### Metodo manual:
1. Descomprime el archivo `Red_Mesh_Vault.zip`
2. Copia el contenido a la carpeta `assets/` de la aplicacion
3. Reinicia la aplicacion

### Instalar traductor:
1. Ejecuta `translator/download_model.sh` para descargar el modelo (~350 MB)
2. O descarga manualmente desde Hugging Face y colocalo en `translator/models/`

---

## Estructura de Archivos

```
vault/
├── manifest.json              # Metadatos y version
├── index.json                 # Indice unificado de busqueda
├── README.md                  # Este archivo
├── guides/
│   ├── supervivencia.json     # 15 guias de supervivencia
│   └── supervivencia.json.gz  # Version comprimida
├── first_aid/
│   ├── primeros_auxilios.json # 12 protocolos medicos
│   └── primeros_auxilios.json.gz
├── dictionary/
│   ├── diccionario.db         # SQLite con FTS5
│   └── diccionario_index.json  # Indice JSON
├── wikipedia/
│   ├── wikipedia_offline.json  # 100 articulos
│   └── wikipedia_offline.json.gz
├── maps/
│   ├── colombia_emergencias.geojson  # Ciudades y rutas
│   └── colombia_emergencias.geojson.gz
├── translator/                # Traductor NLLB-200 offline
│   ├── README.md             # Documentacion del traductor
│   ├── download_model.sh     # Script de descarga del modelo
│   ├── translator_config.json # Configuracion completa
│   ├── translator_engine.py   # Motor de traduccion (NLLBTranslator)
│   ├── language_packs.py      # Gestor de paquetes de idioma
│   ├── models/               # Carpeta para modelo GGUF
│   │   └── nllb-200-distilled-600m-q4_k_m.gguf  # (descarga separada)
│   ├── lang_packs/           # Paquetes de idioma instalados
│   │   ├── es.json           # Espanol (builtin)
│   │   ├── en.json           # Ingles (builtin)
│   │   ├── fr.json           # Frances (builtin)
│   │   ├── pt.json           # Portugues (builtin)
│   │   ├── de.json           # Aleman (builtin)
│   │   ├── it.json           # Italiano (builtin)
│   │   ├── zh.json           # Chino (builtin)
│   │   ├── ja.json           # Japones (builtin)
│   │   ├── ko.json           # Coreano (builtin)
│   │   └── ru.json           # Ruso (builtin)
│   └── cache/                # Cache de traducciones
│       └── translation_cache.json.gz
└── assets/                    # Para recursos futuros
```

---

## Optimizacion de Almacenamiento

Todos los archivos JSON incluyen versiones comprimidas en gzip (.gz). La aplicacion puede usar estas versiones para reducir el uso de memoria durante la carga.

**Nota:** Los archivos .gz se incluyen para referencia. La aplicacion puede generar sus propias versiones comprimidas si es necesario.

---

## Notas sobre Contenido Adicional

### Traductor Offline NLLB-200 (~350 MB) - RECOMENDADO:
Descarga el modelo de traduccion desde Hugging Face:
```
https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF/resolve/main/nllb-200-distilled-600m-q4_k_m.gguf
```
O usa el script incluido: `translator/download_model.sh`

### Para Wikipedia completo (~200 MB):
Descarga el archivo ZIM mas reciente desde:
```
https://download.kiwix.org/zim/wikipedia/wikipedia_es_all_mini_*.zim
```

### Para mapas detallados (~100 MB):
Descarga el mapa de OpenStreetMap desde:
```
https://download.geofabrik.de/south-america/colombia-latest.osm.pbf
```

Estos archivos son opcionales y no estan incluidos en el vault base.

---

## Resumen de Tamanos

| Componente | Tamanio | Estado |
|------------|---------|--------|
| Vault base | ~1 MB | Incluido |
| Traductor NLLB-200 (Q4_K_M) | ~350 MB | Descarga separada |
| Language packs (10 builtin) | ~50 KB | Incluido |
| Language packs adicionales | ~5 KB c/u | Descargable |
| **Total con todo** | **~351 MB** | **Bajo 1 GB** |

El traductor offline es completamente opcional. El vault base (~1 MB) funciona sin el.

---

## Creditos y Licencia

**Autor:** Red Mesh sin Internet
**Licencia:** Creative Commons Attribution-ShareAlike 4.0

El contenido de supervivencia y primeros auxilios esta basado en guias reconocidas internacionalmente incluyendo:
- Cruz Roja Internacional
- OMS (Organizacion Mundial de la Salud)
- CDC (Centro de Control de Enfermedades)
- FEMA (Agencia Federal de Gestion de Emergencias)

Los datos geograficos estan basados en informacion de libre acceso de OpenStreetMap.

El modelo de traduccion NLLB-200 fue desarrollado por Meta AI bajo licencia CC-BY-NC-4.0.

---

## Actualizaciones

### v2.0.0 (2026-05-17)
- Traductor actualizado de Hy-MT a NLLB-200 Distilled 600M
- 200 idiomas (antes 33)
- Sistema de language packs descargables
- 10 idiomas builtin
- Modelo mas pequeno y eficiente

### v1.0.0 (2026-05-16)
- Version inicial del vault
- Wikipedia offline, guias, primeros auxilios, diccionario, mapas
- Traductor Hy-MT (33 idiomas)

Para reportar errores o sugerir contenido, contacta con el equipo de desarrollo de Red Mesh.

---

## Contacto y Soporte

Para asistencia tecnica o dudas sobre el uso del vault, consulta la documentacion de la aplicacion o contacta a la comunidad Red Mesh a traves de los canales de comunicacion mesh.
