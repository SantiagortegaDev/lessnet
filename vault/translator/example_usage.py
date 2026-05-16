"""
Ejemplo de uso del modelo Hy-MT para traducción offline
Requiere: llama-cpp-python, sentencepiece

Instalación:
pip install llama-cpp-python sentencepiece

Uso:
python example_usage.py
"""

import os
import json
from llama_cpp import Llama

# Configuración
MODEL_PATH = os.path.join(os.path.dirname(__file__), "Hy-MT1.5-1.8B-1.25bit.gguf")
DEFAULT_LANG_FROM = "es"
DEFAULT_LANG_TO = "en"

# Verificar si el modelo existe
def check_model():
    if not os.path.exists(MODEL_PATH):
        print(f"❌ Modelo no encontrado: {MODEL_PATH}")
        print("📥 Ejecuta download_model.sh o descarga manualmente desde:")
        print("   https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF")
        return False
    print(f"✓ Modelo encontrado: {MODEL_PATH}")
    print(f"   Tamaño: {os.path.getsize(MODEL_PATH) / 1024 / 1024:.1f} MB")
    return True

# Inicializar modelo
def load_model():
    print("🔄 Cargando modelo...")
    llm = Llama(
        model_path=MODEL_PATH,
        n_ctx=512,          # Contexto máximo
        n_threads=4,        # Hilos de CPU
        n_gpu_layers=0,     # 0 = solo CPU, aumenta si tienes GPU
        use_mmap=True,      # Usar memoria mapeada
        use_mlock=False,    # No bloquear en RAM
        low_vram=True,       # Minimizar uso de VRAM
        verbose=False
    )
    print("✓ Modelo cargado")
    return llm

# Traducir texto
def translate(llm, text, from_lang="es", to_lang="en"):
    """
    Traduce texto de un idioma a otro.

    Args:
        llm: Modelo cargado
        text: Texto a traducir
        from_lang: Código ISO del idioma origen (ej: 'es', 'en')
        to_lang: Código ISO del idioma destino (ej: 'en', 'es')

    Returns:
        Texto traducido
    """
    # Formato del prompt para Hy-MT
    prompt = f"<|im_start|>user\nTranslate from {from_lang} to {to_lang}: {text}<|im_end|>\n<|im_start|>assistant\n"

    # Generar traducción
    result = llm(
        prompt,
        max_tokens=256,
        temperature=0.1,     # Baja temperatura para traducciones más consistentes
        top_p=0.95,
        repeat_penalty=1.1,
        stop=["<|im_end|>"]
    )

    # Extraer resultado
    translated = result["choices"][0]["text"].strip()
    return translated

# Interfaz interactiva
def interactive_mode(llm):
    print("\n" + "="*50)
    print("🌐 MODO TRADUCTOR INTERACTIVO")
    print("="*50)
    print("Escribe texto para traducir. Formato: [origen]->[destino]: texto")
    print("Ejemplos:")
    print("  es->en: Hola, ¿cómo estás?")
    print("  en->es: Where is the hospital?")
    print("  es->fr: Necesito ayuda médica")
    print("\nEscribe 'q' para salir\n")

    while True:
        try:
            user_input = input("\n> ").strip()

            if user_input.lower() == 'q':
                print("¡Hasta luego!")
                break

            # Parsear entrada
            if '->' in user_input:
                parts = user_input.split('->', 1)
                direction = parts[0].strip()
                text = parts[1].strip()

                if '->' in direction:
                    from_lang, to_lang = direction.split('->')
                else:
                    from_lang, to_lang = DEFAULT_LANG_FROM, DEFAULT_LANG_TO
            else:
                # Usar valores por defecto
                from_lang, to_lang = DEFAULT_LANG_FROM, DEFAULT_LANG_TO
                text = user_input

            # Traducir
            result = translate(llm, text, from_lang.strip(), to_lang.strip())
            print(f"📝 {from_lang} -> {to_lang}: {result}")

        except KeyboardInterrupt:
            print("\n¡Hasta luego!")
            break
        except Exception as e:
            print(f"❌ Error: {e}")

# Función para batch translation
def translate_batch(llm, texts, from_lang, to_lang):
    """Traduce múltiples textos de una vez"""
    results = []
    for text in texts:
        try:
            result = translate(llm, text, from_lang, to_lang)
            results.append(result)
            print(f"✓ {text[:30]}... -> {result[:30]}...")
        except Exception as e:
            print(f"❌ Error traduciendo '{text[:20]}...': {e}")
            results.append("")
    return results

# Menú principal
def main():
    print("\n" + "="*50)
    print("🔤 TRADUCTOR OFFLINE - Hy-MT")
    print("="*50)

    if not check_model():
        return

    try:
        llm = load_model()

        # Menú
        print("\n1. Traducción interactiva")
        print("2. Traducir frase de ejemplo")
        print("3. Batch translation (prueba)")

        choice = input("\nElige opción (1-3): ").strip()

        if choice == "1":
            interactive_mode(llm)

        elif choice == "2":
            test_phrases = [
                ("es", "en", "¿Dónde está el hospital más cercano?"),
                ("en", "es", "I need water and food"),
                ("es", "fr", "Necesito ayuda médica urgente"),
                ("en", "de", "Where is the emergency exit?"),
                ("es", "pt", "Hay alguien herido, necesito ayuda"),
            ]

            print("\n📋 FRASES DE PRUEBA:")
            for from_lang, to_lang, text in test_phrases:
                result = translate(llm, text, from_lang, to_lang)
                print(f"\n{from_lang.upper()} -> {to_lang.upper()}:")
                print(f"  Original: {text}")
                print(f"  Traducción: {result}")

        elif choice == "3":
            batch = [
                "Necesito agua potable",
                "Hay una emergencia médica",
                "¿Dónde puedo encontrar refugio?",
                "Necesito contactar a alguien",
                "Hay fuego en el edificio"
            ]
            translate_batch(llm, batch, "es", "en")

        else:
            print("Opción no válida")

    except KeyboardInterrupt:
        print("\n\nSaliendo...")
    except Exception as e:
        print(f"\n❌ Error: {e}")

if __name__ == "__main__":
    main()