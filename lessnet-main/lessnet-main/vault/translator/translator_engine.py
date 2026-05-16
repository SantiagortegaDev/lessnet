"""
NLLB-200 Traductor Offline - Motor de traduccion
Modelo: Meta NLLB-200 Distilled 600M (GGUF)
Soporta 200 idiomas con paquetes descargables por idioma

Requiere: llama-cpp-python, sentencepiece

Instalacion:
pip install llama-cpp-python sentencepiece

Uso:
from translator_engine import NLLBTranslator

translator = NLLBTranslator()
translator.load_model()
result = translator.translate("Hola mundo", "es", "en")
"""

import os
import json
import gzip
import hashlib
import threading
from pathlib import Path
from typing import Optional, Dict, List, Tuple

# ---------------------------------------------------------------------------
# Rutas base
# ---------------------------------------------------------------------------
TRANSLATOR_DIR = Path(__file__).parent
VAULT_DIR = TRANSLATOR_DIR.parent
CONFIG_PATH = TRANSLATOR_DIR / "translator_config.json"
MODELS_DIR = TRANSLATOR_DIR / "models"
LANG_PACKS_DIR = TRANSLATOR_DIR / "lang_packs"
CACHE_DIR = TRANSLATOR_DIR / "cache"

# Asegurar directorios existen
for d in [MODELS_DIR, LANG_PACKS_DIR, CACHE_DIR]:
    d.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Codigo FLORES-200 para NLLB
# ---------------------------------------------------------------------------
# NLLB-200 usa codigos FLORES-200 (ej: spa_Latn, eng_Latn)
# Este modulo mapea codigos ISO comunes a codigos FLORES-200

def _load_flores_map() -> Dict[str, dict]:
    """Carga el mapeo ISO -> FLORES-200 desde translator_config.json"""
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            config = json.load(f)
        mapeo = {}
        # Mapeo principal (incluidos por defecto)
        for iso, info in config.get("idiomas_nativos_nllb", {}).get("mapeo_principal", {}).items():
            mapeo[iso] = info
        # Mapeo extendido (descarga)
        for iso, info in config.get("idiomas_nativos_nllb", {}).get("mapeo_extendido", {}).items():
            mapeo[iso] = info
        return mapeo
    except Exception:
        # Fallback con los mas comunes
        return {
            "es": {"flores": "spa_Latn", "nombre": "Espanol"},
            "en": {"flores": "eng_Latn", "nombre": "Ingles"},
            "fr": {"flores": "fra_Latn", "nombre": "Frances"},
            "pt": {"flores": "por_Latn", "nombre": "Portugues"},
            "de": {"flores": "deu_Latn", "nombre": "Aleman"},
            "it": {"flores": "ita_Latn", "nombre": "Italiano"},
            "zh": {"flores": "zho_Hans", "nombre": "Chino simplificado"},
            "ja": {"flores": "jpn_Jpan", "nombre": "Japones"},
            "ko": {"flores": "kor_Hang", "nombre": "Coreano"},
            "ru": {"flores": "rus_Cyrl", "nombre": "Ruso"},
            "ar": {"flores": "arb_Arab", "nombre": "Arabe"},
            "hi": {"flores": "hin_Deva", "nombre": "Hindi"},
        }


FLORES_MAP = _load_flores_map()


def iso_to_flores(iso_code: str) -> Optional[str]:
    """Convierte un codigo ISO (ej: 'es') a codigo FLORES-200 (ej: 'spa_Latn')"""
    entry = FLORES_MAP.get(iso_code)
    if entry:
        return entry["flores"]
    # Si ya es formato FLORES, devolverlo tal cual
    if "_" in iso_code and len(iso_code) == 7:
        return iso_code
    return None


def flores_to_iso(flores_code: str) -> Optional[str]:
    """Convierte un codigo FLORES-200 de vuelta a ISO"""
    for iso, info in FLORES_MAP.items():
        if info.get("flores") == flores_code:
            return iso
    return flores_code  # Devolver el mismo si no se encuentra


