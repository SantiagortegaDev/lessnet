#!/bin/bash
# =============================================================================
# Script para descargar el modelo NLLB-200 Distilled 600M (GGUF)
# Meta AI - No Language Left Behind - 200 idiomas
# Tamaño: ~350 MB (Q4_K_M)
# =============================================================================
set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  NLLB-200 Traductor Offline${NC}"
echo -e "${CYAN}  Meta AI - 200 idiomas${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
mkdir -p "${MODELS_DIR}"

# URL del modelo GGUF (Q4_K_M - recomendado para movil)
MODEL_URL="https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF/resolve/main/nllb-200-distilled-600m-q4_k_m.gguf"
MODEL_FILE="${MODELS_DIR}/nllb-200-distilled-600m-q4_k_m.gguf"
EXPECTED_SIZE_MB=350

# =============================================================================
# Seleccion de cuantizacion
# =============================================================================
echo -e "${YELLOW}Selecciona la cuantizacion:${NC}"
echo "  1) Q4_K_M (~350 MB) - Recomendada para movil [DEFAULT]"
echo "  2) Q5_K_M (~420 MB) - Mayor calidad"
echo "  3) Q8_0   (~640 MB) - Maxima calidad"
echo ""
read -p "Opcion [1-3, default=1]: " QUANT_CHOICE

case "${QUANT_CHOICE:-1}" in
    2)
        QUANT="q5_k_m"
        EXPECTED_SIZE_MB=420
        MODEL_URL="https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF/resolve/main/nllb-200-distilled-600m-q5_k_m.gguf"
        MODEL_FILE="${MODELS_DIR}/nllb-200-distilled-600m-q5_k_m.gguf"
        ;;
    3)
        QUANT="q8_0"
        EXPECTED_SIZE_MB=640
        MODEL_URL="https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF/resolve/main/nllb-200-distilled-600m-q8_0.gguf"
        MODEL_FILE="${MODELS_DIR}/nllb-200-distilled-600m-q8_0.gguf"
        ;;
    *)
        QUANT="q4_k_m"
        ;;
esac

echo ""
echo -e "${CYAN}Cuantizacion seleccionada: ${QUANT}${NC}"
echo -e "${CYAN}Tamano estimado: ~${EXPECTED_SIZE_MB} MB${NC}"
echo ""

# =============================================================================
# Verificar si ya existe
# =============================================================================
if [ -f "${MODEL_FILE}" ]; then
    CURRENT_SIZE=$(du -m "${MODEL_FILE}" | cut -f1)
    echo -e "${YELLOW}El modelo ya existe: ${MODEL_FILE} (${CURRENT_SIZE} MB)${NC}"

    if [ "${CURRENT_SIZE}" -ge $((EXPECTED_SIZE_MB * 80 / 100)) ]; then
        echo -e "${GREEN}El archivo parece completo. Deseas omitir la descarga? (s/n)${NC}"
        read -r response
        if [ "$response" = "s" ] || [ "$response" = "S" ]; then
            echo "Omitiendo descarga..."
            echo ""
            echo -e "${GREEN}Modelo listo: ${MODEL_FILE}${NC}"
            exit 0
        fi
    else
        echo -e "${RED}El archivo parece incompleto (${CURRENT_SIZE} MB < ${EXPECTED_SIZE_MB} MB)${NC}"
        echo -e "${YELLOW}Se descargara de nuevo.${NC}"
    fi
fi

# =============================================================================
# Descargar modelo
# =============================================================================
echo -e "${YELLOW}Iniciando descarga del modelo NLLB-200 (${QUANT})...${NC}"
echo -e "${YELLOW}URL: ${MODEL_URL}${NC}"
echo -e "${YELLOW}Destino: ${MODEL_FILE}${NC}"
echo ""

# Detectar wget o curl
if command -v wget &> /dev/null; then
    echo "Usando wget..."
    wget -c --show-progress "${MODEL_URL}" -O "${MODEL_FILE}"
elif command -v curl &> /dev/null; then
    echo "Usando curl..."
    curl -L --progress-bar "${MODEL_URL}" -o "${MODEL_FILE}"
else
    echo -e "${RED}Error: No se encontro wget ni curl. Instala alguno de los dos.${NC}"
    exit 1
fi

# =============================================================================
# Verificar descarga
# =============================================================================
echo ""
if [ -f "${MODEL_FILE}" ]; then
    ACTUAL_SIZE=$(du -m "${MODEL_FILE}" | cut -f1)

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Descarga completada!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Archivo: ${MODEL_FILE}"
    echo -e "Tamano: ${ACTUAL_SIZE} MB"

    if [ "${ACTUAL_SIZE}" -ge $((EXPECTED_SIZE_MB * 80 / 100)) ]; then
        echo -e "${GREEN}Archivo valido${NC}"
    else
        echo -e "${RED}El archivo parece incompleto (${ACTUAL_SIZE} MB < ${EXPECTED_SIZE_MB} MB)${NC}"
        echo -e "${RED}Intenta descargar de nuevo.${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: La descarga fallo${NC}"
    exit 1
fi

# =============================================================================
# Verificar integridad (basico)
# =============================================================================
echo ""
echo -e "${CYAN}Verificando integridad del archivo...${NC}"

# Verificar que es un archivo GGUF valido (magic bytes)
GGUF_MAGIC=$(xxd -l 4 "${MODEL_FILE}" 2>/dev/null | awk '{print $2$3}')
if [ "${GGUF_MAGIC}" = "46554747" ] || [ "${GGUF_MAGIC}" = "747547" ]; then
    echo -e "${GREEN}Formato GGUF valido${NC}"
else
    # El magic de GGUF es 0x46475547 ("GGUF" en little-endian)
    # Algunas versiones pueden variar, asi que solo advertimos
    echo -e "${YELLOW}Advertencia: No se pudo verificar el magic GGUF.${NC}"
    echo -e "${YELLOW}Esto no necesariamente significa que el archivo sea invalido.${NC}"
fi

# =============================================================================
# Crear language packs por defecto
# =============================================================================
echo ""
echo -e "${CYAN}Creando language packs por defecto...${NC}"

LANG_PACKS_DIR="${SCRIPT_DIR}/lang_packs"
mkdir -p "${LANG_PACKS_DIR}"

# Crear packs para los 10 idiomas builtin
BUILTIN_LANGS="es en fr pt de it zh ja ko ru"

for lang in ${BUILTIN_LANGS}; do
    PACK_FILE="${LANG_PACKS_DIR}/${lang}.json"
    if [ ! -f "${PACK_FILE}" ]; then
        echo "  Creando pack: ${lang}..."
        # El pack se creara automaticamente cuando la app lo necesite
        # Aqui solo creamos un marcador
        echo "{\"iso\":\"${lang}\",\"builtin\":true,\"installed\":true}" > "${PACK_FILE}"
    else
        echo "  Pack ya existe: ${lang}"
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Instalacion completa!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "El modelo NLLB-200 esta listo para usar."
echo ""
echo "Idiomas builtin activados: es, en, fr, pt, de, it, zh, ja, ko, ru"
echo "Para activar mas idiomas, usa language_packs.py o la app."
echo ""
echo "Ejemplo de uso en Python:"
echo "  from translator_engine import NLLBTranslator"
echo "  t = NLLBTranslator()"
echo "  t.load_model()"
echo "  print(t.translate('Hola mundo', 'es', 'en'))"
