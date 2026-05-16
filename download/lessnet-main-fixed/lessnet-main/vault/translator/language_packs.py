"""
NLLB-200 Language Pack Manager
Gestiona los paquetes de idioma descargables para el traductor NLLB-200.

Los language packs son metadata JSON que habilitan la interfaz para cada idioma
en la app. El modelo GGUF unificado ya contiene todos los 200 idiomas -
los packs solo activan la UI, frases de ejemplo, y configuracion de teclado.

Uso:
    from language_packs import LanguagePackManager
    manager = LanguagePackManager()
    available = manager.list_available()
    manager.download("fr")
    manager.install("fr")
"""

import os
import json
import gzip
import shutil
from pathlib import Path
from typing import Optional, Dict, List, Tuple
from datetime import datetime

TRANSLATOR_DIR = Path(__file__).parent
LANG_PACKS_DIR = TRANSLATOR_DIR / "lang_packs"
CONFIG_PATH = TRANSLATOR_DIR / "translator_config.json"

# Asegurar directorio existe
LANG_PACKS_DIR.mkdir(parents=True, exist_ok=True)


def _load_config() -> dict:
    """Carga la configuracion del traductor"""
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _get_all_lang_map() -> Dict[str, dict]:
    """Obtiene el mapa completo de idiomas desde la config"""
    config = _load_config()
    mapeo = {}
    for iso, info in config.get("idiomas_nativos_nllb", {}).get("mapeo_principal", {}).items():
        info["incluido"] = True
        mapeo[iso] = info
    for iso, info in config.get("idiomas_nativos_nllb", {}).get("mapeo_extendido", {}).items():
        info["incluido"] = False
        mapeo[iso] = info
    return mapeo


# ---------------------------------------------------------------------------
# Frases de emergencia por idioma
# ---------------------------------------------------------------------------

EMERGENCY_PHRASES = {
    "es": ["Necesito ayuda", "Donde esta el hospital?", "Hay alguien herido",
            "Necesito agua potable", "Donde puedo encontrar refugio?",
            "Hay una emergencia medica", "Necesito contactar a alguien",
            "Hay fuego en el edificio", "Evacuacion inmediata",
            "Donde estan los bomberos?"],
    "en": ["I need help", "Where is the hospital?", "Someone is injured",
            "I need drinking water", "Where can I find shelter?",
            "There is a medical emergency", "I need to contact someone",
            "There is a fire in the building", "Immediate evacuation",
            "Where are the firefighters?"],
    "fr": ["J'ai besoin d'aide", "Ou est l'hopital?", "Quelqu'un est blesse",
            "J'ai besoin d'eau potable", "Ou puis-je trouver un abri?",
            "Il y a une urgence medicale", "Je dois contacter quelqu'un",
            "Il y a un incendie dans le batiment", "Evacuation immediate",
            "Ou sont les pompiers?"],
    "pt": ["Preciso de ajuda", "Onde fica o hospital?", "Alguem esta ferido",
            "Preciso de agua potavel", "Onde posso encontrar abrigo?",
            "Ha uma emergencia medica", "Preciso contatar alguem",
            "Ha fogo no predio", "Evacuacao imediata",
            "Onde ficam os bombeiros?"],
    "de": ["Ich brauche Hilfe", "Wo ist das Krankenhaus?", "Jemand ist verletzt",
            "Ich brauche Trinkwasser", "Wo kann ich Unterkunft finden?",
            "Es gibt einen medizinischen Notfall", "Ich muss jemanden kontaktieren",
            "Es brennt im Gebaude", "Sofortige Evakuierung",
            "Wo ist die Feuerwehr?"],
    "it": ["Ho bisogno di aiuto", "Dov'e l'ospedale?", "Qualcuno e ferito",
            "Ho bisogno di acqua potabile", "Dove posso trovare rifugio?",
            "C'e un'emergenza medica", "Devo contattare qualcuno",
            "C'e un incendio nell'edificio", "Evacuazione immediata",
            "Dove sono i vigili del fuoco?"],
    "zh": ["Wo xuyao bangzhu", "Yiyuan zai nali?", "You ren shoushang le",
            "Wo xuyao yinyong shui", "Wo zai nali keyi zhaodao bibi suo?",
            "You yixue jinji qingkuang", "Wo xuyao lianxi mous ren",
            "Jianzhuwu nei you huozai", "Liji shusan",
            "Xiaofangyuan zai nali?"],
    "ja": ["Tasukete kudasai", "Byoin wa doko desu ka?", "Kega ga imasu",
            "Nomimizu ga hitsuyo desu", "Hinansho wa doko desu ka?",
            "Iryou hijou ga arimasu", "Dareka ni renraku shitai desu",
            "Biru no naka de kaji ga hasseimashita", "Sokuji hinan",
            "Shouboutai wa doko desu ka?"],
    "ko": ["Dowa juseyo", "Byeongwoneun eodi innayo?", "Buteun sarami isseoyo",
            "Masimul-i pilyohabnida", "Piancheoneun eodi isseoyo?",
            "Uigeung sanghwang-ibnida", "Nuguengae yeollaghaya habnida",
            "Geonmul-eseo hwaya ga natseubnida", "Jeungshi daepi",
            "Sobangdae eodi isseoyo?"],
    "ru": ["Mne nuzhna pomoshch", "Gde bol'nitsa?", "Kto-to ranen",
            "Mne nuzhna pit'evaya voda", "Gde mne nayti ubezhishche?",
            "Meditsinskaya ekstrennaya situatsiya", "Mne nuzhno svyazat'sya s kem-to",
            "V zdanii pozhar", "Nemnedlennaya evakuatsiya",
            "Gde pozharnaya?"],
    "ar": ["Asa'adu", "Ayna al-mustashfa?", "Hunak shakhs musab",
            "Ahtaju ila ma' shurb", "Ayna ajid mulja'a?",
            "Hala tawari' tibbiyya", "Ahtaju litisal bi-shakhs",
            "Hariq fi al-mabna", "Takhiim fawri",
            "Ayna dhat al-itiq?"],
    "hi": ["Mujhe madad chahiye", "Aspatal kahan hai?", "Koi zakhmi hai",
            "Mujhe peene ka paani chahiye", "Mujhe sharana kahan milegi?",
            "Chikitsha apat hai", "Mujhe kisi se sampark karna hai",
            "Imarat mein aag hai", "turant nikaas",
            "Aag bujhaane wale kahan hain?"],
}