def get_lang_name(iso_code: str) -> str:
    """Obtiene el nombre del idioma a partir del codigo ISO"""
    entry = FLORES_MAP.get(iso_code)
    if entry:
        return entry.get("nombre", iso_code)
    return iso_code


# ---------------------------------------------------------------------------
# Motor principal de traduccion NLLB-200
# ---------------------------------------------------------------------------

class NLLBTranslator:
    """
    Motor de traduccion offline usando NLLB-200 Distilled 600M (GGUF).

    El modelo unificado ya contiene los 200 idiomas. Los 'language packs'
    son archivos de metadata que activan la interfaz para cada idioma
    y proporcionan frases de ejemplo, teclado, etc.

    Uso basico:
        translator = NLLBTranslator()
        translator.load_model()
        result = translator.translate("Hola", "es", "en")
        print(result)  # -> "Hello"
    """

    def __init__(self, model_path: Optional[str] = None, config: Optional[dict] = None):
        self.model = None
        self._model_loaded = False
        self._lock = threading.Lock()

        # Cargar configuracion
        if config:
            self.config = config
        else:
            self.config = self._load_config()

        # Ruta del modelo GGUF
        if model_path:
            self.model_path = Path(model_path)
        else:
            recommended = self.config.get("modelo_unificado", {}).get(
                "archivo", "nllb-200-distilled-600m-q4_k_m.gguf"
            )
            self.model_path = MODELS_DIR / recommended

        # Configuracion runtime
        rt = self.config.get("configuracion_runtime", {})
        self.n_ctx = rt.get("n_ctx", 512)
        self.n_threads = rt.get("n_threads", 4)
        self.n_gpu_layers = rt.get("n_gpu_layers", 0)
        self.use_mmap = rt.get("use_mmap", True)
        self.use_mlock = rt.get("use_mlock", False)
        self.low_vram = rt.get("low_vram", True)
        self.max_tokens = rt.get("max_tokens", 256)
        self.temperature = rt.get("temperature", 0.1)
        self.top_p = rt.get("top_p", 0.95)
        self.repeat_penalty = rt.get("repeat_penalty", 1.1)

        # Cache de traducciones
        self._cache: Dict[str, str] = {}
        self._cache_enabled = True
        self._cache_max = 500

        # Idiomas instalados
        self._installed_langs: List[str] = []

    def _load_config(self) -> dict:
        """Carga la configuracion desde translator_config.json"""
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    # -----------------------------------------------------------------------
    # Modelo
    # -----------------------------------------------------------------------

    def check_model(self) -> Tuple[bool, str]:
        """
        Verifica si el modelo GGUF existe y es valido.
        Returns:
            (existe, mensaje)
        """
        if not self.model_path.exists():
            size_mb = self.config.get("modelo_unificado", {}).get("tamano_mb", 350)
            return False, (
                f"Modelo no encontrado: {self.model_path}\n"
                f"Descargalo con download_model.sh o desde:\n"
                f"https://huggingface.co/mga18/NLLB-200-distilled-600M-GGUF\n"
                f"Tamano esperado: ~{size_mb} MB"
            )

        actual_size = self.model_path.stat().st_size / (1024 * 1024)
        expected_min = self.config.get("modelo_unificado", {}).get("tamano_mb", 350) * 0.8

        if actual_size < expected_min:
            return False, (
                f"Modelo incompleto: {actual_size:.1f} MB "
                f"(esperado ~{self.config.get('modelo_unificado', {}).get('tamano_mb', 350)} MB)\n"
                f"Descargalo de nuevo con download_model.sh"
            )

        return True, f"Modelo encontrado: {self.model_path} ({actual_size:.1f} MB)"

    def load_model(self) -> bool:
        """
        Carga el modelo GGUF en memoria usando llama-cpp-python.
        Returns:
            True si se cargo exitosamente
        """
        exists, msg = self.check_model()
        if not exists:
            raise FileNotFoundError(msg)

        try:
            from llama_cpp import Llama
        except ImportError:
            raise ImportError(
                "llama-cpp-python no esta instalado.\n"
                "Instalalo con: pip install llama-cpp-python\n"
                "Para Android: pip install llama-cpp-python --extra-index-url "
                "https://abetlen.github.io/llama-cpp-python/whl/cpu"
            )

        with self._lock:
            if self._model_loaded:
                return True

            self.model = Llama(
                model_path=str(self.model_path),
                n_ctx=self.n_ctx,
                n_threads=self.n_threads,
                n_gpu_layers=self.n_gpu_layers,
                use_mmap=self.use_mmap,
                use_mlock=self.use_mlock,
                low_vram=self.low_vram,
                verbose=False,
            )
            self._model_loaded = True

        return True

    def unload_model(self):
        """Libera el modelo de memoria"""
        with self._lock:
            if self.model is not None:
                del self.model
                self.model = None
            self._model_loaded = False

    @property
    def is_loaded(self) -> bool:
        return self._model_loaded

    # -----------------------------------------------------------------------
    # Traduccion
    # -----------------------------------------------------------------------

    def _build_prompt(self, text: str, src_lang: str, tgt_lang: str) -> str:
        """
        Construye el prompt para NLLB-200 en formato GGUF.

        NLLB-200 usa tokens especiales de idioma como:
        <src_lang> texto </s> <tgt_lang>

        En formato GGUF con chat template, el prompt es:
        <|im_start|>user\nTranslate from {src} to {tgt}: {text}<|im_end|>\n<|im_start|>assistant\n
        """
        src_flores = iso_to_flores(src_lang)
        tgt_flores = iso_to_flores(tgt_lang)

        if not src_flores:
            raise ValueError(
                f"Codigo de idioma origen no valido: '{src_lang}'. "
                f"Usa codigos ISO (ej: 'es', 'en') o FLORES-200 (ej: 'spa_Latn')."
            )
        if not tgt_flores:
            raise ValueError(
                f"Codigo de idioma destino no valido: '{tgt_lang}'. "
                f"Usa codigos ISO (ej: 'es', 'en') o FLORES-200 (ej: 'spa_Latn')."
            )

        # Formato del prompt para NLLB-200 GGUF
        # El modelo GGUF de NLLB-200 usa el formato de chat con instrucciones
        prompt = (
            f"<|im_start|>user\n"
            f"Translate from {src_flores} to {tgt_flores}: {text}"
            f"<|im_end|>\n"
            f"<|im_start|>assistant\n"
        )
        return prompt

    def _cache_key(self, text: str, src_lang: str, tgt_lang: str) -> str:
        """Genera clave de cache para una traduccion"""
        raw = f"{src_lang}|{tgt_lang}|{text}"
        return hashlib.md5(raw.encode("utf-8")).hexdigest()

    def translate(self, text: str, src_lang: str = "es", tgt_lang: str = "en") -> str:
        """
        Traduce texto de un idioma a otro usando NLLB-200.

        Args:
            text: Texto a traducir
            src_lang: Codigo ISO del idioma origen (ej: 'es', 'en', 'fra_Latn')
            tgt_lang: Codigo ISO del idioma destino (ej: 'en', 'es', 'eng_Latn')

        Returns:
            Texto traducido

        Raises:
            RuntimeError: Si el modelo no esta cargado
            ValueError: Si el codigo de idioma no es valido
        """
        if not self._model_loaded:
            raise RuntimeError("Modelo no cargado. Llama a load_model() primero.")

        # Verificar cache
        if self._cache_enabled:
            key = self._cache_key(text, src_lang, tgt_lang)
            if key in self._cache:
                return self._cache[key]

        # Construir prompt
        prompt = self._build_prompt(text, src_lang, tgt_lang)

        # Generar traduccion
        result = self.model(
            prompt,
            max_tokens=self.max_tokens,
            temperature=self.temperature,
            top_p=self.top_p,
            repeat_penalty=self.repeat_penalty,
            stop=["<|im_end|>"],
        )

        # Extraer texto traducido
        translated = result["choices"][0]["text"].strip()

        # Guardar en cache
        if self._cache_enabled:
            key = self._cache_key(text, src_lang, tgt_lang)
            if len(self._cache) >= self._cache_max:
                # Eliminar la entrada mas antigua (aproximado)
                self._cache.pop(next(iter(self._cache)))
            self._cache[key] = translated

        return translated

    def translate_batch(
        self, texts: List[str], src_lang: str = "es", tgt_lang: str = "en"
    ) -> List[str]:
        """
        Traduce multiples textos de una vez.

        Args:
            texts: Lista de textos a traducir
            src_lang: Codigo ISO del idioma origen
            tgt_lang: Codigo ISO del idioma destino

        Returns:
            Lista de textos traducidos
        """
        results = []
        for text in texts:
            try:
                result = self.translate(text, src_lang, tgt_lang)
                results.append(result)
            except Exception as e:
                results.append(f"[ERROR: {e}]")
        return results

    # -----------------------------------------------------------------------
    # Language packs
    # -----------------------------------------------------------------------

    def get_installed_languages(self) -> List[dict]:
        """
        Obtiene la lista de idiomas instalados (con sus language packs).

        Returns:
            Lista de diccionarios con info de cada idioma instalado
        """
        installed = []

        # Siempre incluir los idiomas del mapeo principal (vienen con la app)
        for iso, info in FLORES_MAP.items():
            pack_file = LANG_PACKS_DIR / f"{iso}.json"
            is_installed = pack_file.exists()
            is_builtin = info.get("incluido", False)

            if is_builtin or is_installed:
                installed.append({
                    "iso": iso,
                    "flores": info.get("flores", ""),
                    "nombre": info.get("nombre", iso),
                    "script": info.get("script", ""),
                    "builtin": is_builtin,
                    "pack_installed": is_installed,
                })

        self._installed_langs = [lang["iso"] for lang in installed]
        return installed

    def get_available_languages(self) -> List[dict]:
        """
        Obtiene TODOS los idiomas disponibles (instalados + descargables).

        Returns:
            Lista de diccionarios con info de cada idioma
        """
        all_langs = []
        for iso, info in FLORES_MAP.items():
            pack_file = LANG_PACKS_DIR / f"{iso}.json"
            is_installed = pack_file.exists()
            is_builtin = info.get("incluido", False)

            all_langs.append({
                "iso": iso,
                "flores": info.get("flores", ""),
                "nombre": info.get("nombre", iso),
                "script": info.get("script", ""),
                "builtin": is_builtin,
                "installed": is_builtin or is_installed,
                "pack_available": True,
            })

        return all_langs

    def install_language_pack(self, iso_code: str) -> bool:
        """
        Instala un language pack para un idioma.
        Los language packs contienen metadata, frases de ejemplo,
        y configuracion de teclado para el idioma.

        Args:
            iso_code: Codigo ISO del idioma a instalar

        Returns:
            True si se instalo correctamente
        """
        info = FLORES_MAP.get(iso_code)
        if not info:
            return False

        pack_data = {
            "iso": iso_code,
            "flores": info.get("flores", ""),
            "nombre": info.get("nombre", iso_code),
            "script": info.get("script", ""),
            "instalado": True,
            "version": "1.0",
            "frases_ejemplo": self._get_example_phrases(iso_code),
            "teclado": self._get_keyboard_layout(iso_code),
        }

        pack_file = LANG_PACKS_DIR / f"{iso_code}.json"
        with open(pack_file, "w", encoding="utf-8") as f:
            json.dump(pack_data, f, ensure_ascii=False, indent=2)

        return True

    def uninstall_language_pack(self, iso_code: str) -> bool:
        """
        Desinstala un language pack (no se pueden desinstalar los builtin).

        Args:
            iso_code: Codigo ISO del idioma a desinstalar

        Returns:
            True si se desinstalo correctamente
        """
        # No desinstalar idiomas builtin
        info = FLORES_MAP.get(iso_code)
        if info and info.get("incluido", False):
            return False

        pack_file = LANG_PACKS_DIR / f"{iso_code}.json"
        if pack_file.exists():
            pack_file.unlink()
            return True
        return False

    def _get_example_phrases(self, iso_code: str) -> List[dict]:
        """Genera frases de ejemplo para un idioma dado"""
        # Frases de emergencia universales
        emergency_phrases = {
            "es": [
                {"texto": "Necesito ayuda", "contexto": "emergencia"},
                {"texto": "Donde esta el hospital?", "contexto": "salud"},
                {"texto": "Hay alguien herido", "contexto": "emergencia"},
                {"texto": "Necesito agua potable", "contexto": "supervivencia"},
                {"texto": "Donde puedo encontrar refugio?", "contexto": "supervivencia"},
            ],
            "en": [
                {"texto": "I need help", "contexto": "emergencia"},
                {"texto": "Where is the hospital?", "contexto": "salud"},
                {"texto": "Someone is injured", "contexto": "emergencia"},
                {"texto": "I need drinking water", "contexto": "supervivencia"},
                {"texto": "Where can I find shelter?", "contexto": "supervivencia"},
            ],
            "fr": [
                {"texto": "J'ai besoin d'aide", "contexto": "emergencia"},
                {"texto": "Ou est l'hopital?", "contexto": "salud"},
                {"texto": "Quelqu'un est blesse", "contexto": "emergencia"},
                {"texto": "J'ai besoin d'eau potable", "contexto": "supervivencia"},
                {"texto": "Ou puis-je trouver un abri?", "contexto": "supervivencia"},
            ],
            "pt": [
                {"texto": "Preciso de ajuda", "contexto": "emergencia"},
                {"texto": "Onde fica o hospital?", "contexto": "salud"},
                {"texto": "Alguem esta ferido", "contexto": "emergencia"},
                {"texto": "Preciso de agua potavel", "contexto": "supervivencia"},
                {"texto": "Onde posso encontrar abrigo?", "contexto": "supervivencia"},
            ],
        }
        return emergency_phrases.get(iso_code, [])

    def _get_keyboard_layout(self, iso_code: str) -> dict:
        """Retorna configuracion de teclado para un idioma"""
        # Layouts basicos
        layouts = {
            "es": {"tipo": "qwerty", "locale": "es"},
            "en": {"tipo": "qwerty", "locale": "en"},
            "fr": {"tipo": "azerty", "locale": "fr"},
            "de": {"tipo": "qwertz", "locale": "de"},
            "pt": {"tipo": "qwerty", "locale": "pt_BR"},
            "ar": {"tipo": "arabic", "locale": "ar"},
            "hi": {"tipo": "devanagari", "locale": "hi"},
            "ja": {"tipo": "japanese", "locale": "ja"},
            "ko": {"tipo": "korean", "locale": "ko"},
            "ru": {"tipo": "cyrillic", "locale": "ru"},
            "zh": {"tipo": "pinyin", "locale": "zh"},
        }
        return layouts.get(iso_code, {"tipo": "qwerty", "locale": iso_code})

    # -----------------------------------------------------------------------
    # Cache
    # -----------------------------------------------------------------------

    def enable_cache(self, max_size: int = 500):
        """Habilita el cache de traducciones"""
        self._cache_enabled = True
        self._cache_max = max_size

    def disable_cache(self):
        """Deshabilita y limpia el cache"""
        self._cache_enabled = False
        self._cache.clear()

    def clear_cache(self):
        """Limpia el cache de traducciones"""
        self._cache.clear()

    def save_cache_to_disk(self):
        """Guarda el cache actual a disco para persistencia entre sesiones"""
        cache_file = CACHE_DIR / "translation_cache.json.gz"
        with gzip.open(cache_file, "wt", encoding="utf-8") as f:
            json.dump(self._cache, f, ensure_ascii=False)

    def load_cache_from_disk(self):
        """Carga el cache de disco"""
        cache_file = CACHE_DIR / "translation_cache.json.gz"
        if cache_file.exists():
            try:
                with gzip.open(cache_file, "rt", encoding="utf-8") as f:
                    self._cache = json.load(f)
            except Exception:
                self._cache = {}

    # -----------------------------------------------------------------------
    # Informacion y diagnostico
    # -----------------------------------------------------------------------

    def get_info(self) -> dict:
        """Retorna informacion completa del traductor"""
        exists, msg = self.check_model()
        return {
            "modelo": self.config.get("modelo", "NLLB-200 Distilled 600M"),
            "version_config": self.config.get("version", "2.0.0"),
            "modelo_cargado": self._model_loaded,
            "modelo_existe": exists,
            "modelo_path": str(self.model_path),
            "modelo_msg": msg,
            "idiomas_disponibles": len(FLORES_MAP),
            "idiomas_instalados": len(self.get_installed_languages()),
            "cache_habilitado": self._cache_enabled,
            "cache_entradas": len(self._cache),
            "threads": self.n_threads,
            "ctx": self.n_ctx,
        }


