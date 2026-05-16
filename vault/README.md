[README.md](https://github.com/user-attachments/files/27855209/README.md)
# Red Mesh Vault - Contenido Offline

**Versión:** 1.0.0
**Fecha:** 2026-05-16
**Idioma:** Español (Colombia)

---

## Descripción

Este vault contiene todo el contenido necesario para que la aplicación **Red Mesh sin Internet** funcione completamente offline. Diseñado para escenarios de emergencias, apagones, desastres naturales y situaciones de censura donde la conectividad a internet no está disponible.

El vault es ligero (~45 MB comprimidos) y puede descomprimirse directamente en la carpeta de assets de la aplicación Android.

---

## Contenido del Vault

### 1. Guías de Supervivencia (`guides/supervivencia.json`)

15 guías detalladas para situaciones de emergencia covering:

- **Agua potable** - Cómo encontrar, purificar y almacenar agua
- **Refugio** - Construcción de refugios improvisados
- **Fuego** - Métodos para encender fuego sin cerillas
- **Señales de emergencia** - Comunicación cuando no hay ayuda disponible
- **Navegación** - Orientación sin GPS ni brújula
- **Desastres naturales** - Terremotos, inundaciones, huracanes
- **Evacuación** - Planes y protocolos de evacuación
- **Comunicación mesh** - Uso de la red mesh sin internet
- **Alimentación** - Nutrición en situaciones de crisis
- **Seguridad en protestas** - Protección en disturbios civiles
- **Sobrevivir apagones** - Manejo de cortes de electricidad prolongados
- **Primeros auxilios psicológicos** - Apoyo emocional en emergencias
- **Optimizar red mesh** - Técnicas avanzadas para mejor rendimiento
- **Cifrado y privacidad** - Protección de comunicaciones
- **Supervivencia urbana** - Guía general de supervivencia

### 2. Primeros Auxilios (`first_aid/primeros_auxilios.json`)

12 protocolos médicos de emergencia:

- **RCP** - Reanimación cardiopulmonar
- **Hemorragias** - Control de sangrados severos
- **Quemaduras** - Tratamiento de quemaduras térmicas y químicas
- **Maniobra de Heimlich** - Desobstrucción de vías respiratorias
- **Shock** - Manejo del shock circulatorio
- **Fracturas** - Inmovilización y estabilización
- **Mordeduras de serpiente** - Protocolo antiofídico
- **Envenenamiento** - Intoxicaciones diversas
- **Hipotermia** - Tratamiento de exposición al frío
- **Golpe de calor** - Emergencia por hipertermia
- **Intoxicación por CO** - Monóxido de carbono
- **Convulsiones** - Manejo de crisis epilépticas

### 3. Diccionario (`dictionary/`)

- **diccionario.db** - Base de datos SQLite con FTS5 para búsqueda full-text
- **diccionario_index.json** - Índice JSON para búsqueda rápida

298 términos organizados en categorías:
- Medicina (RCP, hemorragia, quemadura, etc.)
- Supervivencia (agua, refugio, fuego, etc.)
- Tecnología (mesh, WiFi Direct, cifrado, etc.)
- Comunicación (señales, frecuencias, etc.)
- Seguridad (OPSEC, amenazas, etc.)
- Salud mental (trauma, resiliencia, etc.)

### 4. Wikipedia Offline (`wikipedia/wikipedia_offline.json`)

100 artículos esenciales de Wikipedia en español:

- **Medicina**: 20 artículos de salud y primeros auxilios
- **Supervivencia**: 9 artículos de técnicas de supervivencia
- **Geografía**: 10 artículos de Colombia y regiones
- **Tecnología**: 10 artículos de tecnología mesh y comunicaciones
- **Historia**: 5 artículos de historia colombiana y latinoamericana
- **Ciencia**: 7 artículos de ciencia general

### 5. Mapas de Colombia (`maps/colombia_emergencias.geojson`)

55 ciudades principales de Colombia incluyendo:
- Coordenadas GPS (lat/lng)
- Población y altitud
- Tipo (capital, municipio)
- Servicios disponibles (aeropuerto, hospital)

20 rutas principales entre ciudades con distancias.

---

## Requisitos de Instalación

### Requisitos del dispositivo:
- **Android 8.0 (API 26)** o superior
- **500 MB** de almacenamiento libre
- **2 GB RAM** mínimo recomendado

### Requisitos de la aplicación:
- Compatible con **Kiwix SDK** para navegación Wikipedia
- Compatible con **MapLibre** para mapas offline
- Funciona **100% offline**

---

## Instalación

### Método automático (desde la app):
1. Descarga el archivo `Red_Mesh_Vault.zip`
2. La aplicación detectará e instalará automáticamente

### Método manual:
1. Descomprime el archivo `Red_Mesh_Vault.zip`
2. Copia el contenido a la carpeta `assets/` de la aplicación
3. Reinicia la aplicación

---

## Estructura de Archivos

```
vault/
├── manifest.json              # Metadatos y versión
├── index.json                 # Índice unificado de búsqueda
├── README.md                  # Este archivo
├── guides/
│   ├── supervivencia.json     # 15 guías de supervivencia
│   └── supervivencia.json.gz  # Versión comprimida
├── first_aid/
│   ├── primeros_auxilios.json # 12 protocolos médicos
│   └── primeros_auxilios.json.gz
├── dictionary/
│   ├── diccionario.db         # SQLite con FTS5
│   └── diccionario_index.json  # Índice JSON
├── wikipedia/
│   ├── wikipedia_offline.json  # 100 artículos
│   └── wikipedia_offline.json.gz
├── maps/
│   ├── colombia_emergencias.geojson  # Ciudades y rutas
│   └── colombia_emergencias.geojson.gz
└── assets/                    # Para recursos futuros
```

---

## Optimización de Almacenamiento

Todos los archivos JSON incluyen versiones comprimidas en gzip (.gz). La aplicación puede usar estas versiones para reducir el uso de memoria durante la carga.

**Nota:** Los archivos .gz se incluyen para referencia. La aplicación puede generar sus propias versiones comprimidas si es necesario.

---

## Notas sobre Contenido Adicional

### Para Wikipedia completo (~200 MB):
Descarga el archivo ZIM más reciente desde:
```
https://download.kiwix.org/zim/wikipedia/wikipedia_es_all_mini_*.zim
```

### Para mapas detallados (~100 MB):
Descarga el mapa de OpenStreetMap desde:
```
https://download.geofabrik.de/south-america/colombia-latest.osm.pbf
```

Estos archivos son opcionales y no están incluidos en el vault base.

---

## Créditos y Licencia

**Autor:** Red Mesh sin Internet
**Licencia:** Creative Commons Attribution-ShareAlike 4.0

El contenido de supervivencia y primeros auxilios está basado en guías reconocidas internacionalmente incluyendo:
- Cruz Roja Internacional
- OMS (Organización Mundial de la Salud)
- CDC (Centro de Control de Enfermedades)
- FEMA (Agencia Federal de Gestión de Emergencias)

Los datos geográficos están basados en información de libre acceso de OpenStreetMap.

---

## Actualizaciones

Este vault será actualizado periódicamente con nuevo contenido y correcciones.

**Última actualización:** 2026-05-16

Para reportar errores o sugerir contenido, contacta con el equipo de desarrollo de Red Mesh.

---

## Contacto y Soporte

Para asistencia técnica o dudas sobre el uso del vault, consulta la documentación de la aplicación o contacta a la comunidad Red Mesh a través de los canales de comunicación mesh.