# ---------------------------------------------------------------------------
# Language Pack Manager
# ---------------------------------------------------------------------------

class LanguagePackManager:
    """
    Gestor de paquetes de idioma para NLLB-200.

    Los language packs son archivos JSON con:
    - Metadata del idioma (nombre, script, codigo FLORES)
    - Frases de emergencia pre-traducidas
    - Configuracion de teclado
    - Informacion cultural relevante

    El modelo GGUF unificado ya contiene todos los 200 idiomas.
    Los packs solo proporcionan la interfaz y datos adicionales.
    """

    def __init__(self):
        self.lang_map = _get_all_lang_map()
        self.config = _load_config()

    def list_builtin(self) -> List[dict]:
        """Lista los idiomas incluidos por defecto (builtin)"""
        result = []
        for iso, info in self.lang_map.items():
            if info.get("incluido", False):
                result.append({
                    "iso": iso,
                    "flores": info.get("flores", ""),
                    "nombre": info.get("nombre", iso),
                    "script": info.get("script", ""),
                    "builtin": True,
                    "installed": True,
                })
        return result

    def list_installed(self) -> List[dict]:
        """Lista los idiomas instalados (builtin + descargados)"""
        result = []
        for iso, info in self.lang_map.items():
            pack_file = LANG_PACKS_DIR / f"{iso}.json"
            is_builtin = info.get("incluido", False)
            is_installed = pack_file.exists() or is_builtin

            if is_installed:
                result.append({
                    "iso": iso,
                    "flores": info.get("flores", ""),
                    "nombre": info.get("nombre", iso),
                    "script": info.get("script", ""),
                    "builtin": is_builtin,
                    "installed": True,
                })
        return result

    def list_available(self) -> List[dict]:
        """Lista TODOS los idiomas disponibles (instalados y descargables)"""
        result = []
        for iso, info in self.lang_map.items():
            pack_file = LANG_PACKS_DIR / f"{iso}.json"
            is_builtin = info.get("incluido", False)
            is_installed = pack_file.exists() or is_builtin

            result.append({
                "iso": iso,
                "flores": info.get("flores", ""),
                "nombre": info.get("nombre", iso),
                "script": info.get("script", ""),
                "builtin": is_builtin,
                "installed": is_installed,
                "pack_size_kb": self._estimate_pack_size(iso),
            })
        return result

    def list_downloadable(self) -> List[dict]:
        """Lista solo los idiomas que NO estan instalados"""
        all_langs = self.list_available()
        return [lang for lang in all_langs if not lang["installed"]]

    def _estimate_pack_size(self, iso: str) -> int:
        """Estima el tamano del pack en KB"""
        # Los packs son basicamente metadata JSON, ~5-10 KB cada uno
        return 5 + (len(EMERGENCY_PHRASES.get(iso, [])) * 2)

    def get_pack_info(self, iso: str) -> Optional[dict]:
        """Obtiene informacion de un language pack especifico"""
        info = self.lang_map.get(iso)
        if not info:
            return None

        pack_file = LANG_PACKS_DIR / f"{iso}.json"
        is_builtin = info.get("incluido", False)

        result = {
            "iso": iso,
            "flores": info.get("flores", ""),
            "nombre": info.get("nombre", iso),
            "script": info.get("script", ""),
            "builtin": is_builtin,
            "installed": pack_file.exists() or is_builtin,
            "pack_file": str(pack_file) if pack_file.exists() else None,
        }

        # Si el pack esta instalado, cargar su contenido
        if pack_file.exists():
            try:
                with open(pack_file, "r", encoding="utf-8") as f:
                    pack_data = json.load(f)
                result["pack_data"] = pack_data
            except Exception:
                pass

        return result

    def create_pack(self, iso: str) -> Optional[str]:
        """
        Crea un language pack para un idioma.

        Args:
            iso: Codigo ISO del idioma

        Returns:
            Ruta del archivo creado, o None si falla
        """
        info = self.lang_map.get(iso)
        if not info:
            return None

        pack_data = {
            "iso": iso,
            "flores": info.get("flores", ""),
            "nombre": info.get("nombre", iso),
            "script": info.get("script", ""),
            "version": "1.0",
            "creado": datetime.now().isoformat(),
            "frases_emergencia": [
                {"texto": phrase, "contexto": "emergencia"}
                for phrase in EMERGENCY_PHRASES.get(iso, [])
            ],
            "teclado": self._get_keyboard(iso),
            "metadatos": {
                "modelo_requerido": "nllb-200-distilled-600m",
                "formato_modelo": "gguf",
                "cuantizacion_minima": "Q4_K_M",
            }
        }

        pack_file = LANG_PACKS_DIR / f"{iso}.json"
        with open(pack_file, "w", encoding="utf-8") as f:
            json.dump(pack_data, f, ensure_ascii=False, indent=2)

        return str(pack_file)

    def install_pack(self, iso: str) -> bool:
        """
        Instala un language pack (lo crea si no existe).

        Args:
            iso: Codigo ISO del idioma

        Returns:
            True si se instalo correctamente
        """
        # Los builtin ya estan instalados
        info = self.lang_map.get(iso)
        if info and info.get("incluido", False):
            return True

        result = self.create_pack(iso)
        return result is not None

    def uninstall_pack(self, iso: str) -> bool:
        """
        Desinstala un language pack (no se pueden desinstalar los builtin).

        Args:
            iso: Codigo ISO del idioma

        Returns:
            True si se desinstalo correctamente
        """
        info = self.lang_map.get(iso)
        if info and info.get("incluido", False):
            return False  # No desinstalar builtin

        pack_file = LANG_PACKS_DIR / f"{iso}.json"
        if pack_file.exists():
            pack_file.unlink()
            return True
        return False

    def install_multiple(self, iso_codes: List[str]) -> Dict[str, bool]:
        """
        Instala multiples language packs a la vez.

        Args:
            iso_codes: Lista de codigos ISO

        Returns:
            Diccionario con el resultado de cada instalacion
        """
        results = {}
        for iso in iso_codes:
            results[iso] = self.install_pack(iso)
        return results

    def _get_keyboard(self, iso: str) -> dict:
        """Retorna la configuracion de teclado para un idioma"""
        layouts = {
            "es": {"tipo": "qwerty", "locale": "es", "caracteres_especiales": "n,a,e,i,o,u"},
            "en": {"tipo": "qwerty", "locale": "en"},
            "fr": {"tipo": "azerty", "locale": "fr", "caracteres_especiales": "e,a,e,i,o,u,c"},
            "de": {"tipo": "qwertz", "locale": "de", "caracteres_especiales": "a,o,u,ß"},
            "pt": {"tipo": "qwerty", "locale": "pt_BR", "caracteres_especiales": "a,e,i,o,u,c"},
            "it": {"tipo": "qwerty", "locale": "it", "caracteres_especiales": "a,e,i,o,u"},
            "ar": {"tipo": "arabic", "locale": "ar", "rtl": True},
            "hi": {"tipo": "devanagari", "locale": "hi"},
            "ja": {"tipo": "japanese", "locale": "ja"},
            "ko": {"tipo": "korean", "locale": "ko"},
            "ru": {"tipo": "cyrillic", "locale": "ru"},
            "zh": {"tipo": "pinyin", "locale": "zh"},
            "he": {"tipo": "hebrew", "locale": "he", "rtl": True},
            "el": {"tipo": "greek", "locale": "el"},
            "th": {"tipo": "thai", "locale": "th"},
        }
        return layouts.get(iso, {"tipo": "qwerty", "locale": iso})

    def get_stats(self) -> dict:
        """Retorna estadisticas de los language packs"""
        all_langs = self.list_available()
        installed = [l for l in all_langs if l["installed"]]
        builtin = [l for l in all_langs if l["builtin"]]
        downloadable = [l for l in all_langs if not l["installed"]]

        # Calcular tamano total de packs instalados
        total_size = 0
        for lang in installed:
            if not lang["builtin"]:
                pack_file = LANG_PACKS_DIR / f"{lang['iso']}.json"
                if pack_file.exists():
                    total_size += pack_file.stat().st_size

        return {
            "total_idiomas": len(all_langs),
            "instalados": len(installed),
            "builtin": len(builtin),
            "descargables": len(downloadable),
            "tamano_packs_instalados_bytes": total_size,
            "tamano_packs_instalados_kb": round(total_size / 1024, 1),
        }