# ---------------------------------------------------------------------------
# Funcion de conveniencia para uso rapido
# ---------------------------------------------------------------------------

_quick_translator = None


def quick_translate(text: str, src_lang: str = "es", tgt_lang: str = "en") -> str:
    """
    Traduccion rapida con una sola llamada.
    Carga el modelo automaticamente la primera vez.

    Args:
        text: Texto a traducir
        src_lang: Idioma origen (ISO)
        tgt_lang: Idioma destino (ISO)

    Returns:
        Texto traducido
    """
    global _quick_translator
    if _quick_translator is None:
        _quick_translator = NLLBTranslator()
        _quick_translator.load_model()
    return _quick_translator.translate(text, src_lang, tgt_lang)


# ---------------------------------------------------------------------------
# Main para pruebas directas
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import sys

    print("=" * 50)
    print("NLLB-200 TRADUCTOR OFFLINE")
    print("Meta AI - 200 idiomas")
    print("=" * 50)

    translator = NLLBTranslator()

    # Verificar modelo
    exists, msg = translator.check_model()
    print(f"\n{msg}")

    if not exists:
        print("\nEjecuta download_model.sh para descargar el modelo.")
        sys.exit(1)

    # Cargar modelo
    print("\nCargando modelo...")
    translator.load_model()
    print("Modelo cargado.")

    # Mostrar idiomas instalados
    installed = translator.get_installed_languages()
    print(f"\nIdiomas instalados: {len(installed)}")
    for lang in installed:
        print(f"  - {lang['nombre']} ({lang['iso']})")

    # Traduccion interactiva
    print("\n" + "=" * 50)
    print("MODO INTERACTIVO")
    print("Formato: [origen]->[destino]: texto")
    print("Ejemplos:")
    print("  es->en: Hola, como estas?")
    print("  en->es: Where is the hospital?")
    print("  es->fr: Necesito ayuda medica")
    print("\nEscribe 'q' para salir, 'info' para estado")
    print("=" * 50)

    while True:
        try:
            user_input = input("\n> ").strip()
            if not user_input:
                continue
            if user_input.lower() == "q":
                break
            if user_input.lower() == "info":
                info = translator.get_info()
                for k, v in info.items():
                    print(f"  {k}: {v}")
                continue

            # Parsear entrada
            if "->" in user_input and ":" in user_input:
                direction_part, text = user_input.split(":", 1)
                src, tgt = direction_part.strip().split("->")
                src, tgt = src.strip(), tgt.strip()
            else:
                src, tgt = "es", "en"
                text = user_input

            result = translator.translate(text, src, tgt)
            print(f"{src} -> {tgt}: {result}")

        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")

    # Limpiar
    translator.unload_model()
    print("\nHasta luego!")
