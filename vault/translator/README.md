# Traductor Offline - Hy-MT

**Modelo de traducción de Tencent**
**Tamaño:** 462 MB
**Idiomas:** 33 idiomas + 5 dialectos
**Formato:** GGUF (para uso con llama.cpp)

---

## Descarga del Modelo

El archivo del modelo (`Hy-MT1.5-1.8B-1.25bit.gguf`) debe descargarse manualmente debido a su tamaño.

### Método 1: Descarga directa desde Hugging Face

```bash
# Crear carpeta
mkdir -p translator
cd translator

# Descargar modelo GGUF (462 MB)
wget https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf

# O usando curl
curl -L -o Hy-MT1.5-1.8B-1.25bit.gguf https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf
```

### Método 2: Script automatizado

```bash
chmod +x download_model.sh
./download_model.sh
```

---

## Idiomas Soportados

### Idiomas Principales (33)
1. Chino (simplificado y tradicional)
2. Inglés
3. Francés
4. Alemán
5. Español
6. Portugués
7. Italiano
8. Ruso
9. Japonés
10. Coreano
11. Árabe
12. Hindi
13. Holandés
14. Polaco
15. Turco
16. Vietnamita
17. Tailandés
18. Indonesio
19. Malayo
20. Filipino
21. Hindi
22. Bengalí
23. Urdu
24. Persa
25. Griego
26. Hebreo
27. Húngaro
28. Rumano
29. Ucraniano
30. Checo
31. Sueco
32. Danés
33. Finlandés

### Dialectos (5)
- Tibetano
- Mongol
- Cantonés
- Mandarín variants
- Dialectos regionales varios

### Traducciones Disponibles
- **1,056 direcciones de traducción** (cualquier idioma a cualquier otro)
- Traducción bidireccional automática

---

## Especificaciones Técnicas

| Característica | Valor |
|----------------|-------|
| **Modelo base** | Hy-MT1.5-1.8B |
| **Cuantización** | 1.25-bit (Sherry) |
| **Tamaño archivo** | 462 MB |
| **Formato** | GGUF |
| **Uso de RAM** | ~1-2 GB |
| **Lenguaje de implementación** | Python (sugerido), o integración con llama.cpp |

---

## Integración con la App

### Usando llama.cpp (Recomendado)

```python
# Ejemplo conceptual con llama.cpp Python bindings
from llama_cpp import Llama

# Cargar modelo
llm = Llama(
    model_path="translator/Hy-MT1.5-1.8B-1.25bit.gguf",
    n_ctx=512,
    n_threads=4
)

# Traducir (ejemplo)
def translate(text, from_lang, to_lang):
    prompt = f"<|im_start|>user\nTranslate from {from_lang} to {to_lang}: {text}<|im_end|>"
    result = llm(prompt, max_tokens=200)
    return result["choices"][0]["text"]
```

### APK Demo de Android

Para pruebas, hay disponible un APK demo:
- **URL:** https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT-demo.apk
- **Tamaño:** 7.38 MB

---

## Optimización para Móvil

Para mejor rendimiento en dispositivos móviles:

1. **Uso de GPU** - Habilitar aceleración por GPU en la app
2. **Quantización adicional** - Si 462 MB es mucho, considerar versión 1-bit (más pequeña pero menor calidad)
3. **Cache de traducciones frecuentes** - Guardar traducciones comunes en memoria
4. **Hilos de procesamiento** - Usar 2-4 threads para no saturar el CPU

---

## Comparación de Tamaños

| Versión | Tamaño | Calidad |
|---------|--------|---------|
| **1.25-bit** | **462 MB** | ⭐⭐⭐⭐⭐ Excelente |
| 2-bit | ~574 MB | ⭐⭐⭐⭐⭐ Excelente |
| 4-bit (Q4) | ~900 MB | ⭐⭐⭐⭐⭐ Excelente |
| Original | ~3.6 GB | ⭐⭐⭐⭐⭐ Excelente |

La versión 1.25-bit (462 MB) es la recomendada por su equilibrio entre tamaño y calidad.

---

## Créditos

- **Modelo desarrollado por:** Tencent Hunyuan
- **Licencia:** Open Source
- **Repositorio original:** https://github.com/Tencent-Hunyuan/HY-MT
- **Modelo GGUF:** https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF

---

## Notas de Uso en Emergency Mesh

### Cuándo usar el traductor offline
- Comunicación con comunidades indígenas o afrocolombianas que hablan dialectos
- Coordinación con equipos internacionales de ayuda humanitaria
- Traducción de documentos de emergencia en múltiples idiomas
- Comunicación con migrantes venezolanos (español ↔ nativo)

### Idiomas críticos para Colombia
- Español ↔ Wayuu (La Guajira)
- Español ↔ Emberá (Chocó)
- Español ↔ Wiwa/Kogui (Sierra Nevada)
- Español ↔ Venezolano (frontera)
- Español ↔ Ingl240 MBés (ayuda internacional)

### Modo de bajo consumo
Si la batería es limitada:
1. Desactivar GPU
2. Reducir threads a 2
3. Usar cache para frases repetitivas
4. Traducir por partes si el texto es largo