# ---------------------------------------------------------------------------
# Main para pruebas
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    manager = LanguagePackManager()

    print("=" * 50)
    print("NLLB-200 Language Pack Manager")
    print("=" * 50)

    stats = manager.get_stats()
    print(f"\nEstadisticas:")
    for k, v in stats.items():
        print(f"  {k}: {v}")

    print("\nIdiomas builtin:")
    for lang in manager.list_builtin():
        print(f"  {lang['nombre']} ({lang['iso']}) -> {lang['flores']}")

    print(f"\nIdiomas descargables: {len(manager.list_downloadable())}")
    for lang in manager.list_downloadable()[:10]:
        print(f"  {lang['nombre']} ({lang['iso']}) -> {lang['flores']}")

    if len(manager.list_downloadable()) > 10:
        print(f"  ... y {len(manager.list_downloadable()) - 10} mas")

    # Probar instalacion
    print("\nInstalando Frances...")
    result = manager.install_pack("fr")
    print(f"Resultado: {'OK' if result else 'Fallo'}")

    # Probar instalacion multiple
    print("\nInstalando Aleman, Italiano, Portugues...")
    results = manager.install_multiple(["de", "it", "pt"])
    for iso, ok in results.items():
        print(f"  {iso}: {'OK' if ok else 'Fallo'}")

    # Estadisticas actualizadas
    stats = manager.get_stats()
    print(f"\nEstadisticas actualizadas:")
    for k, v in stats.items():
        print(f"  {k}: {v}")

    # Info de un pack
    print("\nInfo de pack 'fr':")
    info = manager.get_pack_info("fr")
    if info:
        for k, v in info.items():
            if k != "pack_data":
                print(f"  {k}: {v}")
