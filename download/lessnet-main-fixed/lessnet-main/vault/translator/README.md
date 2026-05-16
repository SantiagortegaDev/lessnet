[README.md](https://github.com/user-attachments/files/27857637/README.md)
# Traductor Offline - NLLB-200

**Modelo de traduccion de Meta AI (No Language Left Behind)**
**Tamanio:** ~350 MB (Q4_K_M)
**Idiomas:** 200 idiomas
**Formato:** GGUF (para uso con llama.cpp)

---

## Que es NLLB-200?

NLLB-200 (No Language Left Behind) es un modelo de traduccion automatica desarrollado por Meta AI que soporta 200 idiomas, incluyendo muchos idiomas de bajos recursos que historicamente no tenian buenos traductores. Es el modelo de traduccion mas inclusivo jamas creado.

### Diferencias con Hy-MT (modelo anterior)

| Caracteristica | Hy-MT (anterior) | NLLB-200 (actual) |
|----------------|------------------|-------------------|
| **Idiomas** | 33 + 5 dialectos | 200 |
| **Direcciones** | 1,056 | 39,800 |
| **Tamanio** | 462 MB | ~350 MB (Q4_K_M) |
| **RAM** | ~2 GB | ~900 MB |
| **Organizacion** | Tencent | Meta AI |
| **Idiomas africanos** | No | Si (Swahili, Yoruba, etc.) |
| **Idiomas Colombia** | Espanol solo | Espanol + portugues + frances |

---

## Sistema de Language Packs

El modelo GGUF unificado ya contiene todos los 200 idiomas. Los **language packs** son archivos de metadata que activan la interfaz para cada idioma en la app.

### Idiomas incluidos por defecto (builtin)

Estos 10 idiomas vienen activados sin necesidad de descarga adicional:

| Idioma | Codigo ISO | Codigo FLORES-200 |
|--------|-----------|-------------------|
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

### Idiomas descargables

Los 190 idiomas restantes se pueden activar descargando su language pack (~5 KB cada uno). Ejemplos notables:

- **Arabe** (`arb_Arab`) - Importante para refugiados
- **Hindi** (`hin_Deva`) - Comunidad india global
- **Suajili** (`swh_Latn`) - Africa Oriental
- **Yoruba** (`yor_Latn`) - Nigeria/Africa Occidental
- **Catalan** (`cat_Latn`) - Espana
- **Euskera** (`eus_Latn`) - Pais Vasco
- **Gallego** (`glg_Latn`) - Galicia
- **Kurdo** (`kmr_Latn`) - Comunidad kurda
- **Ucraniano** (`ukr_Cyrl`) - Refugiados ucranianos
- **Cantonés** (`yue_Hant`) - Hong Kong

---

## Descarga del Modelo

El archivo del modelo GGUF (~350 MB) debe descargarse manualmente debido a su tamanio.

### Metodo 1: Script automatizado

```bash
chmod +x download_model.sh
./download_model.sh
```

El script te permite elegir la cuantizacion:
- **Q4_K_M** (~350 MB) - Recomendada para movil
- **Q5_K_M** (~420 MB) - Mayor calidad
- **Q8_0** (~640 MB) - Maxima calidad

### Metodo 2: Descarga directa

```bash
# Crear carpeta de modelos
mkdir -p translator/models

# Q4_K_M (recomendada)
wget -c https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF/resolve/main/nllb-200-distilled-600m-q4_k_m.gguf \
  -O translator/models/nllb-200-distilled-600m-q4_k_m.gguf

# O usando curl
curl -L -o translator/models/nllb-200-distilled-600m-q4_k_m.gguf \
  https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF/resolve/main/nllb-200-distilled-600m-q4_k_m.gguf
```

---

## Instalacion de Language Packs

### Desde Python

```python
from language_packs import LanguagePackManager

manager = LanguagePackManager()

# Ver idiomas disponibles
available = manager.list_available()
for lang in available:
    print(f"{lang['nombre']} ({lang['iso']}) - {'Instalado' if lang['installed'] else 'Descargable'}")

# Instalar un idioma
manager.install_pack("ar")  # Arabe
manager.install_pack("hi")  # Hindi

# Instalar varios a la vez
manager.install_multiple(["ar", "hi", "sw", "uk"])

# Desinstalar un idioma
manager.uninstall_pack("ar")  # Los builtin no se pueden desinstalar
```

### Desde la app (Flet)

```python
# En la app, el usuario selecciona idiomas de una lista
# y la app llama a manager.install_pack(iso_code) para cada uno
```

---

## Uso del Traductor

### Uso basico en Python

```python
from translator_engine import NLLBTranslator

# Crear traductor
translator = NLLBTranslator()

# Verificar modelo
exists, msg = translator.check_model()
print(msg)

# Cargar modelo
translator.load_model()

# Traducir
result = translator.translate("Hola, como estas?", "es", "en")
print(result)  # "Hello, how are you?"

# Traducir a otro idioma
result = translator.translate("Necesito ayuda medica", "es", "fr")
print(result)  # "J'ai besoin d'aide medicale"

# Traduccion por lotes
results = translator.translate_batch(
    ["Hola", "Gracias", "Ayuda"],
    src_lang="es",
    tgt_lang="en"
)

# Descargar modelo de memoria
translator.unload_model()
```

### Traduccion rapida (una linea)

```python
from translator_engine import quick_translate

result = quick_translate("Hola mundo", "es", "en")
print(result)  # "Hello world"
```

### Usando codigos FLORES-200 directamente

```python
# NLLB usa codigos FLORES-200 internamente
# Puedes usarlos directamente:
result = translator.translate("Hola", "spa_Latn", "eng_Latn")
```

---

## Especificaciones Tecnicas

| Caracteristica | Valor |
|----------------|-------|
| **Modelo base** | NLLB-200 Distilled 600M |
| **Parametros** | 600M |
| **Cuantizacion recomendada** | Q4_K_M |
| **Tamanio archivo** | ~350 MB |
| **Formato** | GGUF |
| **Uso de RAM** | ~900 MB (Q4_K_M) |
| **Threads recomendados** | 4 |
| **Contexto maximo** | 512 tokens |
| **Temperatura** | 0.1 (baja para consistencia) |
| **Idiomas** | 200 |
| **Direcciones de traduccion** | 39,800 |

---

## Optimizacion para Movil

1. **Usar Q4_K_M** - La cuantizacion mas pequena con buena calidad
2. **2-4 threads** - No saturar el CPU del telefono
3. **Cache habilitado** - Frases repetitivas se traducen al instante
4. **mmap activado** - Reduce uso de RAM mapeando el archivo
5. **low_vram** - Minimiza uso de memoria grafica
6. **Contexto 512** - Suficiente para la mayoria de frases

### Modo de bajo consumo

```python
translator = NLLBTranslator()
translator.n_threads = 2        # Menos threads
translator.n_ctx = 256          # Contexto mas pequeno
translator.enable_cache(1000)   # Cache mas grande para compensar
```

---

## Comparacion de Cuantizaciones

| Version | Tamanio | RAM | Calidad |
|---------|---------|-----|---------|
| **Q4_K_M** | **~350 MB** | **~900 MB** | Buena - Recomendada |
| Q5_K_M | ~420 MB | ~1.1 GB | Muy buena |
| Q8_0 | ~640 MB | ~1.5 GB | Excelente |
| Original (FP16) | ~1.2 GB | ~2.5 GB | Perfecta |

---

## Estructura de Archivos

```
translator/
├── translator_config.json     # Configuracion completa del modelo
├── translator_engine.py       # Motor de traduccion (NLLBTranslator)
├── language_packs.py          # Gestor de paquetes de idioma
├── download_model.sh          # Script de descarga del modelo
├── README.md                  # Este archivo
├── models/                    # Carpeta para el modelo GGUF
│   └── nllb-200-distilled-600m-q4_k_m.gguf  # (descarga separada, ~350 MB)
├── lang_packs/                # Language packs instalados
│   ├── es.json               # Espanol (builtin)
│   ├── en.json               # Ingles (builtin)
│   ├── fr.json               # Frances (descargable)
│   └── ...                   # Mas packs por idioma
└── cache/                     # Cache de traducciones
    └── translation_cache.json.gz
```

---

## Creditos

- **Modelo desarrollado por:** Meta AI (No Language Left Behind)
- **Paper:** "No Language Left Behind: Scaling Human-Centered Machine Translation"
- **Licencia:** CC-BY-NC-4.0
- **Repositorio:** https://github.com/facebookresearch/fairseq/tree/nllb
- **Modelo original:** https://huggingface.co/facebook/nllb-200-distilled-600M
- **GGUF:** https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF

---

## Notas de Uso en Red Mesh sin Internet

### Cuando usar el traductor offline
- Comunicacion con comunidades indigenas que hablan otros idiomas
- Coordinacion con equipos internacionales de ayuda humanitaria
- Traduccion de documentos de emergencia en multiples idiomas
- Comunicacion con migrantes y refugiados
- Senales de emergencia multilingues

### Idiomas criticos para Colombia
- **Espanol** - Idioma principal (builtin)
- **Ingles** - Ayuda internacional (builtin)
- **Portugues** - Frontera con Brasil (builtin)
- **Frances** - Guyana Francesa / Haiti (builtin)
- Wayuu, Embera - No soportados directamente por NLLB, usar espanol como puente

### Nuevos idiomas relevantes con NLLB-200
- **Suajili** - Comunidad africana en Colombia
- **Haitiano** - Comunidad haitiana
- **Arabe** - Refugiados sirios/libaneses
- **Ucraniano** - Refugiados ucranianos
- **Catalan/Euskera/Gallego** - Comunidades autonomas
