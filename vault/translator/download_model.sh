#!/bin/bash
# Script para descargar el modelo Hy-MT de traducción offline
# Tamaño: 462 MB

set -e

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Descargando Hy-MT Translation Model${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# URL del modelo GGUF
MODEL_URL="https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf"
MODEL_FILE="Hy-MT1.5-1.8B-1.25bit.gguf"
EXPECTED_SIZE=462

# Verificar si ya existe
if [ -f "$MODEL_FILE" ]; then
    CURRENT_SIZE=$(du -m "$MODEL_FILE" | cut -f1)
    echo -e "${YELLOW}El modelo ya existe: $MODEL_FILE ($CURRENT_SIZE MB)${NC}"

    if [ "$CURRENT_SIZE" -ge 400 ]; then
        echo -e "${GREEN}El archivo parece completo. ¿Deseas omitir la descarga? (s/n)${NC}"
        read -r response
        if [ "$response" = "s" ] || [ "$response" = "S" ]; then
            echo "Omitiendo descarga..."
            exit 0
        fi
    fi
fi

echo -e "${YELLOW}Iniciando descarga del modelo (462 MB)...${NC}"
echo -e "${YELLOW}URL: $MODEL_URL${NC}"
echo ""

# Detectar si wget o curl está disponible
if command -v wget &> /dev/null; then
    echo "Usando wget..."
    wget -c --show-progress "$MODEL_URL" -O "$MODEL_FILE"
elif command -v curl &> /dev/null; then
    echo "Usando curl..."
    curl -L --progress-bar "$MODEL_URL" -o "$MODEL_FILE"
else
    echo -e "${RED}Error: No se encontró wget ni curl. Instala alguno de los dos.${NC}"
    exit 1
fi

# Verificar descarga
if [ -f "$MODEL_FILE" ]; then
    ACTUAL_SIZE=$(du -m "$MODEL_FILE" | cut -f1)
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Descarga completada!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Archivo: $MODEL_FILE"
    echo -e "Tamaño: ${ACTUAL_SIZE} MB"

    if [ "$ACTUAL_SIZE" -ge 400 ]; then
        echo -e "${GREEN}✓ Archivo válido${NC}"
    else
        echo -e "${RED}⚠ Archivo incompleto. Intenta descargar de nuevo.${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: La descarga falló${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}El modelo está listo para usar.${NC}"
echo "Muévelo a la carpeta translator/ de tu app si es necesario."