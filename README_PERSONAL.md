# LolPlusTV – Adaptación con Cuentas Locales, Perfiles y Transferencia P2P

Este repositorio contiene la versión adaptada y mejorada de **LolPlusTV**, con soporte completo para cuentas y perfiles locales (estilo Netflix), transferencia P2P directa entre dispositivos por red local (QR + TCP con cifrado AES), nuevas fuentes de streaming en español, fallback secuencial de streams con timeout y extracción por scraping sin APIs de pago.

---

## 1. Sistema de Cuentas y Perfiles Locales (Sembast NoSQL)

La arquitectura de persistencia se migró a **Sembast** (`lib/core/storage/app_database.dart`), un motor de base de datos NoSQL 100% Dart multiplataforma y embebido, desacoplado de dependencias en la nube.

### Estructura de Datos
- **`cuentas`**:
  - `id`: Identificador UUID de la cuenta.
  - `nombre`: Nombre descriptivo (ej. "Cuenta Familiar").
  - `email`: Correo de referencia opcional.
  - `created_at`: Fecha de registro.
- **`perfiles`** (máximo 5 por cuenta):
  - `id`: UUID del perfil.
  - `cuenta_id`: Llave foránea a la cuenta propietaria.
  - `nombre`: Nombre del usuario del perfil (ej. "Papá", "Sofía", "Kids").
  - `avatar`: URL del avatar del perfil (con selección de avatares predeterminados y personalizados).
  - `es_infantil`: Booleano para modo Kids / filtro infantil.
  - `pin`: PIN de 4 dígitos opcional para proteger el perfil.
- **`favoritos`**:
  - `id`: Identificador `${perfil_id}_${contenido_id}`.
  - `perfil_id`: Perfil al que pertenece el contenido guardado.
  - `contenido_id`: ID del contenido/película/serie.
  - `titulo`, `poster`, `tipo`, `timestamp`.
- **`historial`**:
  - `id`: Identificador `${perfil_id}_${contenido_id}_${episodio_id}`.
  - `perfil_id`: Perfil activo durante la reproducción.
  - `contenido_id`, `episodio_id`, `progreso_segundos`, `duracion_total`, `fecha`.
  - `temporada`, `capitulo`, `titulo`, `poster`, `videoUrl`, `tmdbId`.

### Flujo y Funcionalidad
1. **Pantalla de Selección Estilo Netflix (`ProfileSelectionPage`)**:
   - Se muestra al abrir la app o desde el menú lateral en Android TV y móvil.
   - Permite elegir perfil instantáneamente con cambio de `perfil_id` en tiempo de ejecución.
   - Si el perfil tiene PIN de 4 dígitos configurado, solicita validación mediante teclado numérico o D-Pad antes de ingresar.
   - Permite crear nuevos perfiles (hasta un máximo estricto de 5), editar nombre, avatar, modo infantil y PIN, o eliminar perfiles y sus datos asociados.
2. **Aislamiento por Perfil**:
   - `GuardadosService` (`lib/supabase/guardados_service.dart`) y `AppDatabase.instance.getFavorites()` cargan exclusivamente los favoritos del perfil activo.
   - El historial de reproducción (`_saveCache()` y `getHistory()`) guarda y carga el progreso únicamente del perfil en uso.

---

## 2. Transferencia de Cuentas entre Dispositivos (QR + TCP Local)

Ubicación:
- Servicio: `lib/core/network/transfer_service.dart`
- Interfaz: `lib/features/profile/presentation/transfer_screen.dart`

Permite transferir todas las cuentas, perfiles, favoritos e historial de un dispositivo a otro (por ejemplo, de un teléfono móvil a un Smart TV o Android TV Box) en la misma red local WiFi/LAN sin usar servidores intermedios en la nube.

### Protocolo de Comunicación
```
Dispositivo A (Origen)                             Dispositivo B (Destino)
   [Inicia ServerSocket]
   [Genera Token UUID + PIN 4 dígitos]
   [Muestra QR con IP, Puerto, Token]  <=== (Escanea QR o ingresa IP/puerto manual)
                                              [Conecta Socket TCP]
                                              [Envía Handshake: Token + PIN]
   [Valida Token y PIN]  ===============>
   [Exporta datos Sembast a JSON]
   [Cifra con AES-CBC (key: Token+PIN)]
   [Envía Payload cifrado] ============>      [Recibe Payload y descifra]
   [Cierra socket y notifica éxito]            [Importa a Sembast local]
```

### Seguridad
- **Token UUID**: Generado aleatoriamente para cada sesión de transferencia.
- **PIN de 4 Dígitos**: Mostrado en la pantalla del dispositivo origen; debe ser ingresado en el destino.
- **Cifrado AES**: El JSON de exportación se cifra simétricamente usando una clave derivada de `SHA-256(token + pin)`.

---

## 3. Fuentes Integradas (Scrapers)

Ubicación: `lib/data/scrapers/`

1. **Cinecalidad (`cinecalidad_scraper.dart`)**:
   - Dominio: `https://www.cinecalidad.am`
   - Películas, estrenos y géneros.
   - Detección de idioma automática (latino, subtitulado, castellano, inglés).
2. **ThanhDatToday (`thanhdattoday_scraper.dart`)**:
   - Dominio: `https://thanhdattoday.online`
   - Catálogo de películas y series con paginación y búsqueda.
   - Parseo de servidores y resolución de fuentes.
3. **AnimeFLV (`animeflv_scraper.dart`)**:
   - Dominio: `https://animeflv.com.es`
   - Catálogo de anime, temporadas, lista de episodios (`var episodes`) y servidores (`var videos`).
   - Soporte para versiones subtituladas y dobladas al español latino.

### Registro en el Sistema de Addons
- Las fuentes se registran en `lib/data/scrapers/base/registry.dart` dentro de `fuentesRegistry`.
- La delegación de detalle se realiza en `lib/data/scrapers/base/detalle_scraper.dart` (`DetalleScraper.fetch`).
- La agregación de streams para el reproductor se conecta en `lib/data/aggregators/main_fuentes_servidores.dart` (`_scrapeOne`).

---

## 4. Extractor de Streams con Fallback Secuencial

Ubicación: `lib/data/aggregators/server_fallback_service.dart`

- **Fallback Automático**: Recibe la lista de servidores y los prueba uno a uno en orden.
- **Timeout Estricto de 5 Segundos**: Si un servidor no responde o no extrae el stream en 5 segundos, se descarta automáticamente y se procede al siguiente.
- **Detección y Evasión de Captchas**: Detecta retos de Cloudflare, reCAPTCHA y hCaptcha en el HTML; si un servidor requiere captcha, se omite inmediatamente sin bloquear la aplicación.
- **Extracción Headless**: Utiliza `HeadlessInAppWebView` interceptando solicitudes de red para capturar URLs `.m3u8` y `.mp4` de forma invisible.

---

## 5. TMDB y Trailers por Scraping Directo

1. **TMDB (`lib/data/scrapers/tmdb_scraper_service.dart`)**:
   - Realiza búsquedas directamente en `https://www.themoviedb.org/search?query={titulo}`.
   - Extrae carátula oficial (poster w500), fondo (backdrop), sinopsis, año, géneros y reparto (cast).
   - Guarda los resultados en la caché de **Sembast** (`cache_tmdb`) para evitar peticiones repetitivas.
2. **Trailers de YouTube (`lib/data/scrapers/trailer_service.dart`)**:
   - Busca en `https://www.youtube.com/results?search_query={titulo}+{año}+trailer+español`.
   - Extrae el `videoId` analizando el objeto `ytInitialData` del HTML.
   - Incrusta el reproductor mediante `youtube_player_iframe` en un diálogo modal responsive.

---

## 6. Android TV y Control Remoto (D-Pad)

- **TV Shell (`lib/presentation/tv/tv_shell.dart`)**:
  - Totalmente optimizado para control remoto con navegación por foco (`FocusNode`, `FocusScope`).
  - Navegación lateral entre menú, pestañas y perfiles.
- **Manifiesto Android (`android/app/src/main/AndroidManifest.xml`)**:
  - Declarado `android.software.leanback` con `required="false"`.
  - Declarado `android.hardware.touchscreen` con `required="false"`.
  - Intent filter `android.intent.category.LEANBACK_LAUNCHER`.
  - Banner TV definido en `@drawable/banner`.

---

## 7. Cómo Añadir Nuevas Fuentes y Servidores

Para agregar una nueva fuente a la aplicación:
1. Crea tu archivo de scraper en `lib/data/scrapers/mi_fuente_scraper.dart` implementando:
   - `fetch({tipo, genero, page}) -> Future<ScraperResult>`
   - `search(query) -> Future<List<BuscadorItem>>`
   - `fetchDetail({url, titulo, tipo}) -> Future<DetalleContenido>`
   - `fetchServers({url, html}) -> Future<List<DetalleServidor>>`
2. Registra la fuente en `lib/data/scrapers/base/registry.dart`:
   ```dart
   Fuente(
     id: 'mi_fuente',
     label: 'Mi Fuente',
     tipos: MiFuenteScraper.tiposDisponibles(),
     generos: MiFuenteScraper.generos,
     hasListing: true,
     hasSearch: true,
     fetch: MiFuenteScraper.fetch,
     search: MiFuenteScraper.search,
   )
   ```
3. Añade el caso en `lib/data/scrapers/base/detalle_scraper.dart`:
   ```dart
   case 'mi_fuente':
     return await MiFuenteScraper.fetchDetail(url: url, titulo: titulo, tipo: tipo);
   ```
4. En `lib/data/aggregators/main_fuentes_servidores.dart`, añade el mapeo de servidores en `_scrapeOne`.

---

## 9. Transformación a Filmotic, Branding y Preparación de Publicidad (Adsterra & HilltopAds)

La aplicación ha sido completamente transformada en **Filmotic**, estableciendo una identidad visual moderna y una arquitectura limpia libre de dependencias y enlaces externos.

### Identidad Visual y UI
- **Branding Filmotic**: Sustitución de todos los logos y nombres por la marca Filmotic. Se eliminaron pantallas de bienvenida y disclaimers obsoletos. En el reproductor se incluye la insignia "Distribuido por Filmotic".
- **Paleta Filmotic Orange**: Color base `#FF6B35` aplicado de manera consistente en botones principales, acentos de selección, barras de navegación y gradientes.
- **Limpieza de UI**:
  - Eliminados botones y enlaces externos (incluyendo Letterboxd y redes sociales).
  - Pestaña y botones de descarga desactivados (modelo exclusivo de streaming).
  - Menú de 3 puntos rediseñado como un **Bottom Sheet modal nativo** centrado para evitar desbordamientos de pantalla.
  - Botón de guardados transformado en un botón claro `+ Agregar a favoritos` / `✓ En favoritos`.
  - Pestaña "Videos" renombrada a "Trailers".
  - Configuración simplificada: únicamente Apariencia (selector TV/Celular), Cambio de perfil, Calidad de reproducción e Idioma, y Versión.

### Funcionalidad Mejorada
- **Aviso CAM para Estrenos**: Modal automático al pulsar reproducir en títulos recientes o marcados como CAM informando al usuario que la calidad se actualizará automáticamente cuando esté disponible en HD.
- **Filtro de Servidores y Deduplicación**: En "Todas las fuentes" se normalizan los títulos (`_normalizeTitle`) para eliminar duplicados, y se muestran contadores en tiempo real por servidor (ej. `Cinecalidad (24)`).
- **Barra de Búsqueda Scrollable**: Chips de filtro con scroll horizontal fluido para evitar cortes o superposición de texto en pantallas compactas.
- **Detección de Idioma y Botón de Audífonos**: Botón de audífonos (`Icons.headphones_rounded`) en el reproductor que despliega los idiomas de audio disponibles en los servidores del contenido y conmuta de servidor automáticamente conservando con precisión la posición de reproducción (`seekTo`).

### Integración Real de Publicidad con WebView (Adsterra)
> **POLÍTICA ESTRICTA**: No se utiliza Google AdMob debido a que las políticas de Google prohíben contenido con derechos de autor y suspenden cuentas de inmediato. CERO anuncios durante la reproducción de video.

La monetización se implementó mediante **WebViews locales aislados** (`flutter_inappwebview`) para máxima fiabilidad y control sobre los scripts de Adsterra, sin requerir SDKs externos desactualizados:

1. **Adsterra Banner 320x50 (`AdsterraBannerWidget`)**:
   - Carga un HTML inline con fondo transparente (`transparentBackground: true`), sin barras de desplazamiento y con interceptación de clics (`shouldOverrideUrlLoading`) para abrir los enlaces publicitarios en el navegador externo del sistema (`LaunchMode.externalApplication`).
   - Ubicación: Al final del `ListView` principal del Home (`home_page.dart`) con márgenes laterales de 16px, y al pie de la ficha de contenido (`content_page.dart`).
   - **Key aprobada**: `b40d7be87e3186a983946460caa04802`.

2. **Adsterra Native Banner (`AdsterraNativeBannerWidget`)**:
   - Widget camuflado como una tarjeta elegante más del catálogo con radio de borde de 14px, fondo oscuro (`#16161A`) y altura de 250px.
   - Ubicación: Insertado estratégicamente entre secciones del catálogo (después de "Populares", cada 5-6 filas), manteniendo solo uno por pantalla.
   - **Container ID**: `container-512fc1ea8b3c9db09a992edbaf608772`.
   - **Script URL**: `https://pl31504029.profitableratecpmnetwork.com/512fc1ea8b3c9db09a992edbaf608772/invoke.js`.

3. **Gestión Remota desde `filmotic_config.json`**:
   Las claves y URLs pueden cambiarse o pausarse en tiempo real sin recompilar la app editando la sección `"ads"` en GitHub:
   ```json
   "ads": {
     "adsterra_banner_key": "b40d7be87e3186a983946460caa04802",
     "adsterra_native_container_id": "container-512fc1ea8b3c9db09a992edbaf608772",
     "adsterra_native_script_url": "https://pl31504029.profitableratecpmnetwork.com/512fc1ea8b3c9db09a992edbaf608772/invoke.js",
     "hilltopads_vast_url": "PENDIENTE"
   }
   ```
   - Si algún valor es `""` o `"PENDIENTE"`, `AdService` retorna un `SizedBox.shrink()` invisible sin romper el layout ni generar espacios en blanco vacíos.

---

## 10. Cuatro Mejoras Mayores: Repositorio Privado, P2P con mDNS, Remote Config y Avatares Cartoon

### 10.1 Repositorio GitHub Privado y Gestión de Credenciales
- **Seguridad y `.gitignore`**:
  Se configuró `.gitignore` estricto para impedir la subida accidental de información confidencial:
  - `ads_config.dart` y `**/ads_config.dart` (claves de Adsterra y HilltopAds).
  - Archivos `.env`, APKs compilados (`*.apk`), archivos de caché y configuración local.
  - Artefactos de build de Android y Flutter (`build/`, `.dart_tool/`, `android/app/build/`).
- **Plantilla `ads_config.example.dart`**:
  Se proporciona `lib/core/services/ads_config.example.dart` con la estructura de configuración necesaria y valores de ejemplo.
- **Instrucciones para Clonar, Configurar y Compilar**:
  ```bash
  # 1. Clonar el repositorio privado
  git clone <URL_TU_REPOSITORIO_PRIVADO>
  cd Pelisapp

  # 2. Configurar el archivo de publicidad
  cp lib/core/services/ads_config.example.dart lib/core/services/ads_config.dart
  # Edita ads_config.dart con tus IDs de Adsterra o HilltopAds

  # 3. Instalar dependencias
  flutter pub get

  # 4. Compilar o ejecutar en emulador/dispositivo
  flutter run
  # O generar APK de distribución:
  flutter build apk --release
  ```
- **Conectar a un Repositorio Privado**:
  ```bash
  git remote add origin git@github.com:<tu-usuario>/<tu-repo-privado>.git
  git branch -M main
  git push -u origin main
  ```

### 10.2 P2P Simplificado con mDNS + Código PIN de 6 Dígitos
Ubicación: `lib/core/network/transfer_service.dart` y `lib/features/profile/presentation/transfer_screen.dart`

- **Anuncio en Red Local (Emisor / Origen)**:
  - Al iniciar compartir, además de levantar el `ServerSocket` TCP en un puerto dinámico, publica un servicio mDNS con el tipo `_filmotic._tcp` usando el paquete `nsd: ^5.0.1`.
  - El anuncio incluye atributos TXT:
    - `pin`: Código de verificación de 6 dígitos generado aleatoriamente.
    - `token`: Identificador de sesión UUID v4.
    - `ip`: Dirección IP local asignada.
- **Receptor / Destino**:
  1. **"Buscar dispositivos en mi red" (Botón Principal)**: Realiza descubrimiento automático mDNS en la red Wi-Fi/LAN y presenta una lista de dispositivos Filmotic disponibles con un solo toque para enlazar sin necesidad de copiar IPs ni puertos.
  2. **"Escanear QR" (Opción Secundaria - Fallback)**: Conserva el escáner de cámara nativo (`MobileScanner`) para redes complejas con aislamiento de clientes (AP isolation) donde mDNS esté restringido.
  3. **"Introducir código de 6 dígitos" (Opción Terciaria)**: Permite ingresar el PIN de 6 dígitos que se visualiza en la pantalla del emisor; el cliente resuelve automáticamente el dispositivo emisor asociado a dicho PIN en mDNS y establece la conexión TCP cifrada con AES.

### 10.3 Remote Config Dinámico sin Recompilar
Ubicación: `lib/core/services/remote_config_service.dart` y archivo plantilla `filmotic_config.json`

- **Descarga y Caché Local**:
  - Al iniciar la aplicación, intenta descargar la configuración remota desde una URL centralizada (por defecto configurable en GitHub Raw o CDN privado).
  - Almacena la configuración en la base de datos local **Sembast** con un **TTL de 24 horas**. Si no hay conexión o falla la descarga, utiliza la copia en caché o los valores predeterminados hardcodeados de emergencia.
- **Estructura del JSON (`filmotic_config.json`)**:
  ```json
  {
    "version": 1,
    "ads": {
      "adsterra_banner_id": "TU_BANNER_ID",
      "hilltopads_vast_url": "https://..."
    },
    "sources": {
      "enabled": ["cinecalidad", "thanhdattoday", "animeflv", "serieskao", "tioplus"],
      "disabled": ["pelisplus"]
    },
    "messages": {
      "maintenance": null,
      "welcome_banner": null
    },
    "min_app_version": "1.0.0"
  }
  ```
- **Integración con Componentes**:
  - `AdService`: Obtiene dinámicamente los IDs publicitarios desde `RemoteConfigService.instance`.
  - `registry.dart`: Filtra las fuentes activas en tiempo de ejecución consultando `isSourceEnabled(f.id)`.
  - `main.dart`: Compara `min_app_version` con la versión instalada. Si es mayor, despliega un diálogo modal bloqueante invitando al usuario a actualizar con botón directo al APK.

### 10.4 Avatares Cartoon y Corrección de Pantalla Negra al Cambiar Perfil
- **Galería de Avatares Cartoon Locales**:
  - Se añadieron 10 avatares cartoon de alta resolución en formato PNG en `assets/avatars/` (`avatar_1.png` a `avatar_10.png`) basados en DiceBear Adventurer.
  - No dependen de conexión a internet para renderizarse inmediatamente.
  - La base de datos y la UI (`ProfileSelectionPage`) migran automáticamente cualquier URL antigua a los avatares locales, permitiendo personalizar perfiles con una cuadrícula visual y moderna.
- **Corrección del Bug de Pantalla Negra (Fix Técnico)**:
  - **Causa Raíz**: En `ProfileSelectionPage`, cuando `allowDismiss` era verdadero, se ejecutaba `widget.onProfileSelected?.call()` (el cual ya contenía un `Navigator.of(context).pop()`) e inmediatamente después se volvía a llamar a `Navigator.of(context).pop()` dentro de `_enterApp()`. Esta doble expulsión desmontaba tanto el modal de perfiles como el shell principal (`MobileShell`), dejando al usuario viendo el canvas negro por defecto de la ventana de Flutter. Además, las pantallas dependientes no escuchaban reactivamente el cambio de perfil.
  - **Solución Implementada**:
    1. Se eliminaron las llamadas duplicadas a `Navigator.pop()` en los callbacks de `settings_page.dart`, `profile_page.dart`, `tv_supabase_tab.dart` y `supabase_section.dart`, dejando que `ProfileSelectionPage._enterApp()` controle de forma estricta y única el cierre del diálogo.
    2. Se conectó `AppDatabase.instance.activeProfileNotifier` con listeners reactivos en `MobileShell` y en `GuardadosPage` (`favorites_page.dart`), de modo que al conmutar de perfil se limpien y recarguen de inmediato los favoritos, el historial y las recomendaciones del nuevo perfil sin dejar estados inconsistentes ni pantallas negras.


---

## 11. Landing Page en GitHub Pages, Soporte de Actualizaciones y Distribución de APKs

### 11.1 Landing Page Oficial en GitHub Pages (`/docs`)
Se implementó una landing page estática moderna, de alto impacto visual y adaptada a móvil y desktop, alojada en el directorio `/docs` para servirse nativamente mediante GitHub Pages:

- **Archivos Clave**:
  - `docs/index.html`: Estructura semántica HTML5 con optimización SEO, meta tags para vista previa social, hero section con llamado a la acción (CTA) directo, cuadrícula de 4 características clave (Multi-perfil, WiFi P2P, Sin publicidad molesta, Móvil & TV), guía paso a paso para instalar en Android y pie de página legal.
  - `docs/style.css`: Diseño en tema oscuro (`#0B0B0E`), fuentes modernas (Google Fonts *Inter*), acentos con el naranja oficial de Filmotic (`#FF6B35`), efectos de glassmorphism y microinteracciones de botón.
  - `docs/app-icon.png`: Icono oficial de alta definición generado desde el branding de la app.
  - `docs/README.md`: Instrucciones directas de activación de GitHub Pages.
  - `docs/PUBLICAR.md`: Manual operativo para empaquetado de APKs y publicación de releases.
- **Enlace de Descarga Directa**:
  El botón principal apunta de forma permanente a la URL canónica de GitHub Releases:
  `https://github.com/Pokaysplash/filmotic-releases/releases/latest/download/filmotic.apk`

### 11.2 Pasos para Activar GitHub Pages en el Repositorio
1. Ve a tu repositorio en GitHub: `https://github.com/Pokaysplash/filmotic-app`.
2. Haz clic en **Settings** (pestaña superior).
3. En el menú lateral izquierdo, haz clic en **Pages**.
4. En **Build and deployment > Source**, selecciona: **Deploy from a branch**.
5. En **Branch**:
   - Rama: **`main`**
   - Carpeta: **`/docs`**
6. Haz clic en **Save**.
7. En 1-2 minutos, tu landing estará disponible en:  
   👉 **`https://pokaysplash.github.io/filmotic-app/`**

### 11.3 Distribución de Nuevas Versiones y GitHub Releases
Para compilar y publicar una actualización:

1. **Ajustar versión**: En `pubspec.yaml`, incrementa `version: 1.0.1+2` (y opcionalmente `const currentVersion = '1.0.1'` en `lib/main.dart`).
2. **Compilar APK Release**:
   ```bash
   flutter build apk --release
   ```
   El binario se genera en: `build/app/outputs/flutter-apk/app-release.apk`.
3. **Crear Release en GitHub**:
   - Ve a `https://github.com/Pokaysplash/filmotic-releases/releases` y pulsa **Draft a new release**.
   - Tag: `v1.0.0` (o `v1.0.1`).
   - Título: `Filmotic v1.0.0`.
   - Adjunta el archivo `app-release.apk` y **renómbralo exactamente a `filmotic.apk`** para asegurar compatibilidad permanente con la URL de descarga directa.
   - Publica el release.

### 11.4 Configuración Remota Ampliada (`filmotic_config.json`)
La configuración remota se sirve desde GitHub Raw:
`https://raw.githubusercontent.com/Pokaysplash/filmotic-app/main/filmotic_config.json`

Estructura completa con sección `"app"`:
```json
{
  "version": 1,
  "ads": {
    "adsterra_banner_key": "b40d7be87e3186a983946460caa04802",
    "adsterra_native_container_id": "container-512fc1ea8b3c9db09a992edbaf608772",
    "adsterra_native_script_url": "https://pl31504029.profitableratecpmnetwork.com/512fc1ea8b3c9db09a992edbaf608772/invoke.js",
    "hilltopads_vast_url": "PENDIENTE"
  },
  "sources": {
    "enabled": ["cinecalidad", "thanhdattoday", "animeflv", "serieskao", "tioplus", "cuevana", "pelisplus", "cinehax"],
    "disabled": []
  },
  "messages": {
    "maintenance": null,
    "welcome_banner": null
  },
  "app": {
    "min_version": "1.0.0",
    "latest_version": "1.0.0",
    "update_url": "https://github.com/Pokaysplash/filmotic-releases/releases/latest/download/filmotic.apk",
    "update_message": "Hay una nueva versión de Filmotic disponible. Actualiza para disfrutar de las últimas mejoras.",
    "force_update": false
  }
}
```

### 11.5 Lógica de Actualizaciones Inteligente en la App
Ubicación: `lib/core/services/remote_config_service.dart` y `lib/main.dart`

- **Comparación Semántica de Versiones (`compareVersions`)**:
  Analiza numéricamente cada componente mayor, menor y parche (ej: `1.0.1` vs `1.0.0`) ignorando sufijos de compilación (`+1`).
- **Actualización Obligatoria (Hard Gate)**:
  Se activa si `min_version` es mayor a la versión instalada o si `force_update: true`. Muestra un diálogo bloqueante (`PopScope(canPop: false)`) con botón "Descargar Actualización" que invoca `url_launcher` para abrir el navegador hacia `update_url`.
- **Actualización Opcional (Soft Prompt)**:
  Se activa si `latest_version` es mayor a la versión instalada y no hay bloqueo obligatorio.
  - Ofrece botones **"Actualizar"** y **"Más tarde"**.
  - Al pulsar **"Más tarde"**, guarda la versión descartada en la base de datos local **Sembast** (`dismissed_version`), garantizando no volver a interrumpir al usuario hasta que se publique una versión posterior.

---

## 12. Módulo de Televisión en Vivo (Live TV) y Guía EPG

Filmotic incorpora una sección completa de **Televisión en Vivo** tanto en la versión Móvil como en Android TV, utilizando listas públicas M3U y guías XMLTV del proyecto de código abierto [iptv-org](https://github.com/iptv-org/iptv).

### 12.1 Arquitectura del Módulo
Ubicación: `lib/features/live_tv/`
- **Modelos (`domain/`)**:
  - `LiveChannel`: Modelo para cada canal (id, nombre, logo, país, idioma, categoría, url de stream, bandera HD).
  - `EpgProgram`: Evento de programación EPG (id, canalId, título, descripción, categoría, inicio y fin UTC, cálculo de progreso en tiempo real).
- **Parsers y Servicios (`data/`)**:
  - `m3u_parser.dart`: Parser streaming de listas M3U/#EXTINF con extracción de etiquetas estándar (`tvg-id`, `tvg-logo`, `group-title`, `tvg-country`, etc.) y directiva cabecera `x-tvg-url`.
  - `xmltv_parser.dart`: Parser XMLTV de alto rendimiento basado en expresiones regulares y streaming. Normaliza todas las zonas horarias (+0000, -0500, etc.) a UTC y filtra con ventana rodante (-2 horas a +48 horas) para optimizar memoria RAM.
  - `live_tv_service.dart`: Descarga y administra listas M3U por país, idioma o categoría desde iptv-org. Cuenta con almacenamiento en caché local Sembast con TTL de 24 horas (`live_channels`, `live_lists_cache`).
  - `epg_service.dart`: Descarga guías XMLTV desde `epg.pw` o URLs provistas en la lista M3U. Almacena en caché local Sembast con TTL de 6 horas (`epg_programs`, `epg_meta`) y provee consultas instantáneas de "En Vivo Ahora" y "A Continuación".
- **Vistas e Interfaz (`presentation/`)**:
  - **Móvil**: `LiveTvPage` con barra de búsqueda, chips de filtro rápido por país y categoría, cards con preview "Ahora / Después" con barra de progreso en vivo, y acceso directo a `EpgPage` (vista de parrilla de tiempo horizontal/vertical).
  - **Android TV**: `LiveTvPageTv` con navegación 100% por control remoto (D-Pad), barra de previsualización superior dinámica, acceso directo a la guía de programación (`EpgPageTv`) y foco visual en color Filmotic Naranja (`#FFFF6B35`).
  - `EpgProgramDetailModal`: Modal reutilizable con ficha descriptiva del programa actual/siguiente, progreso de emisión y botón de reproducción directa.

### 12.2 Reproductor en Modo En Vivo (Live Mode)
Ubicación: `lib/features/player/presentation/player_page.dart` y `tv/tv_player_page.dart`
- Al reproducir un canal de TV en vivo (`openLiveChannel`):
  - Se oculta la barra de tiempo/seek del reproductor y los botones de adelantar/retrasar +/-10s.
  - Se activa el indicador animado pulsante `[● EN VIVO]`.
  - Se muestra el logo y nombre oficial del canal en la cabecera superior.
  - Se implementa un detector de desconexión o falla de señal con opción de reintento automático y diálogo amigable.

### 12.3 Configuración Remota (`filmotic_config.json`)
La sección `"live_tv"` permite habilitar/deshabilitar o personalizar el comportamiento del módulo dinámicamente:
```json
"live_tv": {
  "enabled": true,
  "default_country": "co",
  "default_language": "spa",
  "featured_channels": ["Caracol", "RCN", "Canal 1", "Señal Colombia"],
  "categories": [
    {"id": "general", "name": "General"},
    {"id": "news", "name": "Noticias"},
    {"id": "sports", "name": "Deportes"},
    {"id": "entertainment", "name": "Entretenimiento"},
    {"id": "movies", "name": "Películas"},
    {"id": "music", "name": "Música"},
    {"id": "kids", "name": "Infantil"}
  ],
  "epg_enabled": true,
  "epg_refresh_hours": 6,
  "epg_window_hours": 48
}
```

### 12.4 Política de Publicidad
- **En Listas / Catálogo**: Se integran banners publicitarios estándar no invasivos de Adsterra.
- **Durante la Reproducción**: **Estrictamente cero publicidad** durante la reproducción de canales en vivo o contenido de video para evitar interrupciones de transmisiones en tiempo real.

### 12.5 Aviso Legal y Exención de Responsabilidad (Disclaimer)
Filmotic no transmite, aloja, retransmite ni almacena ninguna señal audiovisual o contenido multimedia en sus propios servidores. Todas las listas M3U y fuentes de streaming utilizadas provienen del repositorio público y colaborativo de código abierto [iptv-org/iptv](https://github.com/iptv-org/iptv), el cual recopila únicamente enlaces y transmisiones oficiales de libre acceso público transmitidas por sus respectivos titulares de derechos por internet. Filmotic actúa exclusivamente como un software cliente/reproductor multimedia.

---

## 13. Limpieza de Ajustes y Comunicaciones
- **Redes Sociales**: Se eliminaron completamente los enlaces directos y códigos QR a redes sociales en la configuración de la app tanto en Móvil (`settings_page.dart`) como en TV (`tv_updates_tab.dart` y `tv_settings.dart`).
- **Canal de Telegram**: Se reserva un canal de Telegram para futuras comunicaciones con los usuarios. No se implementa todavía.

---

## 14. Correcciones de Bugs y Paridad Móvil / TV

### 14.1 Publicidad en Android TV (BLOQUE B)
- **Banner Adsterra 320x50**: Integrado al final del catálogo principal en `tv_home_page.dart` y entre las secciones horizontales de contenido.
- **Native Banner Adsterra**: Insertado cada 6-8 filas de tarjetas en el catálogo de TV con diseño adaptado a las tarjetas de contenido.
- **Accesibilidad D-Pad**: Se creó el componente `_TvAdBannerWrapper` con `FocusNode` dedicado, borde iluminado con color de acento Filmotic en foco y navegación fluida hacia arriba/abajo y apertura de menú lateral con flecha izquierda sin bloquear el carrusel.
- **Política Estricta**: Estrictamente **cero publicidad** en el reproductor de video (`tv_player_page.dart`), la guía EPG (`epg_page_tv.dart`) y la lista de canales en vivo (`live_tv_page_tv.dart`).

### 14.2 Bugs de UI (BLOQUE C)
- **Botón "Ver más" / "Ver todo" (C.1)**:
  - Se creó `CategoryListPage` (`lib/features/home/presentation/category_list_page.dart`) con diseño responsive (3 columnas en móvil, 6 en TV), soporte integral de control remoto D-Pad, badges de calificación/año y transiciones suaves (`PageRouteBuilder` con `FadeTransition` y `SlideTransition`).
  - En móvil (`home_page.dart`), se conectaron los botones "Ver Todo", "Ver más +" y tarjetas finales en carruseles de Continuar Viendo, Agregados Recientemente, Capítulos Recientes, Mejores Valoradas, Populares y Películas por Género.
  - En TV (`tv_home_page.dart`), se conectó el botón de cabecera `ver más +` y se añadió la tarjeta interactiva `_TvSeeMoreCard` al final de cada carrusel horizontal con foco D-Pad.
- **Texto extraño bajo actores (C.2)**:
  - En la ficha de contenido de TV (`tv_content_page.dart`), se corrigió el desbordamiento de 3 píxeles (`BOTTOM OVERFLOWED BY 3.0 PIXELS`) reduciendo los paddings verticales y optimizando la altura del chip de actores a 68px.

### 14.3 Bugs de Reproducción y Audio (BLOQUE D)
- **Servidores sin audio / volumen del sistema (D.1)**:
  - Se integró detección del nivel de volumen en `MainActivity.kt` (`getVolumePercent`) y `AudioBoostService`. Si el stream tiene pista de audio pero el volumen del sistema está en 0%, se alerta al usuario: *"Sube el volumen de tu dispositivo para escuchar."*
  - Badge `"Sin audio"` visible en botones de servidores cuando no disponen de pistas de audio válidas.
  - Diálogo de fallback automático tras 3 segundos de reproducción sin audio: *"Este servidor no tiene audio. ¿Cambiar a otro?"* con opciones de Sí/No.
- **Selector de idiomas y validación de servidores (D.2)**:
  - Validación y deshabilitación preventiva de opciones no disponibles (mostradas en gris con etiqueta *"No disponible"*).
  - Almacenamiento en caché en base de datos Sembast (`_serverValidationStore`) con TTL de 1 hora para evitar revalidaciones innecesarias.
  - Manejo robusto de errores con `try/catch` al cambiar de idioma: en caso de fallo, se restaura el stream y posición anterior sin interrumpir la reproducción y se notifica con un mensaje claro: *"No se pudo cambiar el idioma. Intenta con otro servidor."*

---

## 15. Correcciones Finales y Unificación del Reproductor (WAVE 2)

### 15.1 Unificación del Reproductor
- Se eliminaron por completo los modales de selección de servidores intermedios (`ServersModal`, `ServidoresModalTv`, `ServidoresModalFuentesTv`) y todos los reproductores externos (WebView, TV Discover Player).
- Toda la reproducción, sin importar la fuente, se realiza a través del reproductor único unificado (`PlayerScreen` en `player_page.dart` para móvil y `tv_player_page.dart` para TV).
- Al pulsar un contenido, el reproductor resuelve el stream silenciosamente en segundo plano usando `ServerLoader.resolvePlayable` y luego abre la interfaz del reproductor, agilizando enormemente la experiencia "Click-and-Play".

### 15.2 Correcciones de Persistencia y Navegación
- **Sembast**: Migración a `getApplicationSupportDirectory()` en `app_database.dart` para resolver problemas de persistencia en Android TV y limpieza agresiva de caché.
- **Navegación Horizontal (TV)**: Refactorización profunda de `_HorizontalSlider` en `tv_home_page.dart`. Se eliminó la reconstrucción forzada por índices para implementar smooth-scrolling nativo utilizando `ListView.builder(controller: ScrollController)`. Las tarjetas ya no saltan ni desplazan el contenido bruscamente, sino que realizan un scroll suave a su posición focal exacta.

### 15.3 Verificación de Scrapers y Auto-Reparación
- Se verificó el funcionamiento HTTP 200 OK de `ThanhDatToday` (HDToday), `AnimeFLV` y `Cinecalidad`.
- **Auto-Reparación de Remote Config**: El TTL se redujo a 6 horas y se implementó un `Timer.periodic(Duration(hours: 6))` en `remote_config_service.dart` para descargar automáticamente la última versión de `filmotic_config.json` en segundo plano sin requerir reiniciar la aplicación (especialmente útil en dispositivos de TV que permanecen suspendidos).

### 15.4 Corrección de Bugs: Diseño y Selector de Idioma (WAVE 3)
- **Bug de Layout en el Home**: Se eliminaron cortes extraños en los títulos ("Agregados Recientemente", etc.) configurando `maxLines: 1` o `2` con `TextOverflow.ellipsis`.
- **Eliminación de Filtro en el Buscador**: Se eliminó el botón y modal "Buscar en" (`_showFilterDialog`) en la pantalla de búsqueda, asegurando que el buscador consulte y agrupe siempre los resultados de todas las fuentes.
- **Selector de Idiomas Expandible**: Se refactorizó `_showAudioLanguageSelector` (en el reproductor) sustituyendo la simple lista de idiomas por un diseño agrupado con `ExpansionTile`. Al tocar un idioma, se despliega la lista individual de servidores con su nombre y calidad. Los usuarios ahora pueden probar servidores alternativos libremente si la etiqueta del scraper es incorrecta.
- **Sistema de Priorización de Servidores**: Se integró `ServerPriorityConfig` en el motor de carga de configuración remota y se aplicó la lógica de ordenamiento `_sortServersByPriority` dentro de `ServerLoader`. Los servidores ahora se organizan respetando las preferencias de la configuración (priorizando por fuentes específicas, como `cinecalidad` y `thanhdattoday`, luego por calidad y fallbacks), mejorando dramáticamente el índice de éxito en el primer intento del "Click-and-Play".

## 16. Agregador IPTV (WAVE 4)
Para mitigar la alta tasa de canales caídos en listas públicas, se creó un motor en Python (`iptv_aggregator/`) que automatiza la recolección, deduplicación y verificación de listas M3U.

- **URL de la Lista Maestra**: `https://raw.githubusercontent.com/Pokaysplash/filmotic-app/main/docs/filmotic_playlist.m3u`
- **Frecuencia de Actualización**: Cada 6 horas mediante GitHub Actions (`update_playlist.yml`).
- **Verificación**: Cada canal se valida con un ping HTTP concurrente (HEAD y GET Byte-Range). Canales inactivos se descartan.
- **Prioridad**: La app (en `live_tv_service.dart`) primero lee esta lista unificada usando la variable `custom_m3u_url`. En caso de que la lista no responda, cae automáticamente en las listas de `iptv-org` como fallback.

---

## 17. Corrección de Regresiones Pendientes y Ampliación IPTV (WAVE 6)

### 17.1 Subtítulos y Cambio de Idioma de Audio (Regresiones Críticas)
- **Subtítulos con Búsqueda Automática de IMDb ID**: En `subtitle_selector.dart` (móvil) y `tv_subtitle_selector.dart` (TV), se agregó el parámetro `tmdbId`. Si la ficha o scraper no proporcionó un `imdbId` o la carga de metadatos falló, el modal consulta dinámicamente `/movie/{id}` o `/tv/{id}/external_ids` en TMDB para resolver el `imdb_id` al vuelo, eliminando el fallo recurrente *"No se encontró IMDb ID"*.
- **Selector de Idiomas y Múltiples Servidores**: Se integró `getAllServers` en el loader del reproductor móvil y de TV. Si al abrir el menú de audífonos solo se detecta un idioma inicial, se consultan todos los servidores en segundo plano para poblar el selector con las opciones reales disponibles (Español Latino, Castellano, Inglés Subtitulado, etc.).
- **Tolerancia a Fallos en Conmutación de Servidor**: Si un cambio de idioma falla por un enlace inactivo, el reproductor restaura la reproducción previa y posición temporal sin dejar la pantalla en negro ni emitir errores permanentes.

### 17.2 Metadatos Completos e Hidratación de Favoritos (Mi Lista)
- **Persistencia Completa en Sembast**: Se aseguró el almacenamiento de todas las claves requeridas (`contenido_id`, `idcontenido`, `titulo`, `title`, `poster`, `poster_path`, `backdrop`, `backdrop_path`, `tipo`, `año`, `year`, `tmdb_id`, `vote_average`, `timestamp`, `metadatos_completos`) tanto en `app_database.dart` como en `guardados_service.dart`.
- **Actualización in-situ (`updateFavorite`)**: Permite refrescar registros existentes sin duplicar ni forzar eventos de recarga cíclica.
- **Hidratación Automática TMDB**: En `_load()` de `favorites_page.dart` (móvil) y `history_page.dart` (TV), los elementos que carezcan de carátula o título se enriquecen consultando TMDB (hasta 5 elementos por apertura para respetar límites de cuota), guardando los resultados inmediatamente.
- **Renderizado Robusto y Sin 'N/A'**: Las tarjetas de Mi Lista leen jerárquicamente `poster_path`, `poster` e `imagen`. Si la imagen no está disponible, se muestra un placeholder estilizado con icono y el título centrado. El badge de calificación solo se muestra si `rating > 0`, eliminando el texto "N/A".

### 17.3 Limpieza de Texto de Fuente en "Todas las películas/series"
- En `lib/features/discover/domain/mobile/pag.dart`, se eliminó el bloque de texto con el nombre de la fuente activa (`$_servicioLabel · $_tipoLabel · $_generoLabel`) para mantener la interfaz completamente limpia y desvinculada de nombres de proveedores externos.

### 17.4 Optimización del Agregador IPTV con Prioridad Deportiva y Española (`iptv_aggregator/`)
- **Estrategia de Filtrado por Prioridad (100% Deportes y España)**:
  - **Prioridad 1**: Todos los canales deportivos (fútbol, ESPN, Fox Sports, DAZN, Movistar Deportes, Eurosport, etc.) y todos los canales de España (`ES`). Se preservan al 100% sin importar límites y se colocan al inicio del archivo M3U para acceso prioritario.
  - **Prioridad 2**: Canales principales de LATAM (Colombia, México y Argentina).
  - **Prioridad 3**: Resto de LATAM (Chile, Perú, Venezuela, Ecuador, Uruguay, Bolivia, Paraguay) y categorías temáticas en español (Noticias, Infantil, Películas, Documentales).
  - **Prioridad 4**: Canales irrelevantes descartados previo a la verificación (fuera de la región, sin grupo o con palabras clave como `test`, `backup`, `offline`, `[not 24/7]`).
- **Curaduría de Fuentes (`sources.json`)**: Reducido a 11 fuentes clave de alta fidelidad (Colombia, Deportes, España, México, Argentina, Chile, Perú, Venezuela, Noticias, Infantil y Películas), eliminando índices globales saturados.
- **Verificación Asíncrona Acelerada**: 150 tareas concurrentes, timeout estricto por canal (`asyncio.wait_for` a 5s + 1.5s), HEAD prioritario con fallback a GET `Range: bytes=0-512`, reduciendo el tiempo de ejecución de 16m 31s a tan solo **31 segundos**.
- **Límite Suave (Soft Cap a 1200)**: Si la lista de canales activos supera los 1200, se conservan todos los de Prioridad 1 y se recorta del final de categorías secundarias. En la ejecución local se obtuvieron **1,131 canales activos** (351 deportivos, 152 de España).
- **Automatización Diaria (`update_playlist.yml`)**: Frecuencia ajustada a cada 24 horas (`0 6 * * *` UTC) con un timeout de seguridad de 15 minutos en GitHub Actions.

---

## 18. WAVE 7 – Cierre de bugs y primera beta pública

### 18.1 Cierre de Bugs Pendientes
- **A.1 Favoritos sin carátula ni nombre**:
  - En `content_page.dart` y `tv_content_page.dart`, `_toggleSaved` captura y persiste la metadata completa: `contenido_id`, `idcontenido`, `titulo`, `title`, `poster`, `poster_path`, `backdrop`, `backdrop_path`, `tipo`, `año`, `year`, `tmdb_id`, `vote_average`, `timestamp` y `metadatos_completos: true`.
  - En `content_options_modal.dart` y `tv_content_options_modal.dart`, se añadieron `timestamp` y `metadatos_completos`.
  - En `favorites_page.dart` y `history_page.dart` (TV), se amplió la hidratación automática (lote de 5 en paralelo) con fallback a búsqueda por título o slug si el ID numérico no está resuelto.
  - Fallback visual: si tras la hidratación falta póster se muestra el icono de claqueta con el título; si tampoco hay título, se visualiza "Contenido guardado sin metadatos" junto con un botón para eliminarlo directamente.
- **A.2 Subtítulos (IMDb ID y Fallback)**:
  - En `subtitle_selector.dart` y `tv_subtitle_selector.dart`, se implementó caché en Sembast (`AppDatabase.instance.setTmdbCache` / `getTmdbCache`) para la resolución del IMDb ID vía TMDB (`/external_ids`), evitando consultas repetidas.
  - Mensaje honesto y claro cuando no hay subtítulos o falla la consulta: *"No hay subtítulos disponibles para este contenido."*
- **A.3 Cambio de idioma de audio sin interrupción de posición**:
  - Se documentó la limitación técnica de HLS en el reproductor mediante un badge informativo en el modal de idioma: *"Cambia de servidor para otro idioma"*, indicando que las pistas de idioma son servidores independientes.
  - Se preservó el flujo de retención de posición (`seekTo` a la posición exacta tras inicializar el nuevo stream de audio).
  - Se integró un overlay discreto animado: *"Cambiando a [Idioma]..."* tanto en la versión móvil (`player_page.dart`) como en la versión Android TV (`tv_player_page.dart`).
- **A.4 Limpieza de menciones visuales a "Cuevana"**:
  - Eliminados los getters en desuso `_servicioLabel` en `pag.dart` y `tv_discover_page.dart`.
  - Eliminado el prefijo `'Cuevana · '` en los nombres de servidor de `server_preloader.dart`, `tv_server_preloader.dart` y `cuevana_extractor.dart`.

### 18.2 Preparación y Publicación de Versión Beta
- **Versionado unificado**:
  - `pubspec.yaml`: `version: 1.0.0-beta.1+1`.
  - `lib/main.dart`: `currentVersion = '1.0.0-beta.1'`.
  - `lib/core/constants/versiones.dart`: `currentVersionName = "1.0.0-beta.1"`, `currentVersionCode = 1`.
  - `filmotic_config.json`: actualizado bloque `app` con `1.0.0-beta.1`, `is_beta: true`, y URL de descarga hacia el release oficial.
  - `docs/index.html` & `docs/style.css`: banner superior de Beta, pill de versión actualizado y caja de advertencia en las instrucciones de instalación.
  - `README.md`: bloque de aviso superior informando del estado de Beta en desarrollo activo.

---

## 19. Comunidad y Soporte Oficial (Telegram)

- **Grupo Oficial**: [Filmotic Comunidad](https://t.me/+GFmv2pzxes8yNTcx) (`https://t.me/+GFmv2pzxes8yNTcx`).
- **Objetivo**: Punto de encuentro y canal directo para soporte al usuario, reporte de fallos, sugerencias y anuncios durante la fase de desarrollo beta.
- **Integraciones implementadas**:
  - **Ajustes en App Móvil (`settings_page.dart`)**: Nuevo ítem de configuración *"Comunidad y soporte"* con icono `Icons.groups_rounded`, color de acento `#FF6B35` y apertura de enlace externo mediante `url_launcher`.
  - **Ajustes en Android TV (`tv_updates_tab.dart`)**: Tarjeta interactiva *"Comunidad y soporte"* con soporte D-Pad nativo, borde animado de foco en naranja Filmotic (`#FF6B35`) y confirmación con tecla Select / Enter.
  - **Aviso de bienvenida en móvil (`filmotic_welcome_dialog.dart`)**: Diálogo informativo desplegado una única vez (`has_seen_welcome_dialog` en persistencia) que invita al usuario a sumarse a Telegram para reportar cualquier incidencia. Omitido en Android TV para preservar una experiencia limpia de sala.
  - **Landing Page (`docs/index.html` & `docs/style.css`)**: Botón oficial de Telegram en el header, sección *"Soporte y comunidad"* tras la cuadrícula de características y enlace en el footer.

---

## 20. WAVE 8 – Optimización de reproducción y fix de favoritos

### 20.1 Corrección de Bugs Críticos de UX

- **BLOQUE B: Fallback Inteligente y Recuperación Automática de Servidores**:
  - **Detección Inmediata de Fallo**: `VideoPlayerController.value.hasError` se supervisa activamente en `_videoListener` tanto en móvil (`player_page.dart`) como en TV (`tv_player_page.dart`). Ante cualquier excepción o caída de stream, se marca el servidor inválido y se dispara el fallback inmediato sin forzar al usuario a abandonar la pantalla.
  - **Timeout de Inicialización y Watchdog de 8 Segundos**: Se añadió un timeout estricto de 8 segundos a `_controller.initialize()` en VOD (evitando que ExoPlayer quede congelado indefinidamente en peticiones socket) y se elevó el watchdog de arranque a 8 segundos. Si la posición no avanza más allá de 300 ms en 8s, se activa automáticamente la alternancia de servidor mostrando un aviso discreto: *"Cambiando de servidor..."*.
  - **Blacklist Temporal de Servidores en Sembast (TTL 30 min)**: Todo servidor caído se guarda con marca temporal en `server_blacklist` en Sembast (`AppDatabase.instance.blacklistServer` / `isServerBlacklisted`). Mientras esté en lista negra, no vuelve a ser consultado durante la sesión, impidiendo que el usuario reincida en un servidor defectuoso.
  - **Fallback Visible (3 Intentos)**: Contador `_consecutiveServerFailures`. Si tras 3 intentos consecutivos ningún servidor arranca, se presenta un diálogo claro: *"No se pudo reproducir el contenido en ninguno de los servidores disponibles. ¿Quieres probar otra fuente?"*, con opciones para seleccionar manualmente otro servidor o regresar a la navegación.
  - **Preservación de Cola de Alternativas**: En URLs de stream directo ya resueltas (`_isDirectStreamUrl`), se mantiene y actualiza en segundo plano la lista de servidores de respaldo (`_fallbackServers`), evitando listas vacías al producirse un fallo repentino.

- **BLOQUE C: Fix del Botón "+ Favoritos" en la Ficha del Contenido**:
  - **Soporte de Título para Series (TMDB `name`)**: Se solventó la omisión del campo `name` devuelto por la API de TMDB para series televisivas tanto en `content_page.dart` como en `tv_content_page.dart`. Anteriormente, el título evaluaba a cadena vacía `''`, lo cual invalidaba los metadatos completos y ocultaba la serie en *"Mi lista"*.
  - **Protección en Sembast (`AppDatabase.toggleFavorite`)**: Se blindó la extracción de título ante cadenas vacías (`item['titulo']?.trim().isNotEmpty == true`), garantizando que siempre se seleccione un título válido (`item['name']` / `item['title']`).
  - **Resolución de ID y Estado Inicial**: En `tv_content_page.dart`, `_loadSavedState()` evalúa `widget.idcontenido > 0 ? widget.idcontenido : _resolvedTmdbId`, sincronizando fielmente el estado guardado.
  - **Interactividad y Hit Testing**: En móvil, el botón "+ Favoritos" fue envuelto en `Material` con `InkWell` (soporte táctil opaco y ripple animado).
  - **Navegación D-Pad en Android TV**: En `tv_content_page.dart`, se corrigió la navegación hacia la derecha desde el botón *"Ver Ahora"* para películas (`onRequestEpisodesView == null`), permitiendo al usuario alcanzar directamente el botón de favoritos con el control remoto.
  - **Feedback Visual Inmediato**: Actualización de estado visual inmediata (`setState` / `ValueNotifier`) y despliegue de SnackBar flotante claro: *"Añadido a Mi lista"* / *"Eliminado de Mi lista"*.

- **BLOQUE A: Optimización del Tiempo de Arranque de Reproducción**:
  - **Resolución en Paralelo (Top 3 Servidores)**: Se implementó `_resolveServersInParallel` en `ServerLoader` (`player_controller.dart` y `tv_player_controller.dart`). Los 3 primeros servidores por prioridad se prueban concurrentemente con un `Completer`; el primero en responder satisfactoriamente gana y cancela/ignora los restantes, reduciendo el arranque de ~15s a menos de ~3-5s.
  - **Pre-calentamiento en Fondo (`preResolve`)**: Al ingresar a la ficha del contenido (`content_page.dart` y `tv_content_page.dart`), se dispara en background `ServerLoader.preResolve()`. Al pulsar *"Ver ahora"*, la fuente ya se encuentra precargada en memoria/caché.
  - **Caché Sembast de Servidor Exitoso (TTL 30 min)**: Al reproducir con éxito un contenido, se guarda en el store `server_win_cache` con TTL de 30 minutos. Al volver a reproducir el mismo contenido dentro de la ventana de validez, el arranque es instantáneo.
  - **Overlay de Carga Informativo**: La pantalla de carga ahora indica *"Conectando al servidor..."* (o *"Cambiando de servidor..."*), y si la conexión supera los 8 segundos, se muestra el botón *"Probar otro servidor"* para evitar cualquier sensación de bloqueo.

## 21. WAVE 9 – Paridad TV completa, fix definitivo de favoritos y publicidad en pausa

### 21.1 Auditoría de paridad Móvil ↔ TV

Se realizó una auditoría completa comparando todas las funcionalidades entre la versión móvil y la versión Android TV. Resultado:

| Funcionalidad | Móvil | TV | Estado |
|---|---|---|---|
| Arranque rápido del reproductor (WAVE 8) | ✅ | ✅ | OK – Paridad |
| Fallback automático de servidores (WAVE 8) | ✅ | ✅ | OK – Paridad |
| Blacklist de servidores caídos (WAVE 8) | ✅ | ✅ | OK – Paridad |
| Botón de favoritos en ficha de contenido | ✅ | ✅ | **FIX en WAVE 9** |
| Navegación desde Home → Ficha con tmdbId/mediaType | ✅ | ⚠️ → ✅ | **FIX en WAVE 9** |
| Navegación desde Búsqueda → Ficha con tmdbId/mediaType | ✅ | ⚠️ → ✅ | **FIX en WAVE 9** |
| Navegación desde Categoría → Ficha con tmdbId/mediaType | ✅ | ✅ | OK |
| Toast/SnackBar de confirmación de favoritos | SnackBar | Toast overlay | **Nuevo en WAVE 9** |

### 21.2 Fix definitivo de favoritos (Bloque C)

**Causa raíz identificada**: Al navegar desde Home, secciones, búsqueda o discover hacia `PageContenido` / `TvPageContenido`, no se pasaban `tmdbId` ni `mediaType` correctamente. Esto causaba:
- TMDB 404 al intentar enriquecer datos de favoritos (el ID de la base local no es el mismo que el ID de TMDB).
- `mediaType` defaulteando a `'movie'` incluso para series, invalidando la llamada a la API.

**Archivos corregidos** (C.1 – Navegación con parámetros completos):
- `lib/features/home/presentation/movie_section.dart` — Pasa `tmdbId` explícito al construir `PageContenido`.
- `lib/features/home/presentation/series_section.dart` — Pasa `tmdbId` y `mediaType: 'tv'`.
- `lib/features/home/presentation/tv_movie_section.dart` — Pasa `tmdbId` para TV home.
- `lib/features/home/presentation/tv_series_section.dart` — Pasa `tmdbId` y `mediaType: 'tv'` para TV home.
- `lib/features/home/presentation/category_list_page.dart` — Detección mejorada de `mediaType` por tipo de categoría.
- `lib/features/search/presentation/search_page.dart` — Parseo correcto de `id` y `media_type` de resultados TMDB.
- `lib/features/search/presentation/tv_search_page.dart` — Mismo parseo correcto para TV.

**Arquitectura compartida creada** (C.2 – Modelo unificado `Contenido`):
- **`lib/core/services/guardados_bus.dart`** (nuevo): Define `Contenido` (modelo VO inmutable con `id`, `tmdbId`, `titulo`, `poster`, `mediaType`, `year`), `GuardadosBus` (ValueNotifier para propagar cambios de guardados en tiempo real) y `GuardadosCache` (fachada única que coordina `GuardadosService`, `AppDatabase` y `GuardadosBus`).
- **`lib/supabase/guardados_service.dart`**: `toggle()` ahora acepta tanto `Map` como `Contenido`, adaptándose al modelo unificado.
- **`lib/features/content/presentation/content_page.dart`**: Exporta `guardados_bus.dart`, integra `GuardadosCache` para toggle, construye `Contenido` parcial con datos del TMDB enriquecido.
- **`lib/features/content/presentation/tv_content_page.dart`**: Mismo tratamiento + `showTvToast()` para confirmar visualmente la acción con un overlay estilo Android TV.

**`showTvToast`**: Overlay animado (3s) con gradiente oscuro y borde naranja que aparece centrado encima de cualquier interfaz TV, usando `Overlay.maybeOf(context, rootOverlay: true)`.

### 21.3 Publicidad en pausa (Bloque N – Feature nueva)

**Política estricta**:
- ✅ Cero publicidad durante la reproducción activa.
- ✅ Publicidad solo visible cuando el reproductor esté en pausa real (tras haber iniciado).
- ✅ Rotación automática configurable (default 15s).
- ✅ Desaparición instantánea al reanudar.
- ✅ Respeta `pause_ad_enabled: false` desde Remote Config.
- ✅ Botón "Ocultar anuncio" descarta hasta la próxima pausa.
- ✅ Botón "Reanudar" reanuda la reproducción directamente.
- ✅ Navegación D-Pad completa para Android TV.

**Archivos creados/modificados**:
- **`lib/core/services/ad_pause_overlay.dart`** (nuevo): Widget `AdPauseOverlay` con debounce de 800ms, rotación por `Timer.periodic`, soporte D-Pad (`FocusNode` + `KeyEvent`), y diseño premium con glassmorphism oscuro.
- **`lib/core/services/ad_service.dart`**: Añadidos getters `pauseAdEnabled`, `pauseAdRotationSeconds`, `adsterraPauseBannerId`.
- **`filmotic_config.json`**: Nuevas claves `pause_ad_enabled`, `pause_ad_rotation_seconds`, `adsterra_pause_banner_id`.
- **`lib/features/player/presentation/player_page.dart`**: Integrado `AdPauseOverlay` con `_hasStartedPlaying` flag.
- **`lib/features/player/presentation/tv/tv_player_page.dart`**: Integrado `AdPauseOverlay` con `_hasStartedPlaying` flag y condición de `_showToolbarOnly`.

### 21.4 Capa de servicios compartida

- **`lib/core/services/server_loader_shared.dart`** (nuevo): `ServerLoader` consolidado, exportado tanto por `player_controller.dart` como `tv_player_controller.dart`. Elimina duplicación de lógica de resolución paralela, blacklist, y caché de servidor ganador.

---

## 22. WAVE 10 – Corrección de bugs Beta 3

### 22.1 Resumen de Bugs Corregidos
En esta iteración se corrigieron 6 problemas reportados en la Beta 2 tanto para Móvil como para Android TV:

- **BLOQUE B: Live TV – Falla de stream al pasar de preview a pantalla completa (Android TV)**:
  - **Causa**: Al pasar a pantalla completa, `tv_player_page.dart` ignoraba el stream activo resuelto en preview (`widget.videoUrl`) y volvía a forzar el índice inicial (`liveList[0]`). Si el canal había hecho failover exitoso a la opción 1 o 2 en preview, la pantalla completa intentaba de nuevo el enlace caído 0 y fallaba.
  - **Solución**: Se integró `initialPosition` en `PlayerScreen` y parámetros `initialUrl` e `initialPosition` en `openLiveChannel`. En `_initializePlayer()`, se prioriza `widget.videoUrl` sobre `liveList[_currentLiveIndex]` y se sincroniza el índice actual (`liveList.indexOf(url)`). Al tocar para pantalla completa, se pausa el preview, se toma su posición actual y URL activa, y se transfiere de forma transparente sin cortes ni reintentos innecesarios.

- **BLOQUE D: Live TV – Audio del preview continúa reproduciéndose al salir de la pestaña (Android TV)**:
  - **Causa**: `tv_shell.dart` utiliza `IndexedStack` para mantener el estado de navegación. Al cambiar de pestaña, los hijos no se destruyen y el `VideoPlayerController` del preview seguía reproduciendo audio en segundo plano.
  - **Solución**: Se añadió `final bool isActive` a `LiveTvPageTv` conectado con `_currentIndex == _kFuentesIndex` en `tv_shell.dart`. Mediante `didUpdateWidget`, al salir de la pestaña (`!widget.isActive`), el preview se pausa y se desecha inmediatamente (`dispose()`). Al reingresar (`widget.isActive`), se reconstruye limpiamente. También se añadió `WidgetsBindingObserver` para pausar ante minimizado del sistema.

- **BLOQUE C: Audio Boost – Respeto absoluto del volumen del sistema (Móvil y Android TV)**:
  - **Política Estricta**: Filmotic NUNCA altera el volumen del sistema operativo de forma programática. La app respeta fielmente el control de volumen del usuario (físico o remoto) y únicamente asegura que el reproductor interno utilice el 100% del volumen multimedia disponible (`_controller.setVolume(1.0)`).
  - **Solución**: En `android/app/src/main/kotlin/com/example/lol/MainActivity.kt`, se eliminó la llamada a `setStreamVolume` en el handler `boostVolume`. En `lib/core/services/audio_service.dart`, `boostVolume()` se convirtió en una operación intencionalmente inocua (no-op). Se eliminaron todas las llamadas a `boostVolume` en los reproductores móvil y TV.

- **BLOQUE E: Selector de idioma de audio no desplegable (Android TV)**:
  - **Causa**: En el reproductor de TV (`tv_player_page.dart`), el selector de idioma usaba un `InkWell` plano directamente sobre la etiqueta del idioma que cerraba el diálogo y forzaba el cambio a ciegas, en lugar de permitir explorar y elegir los servidores disponibles como en móvil.
  - **Solución**: Se implementó una lista interactiva optimizada para control remoto (D-Pad). Cada idioma se muestra como un grupo colapsable/expandible con icono, nombre y conteo de servidores. Al seleccionar un idioma con D-Pad, se expanden sus servidores individuales mostrando nombre, calidad y estado activo. El usuario puede seleccionar con la tecla Enter/Select el servidor específico deseado, disparando `_switchToSpecificServerTv(srv)` y manteniendo la posición del video.

- **BLOQUE F: Publicidad en pausa no aparecía**:
  - **Causa**: `AdPauseOverlay` recibía `isControlsOrModalOpen: _showControls`. Como al pausar los controles se muestran, `!isControlsOrModalOpen` resultaba falso, impidiendo que el banner apareciera. Además, en el `Stack` los controles se superponían al banner.
  - **Solución**: En `lib/core/services/ad_pause_overlay.dart`, se aseguró el fallback a `adsterraBannerKey` si el identificador es `'PENDIENTE'` o vacío. En `player_page.dart` y `tv_player_page.dart`, `AdPauseOverlay` se colocó después de los controles en el `Stack` (z-index superior) y la bandera `isControlsOrModalOpen` se reservó únicamente para modales completos de pantalla (`_showBottomPanel` / `_showBecauseYouWatched`). El debounce de 1 segundo permite que el usuario vea la pausa y controles antes de que el banner aparezca en el centro de forma elegante. Cero publicidad durante reproducción activa garantizada.

- **BLOQUE A: Desplazamiento horizontal bloqueado en la pantalla principal**:
  - **Causa**: Las listas horizontales (`ListView.builder`) de las categorías ("Continuar viendo", "Agregados Recientemente", "Populares", etc.) en `home_page.dart` no tenían definida una física explícita, generando conflictos con el `CustomScrollView` vertical padre. En `tv_home_page.dart`, `_HorizontalSlider` tenía asignado `NeverScrollableScrollPhysics()`, impidiendo cualquier desplazamiento táctil o de puntero.
  - **Solución**: Se añadió `physics: const BouncingScrollPhysics(), shrinkWrap: false` a todas las listas horizontales en móvil y TV. En TV, el desplazamiento continuo mediante flechas D-Pad (`_cycle`) y el scroll suave automático (`_scrollController.animateTo`) se preservaron al 100%.

### 22.2 Corrección Integral de Metadatos e IDs Canónicos TMDB (Resolución de Títulos Incorrectos al Guardar/Abrir)
- **Problema de Fondo**: Al navegar desde diversas fuentes o vistas (categorías, recomendaciones, listas, continuados) o al guardar contenido en Favoritos, ciertos proveedores o capas intermedias generaban colisiones de IDs locales vs. IDs TMDB, o el título original era reemplazado por el de otro contenido asociado al mismo ID numérico erróneo.
- **Solución Implementada**:
  - `parseCanonicalTmdbId`: Función utilitaria universal para normalizar de forma estricta los IDs provenientes de cualquier campo (`tmdb_id`, `idtmdb`, `idcontenido`, `contenido_id`, `id`).
  - `expectedTitle` y Verificación Canónica en TMDB: En `PageContenido` (tanto móvil como TV), se añadió el parámetro `expectedTitle`. Al consultar la API de TMDB (`/movie/{id}` o `/tv/{id}`), si el título devuelto por TMDB difiere de forma radical del título esperado de la tarjeta (por colisión de ID en el scraper), se realiza una búsqueda de rescate por título (`searchTmdbMovie` / `searchTmdbTv`) para resolver el verdadero `tmdbId` canónico del contenido.
  - Sincronización en Cascada: Actualizados todos los puntos de navegación (`home_page.dart`, `tv_home_page.dart`, `search_page.dart`, `tv_search_page.dart`, `discover_page.dart`, `derivar.dart`, `downloads_page.dart`, `movie_section.dart`, `series_section.dart`, `tv_movie_section.dart`, `tv_series_section.dart`, `category_list_page.dart`) y los modales de guardado/opciones para garantizar que el título, póster y tipo de medio persistan fielmente en Sembast.

### 22.3 Integración del Extractor Canela.TV (Master HLS 1080p con Firma JWT HS256)
- **Proveedor VOD en Español**: Se integró `CanelaService` (`lib/data/extractors/providers/canela_extractor.dart`) para películas y series.
- **Autenticación Edge y Sesión Criptográfica**:
  - Obtención de OAuth Client Credentials con `webclient-ui-app`.
  - Generación de token QPAT vinculado a `deviceId` consistente.
  - Registro de dispositivo en el microservicio Edge (`device-register-service.edge.api.canela.tv`) para adquirir la clave secreta Base64.
  - Firma dinámica de JWT tokens (`alg: HS256`, `typ: JWT`) mediante HMAC-SHA256 con payload expiratorio corto para solicitar autorización de reproducción (`playback-auth-service.edge.api.canela.tv`).
  - Obtención de streams directos BoltDNS HLS AES-128 (`master.m3u8`) con calidad 1080p y audio nativo en español latino, sin necesidad de WebViews ni reproductores externos.

### 22.4 Versionado
- Versión pública: **`v1.0.0-beta.3`** (Build 3).
- Remote Config (`filmotic_config.json`): `latest_version: "1.0.0-beta.3"`.
- Documentación y Landing Page (`docs/index.html`): actualizadas a `v1.0.0-beta.3`.

---

## 23. WAVE 11 – Casting DLNA (Enviar a TV desde Móvil)

Se implementó la funcionalidad completa de casting mediante el protocolo universal **DLNA / UPnP (Digital Living Network Alliance / Universal Plug and Play)**, permitiendo a los usuarios transmitir películas y series directamente desde su teléfono móvil a receptores en la misma red local WiFi (consolas Xbox One, Xbox Series X|S, Smart TVs Samsung/LG/Sony/TCL, TV Boxes y dongles compatibles).

### 23.1 Arquitectura y Rol de la App Móvil (DMC - Digital Media Controller)
- **Rol DMC**: La app Filmotic actúa exclusivamente como controlador de medios. Descubre los receptores DLNA (Digital Media Renderers - DMR), transmite la URL del stream resuelta por el reproductor y controla la reproducción remota (Play, Pause, Stop, Seek).
- **Sin duplicación en local**: El dispositivo receptor reproduce el stream directamente por su cuenta vía red. La reproducción local en el teléfono se pausa automáticamente al iniciar el cast para evitar duplicidad de audio y ahorrar batería.
- **Sin WebViews**: El envío se realiza puramente a nivel de red (URL directa de video y metadatos UPnP AVTransport), garantizando máxima fluidez y compatibilidad.

### 23.2 Componentes Implementados

1. **Dependencia y Configuración Android**:
   - Librería: `media_cast_dlna: ^0.3.1` (basada en el stack robusto jUPnP / Cling).
   - Permisos en `android/app/src/main/AndroidManifest.xml`:
     - `android.permission.INTERNET`
     - `android.permission.ACCESS_NETWORK_STATE`
     - `android.permission.ACCESS_WIFI_STATE`
     - `android.permission.CHANGE_WIFI_MULTICAST_STATE`
     - `android.permission.NEARBY_WIFI_DEVICES`
   - Servicio UPnP en `<application>`: `<service android:name="org.jupnp.android.AndroidUpnpServiceImpl"/>`.
   - `android/app/src/main/res/values/strings.xml`: `<string name="app_name">Filmotic</string>`.

2. **Servicio Central `CastService` (`lib/core/services/cast_service.dart`)**:
   - Singleton con inicialización segura (`init()`) de UPnP en Android.
   - **Descubrimiento en tiempo real**: `discoverDevices(timeout: 10s)` mediante `MediaCastDlnaDiscoveryEvents` escuchando eventos nativos `onDeviceFound`, `onDeviceLost` y `onRendererOffline`.
   - **Conexión con reintento automático**: `connectToDevice(deviceUdn)` con verificación de disponibilidad en red.
   - **Envío de Streams y Metadatos**: `castMedia(videoUrl, title, posterUrl)` empaqueta `VideoMetadata` (título, póster, clase UPnP `object.item.videoItem.movie`) y ejecuta `setMediaUri` + `play`.
   - **Control de Transporte Remoto**: métodos asíncronos `play()`, `pause()`, `stop()`, `seek(Duration)` y `disconnect()`.
   - **Manejo de Errores y Estados**: `ValueNotifier<CastState>` expone los estados `idle`, `discovering`, `connected`, `casting` y `error`. Si no se hallan dispositivos tras 10 segundos o el formato no es soportado, emite mensajes claros y precisos.

3. **Interfaz de Usuario y Modal de Selección (`lib/features/player/presentation/widgets/dlna_cast_sheet.dart`)**:
   - Modal bottom sheet con diseño oscuro y acento naranja Filmotic (`#FF6B35`).
   - Spinner animado durante el escaneo activo de red.
   - Listado en tiempo real con iconos dedicados: consola (Xbox), TV o equipo de audio.
   - Manejo de timeout de 10 segundos con tarjeta de aviso y botón para reintentar la búsqueda.
   - Notificación SnackBar informativa al iniciar la transmisión exitosamente ("Reproduciendo en [dispositivo]").

4. **Barra de Control Remoto Flotante (`lib/features/player/presentation/widgets/dlna_remote_control_bar.dart`)**:
   - Barra minimalista con efecto glassmorphism en la parte inferior del reproductor móvil.
   - Muestra el nombre del dispositivo activo, botón Play/Pause remoto sincronizado en tiempo real, botón Stop y botón de Desconectar.
   - Se adapta a la visibilidad de los controles generales del reproductor.

5. **Integración en el Reproductor Móvil (`lib/features/player/presentation/player_page.dart`)**:
   - Botón Cast en la barra superior con indicador reactivo de conexión (icono `cast_connected_rounded` resaltado en naranja al estar activo).
   - Diálogo de administración rápida al tocar el botón con sesión activa (opción de cambiar de dispositivo o desconectar).
   - Liberación limpia de recursos y desconexión en `dispose()` del reproductor.

### 23.3 Requisitos y Limitaciones
- **Requisitos de Red**: Teléfono móvil y dispositivo receptor deben estar conectados a la **misma red WiFi / subred local** (asegurar que el router no tenga activo "Aislamiento de Clientes / AP Isolation").
- **Dispositivos Compatibles**:
  - Consolas: Xbox One, Xbox One S/X, Xbox Series S/X (función "Play To" / DLNA habilitada por defecto).
  - Smart TVs: LG (webOS), Samsung (Tizen), Sony, Philips, TCL, Hisense, Xiaomi con soporte DLNA/DMR.
  - TV Boxes / Dongles: Android TV Boxes, Fire TV, Roku (con receptor UPnP/DLNA activo).
- **Alcance de Contenido**: Exclusivo para Video on Demand (**VOD**: Películas y Series). Si se intenta enviar TV en Vivo, la app notifica: *"El envío a TV estará disponible próximamente para TV en vivo"*.
- **Plataformas**: Implementación enfocada en Android. En iOS el soporte se integrará mediante AirPlay nativo en una fase posterior.

### 23.4 Cómo Añadir Nuevos Dispositivos Compatibles en el Futuro
- Para integrar nuevos protocolos (por ejemplo, Google Cast v2 o Apple AirPlay), basta con conectar sus controladores a la interfaz de `CastService` sin modificar los componentes de la interfaz de usuario ni los reproductores, o extender las opciones de búsqueda en `DiscoveryOptions` ampliando los `SearchTarget` a servicios UPnP propietarios adicionales.

---

## 24. Expansión de Catálogo, Refactorización de Scrapers y Búsqueda Federada (WAVE 12)

Esta fase introduce una arquitectura de scraping modular y exhaustiva, ampliación masiva de catálogos (novelas y anime), búsqueda federada paralela y rediseño del selector de idioma y servidores tanto en móvil como en Android TV con navegación D-pad.

### 24.1 Nueva Arquitectura de Fuentes y Scrapers (BLOQUE A)
1. **Modelo `Fuente` Extendido (`scraper_context.dart`)**:
   - `category`: Categoría principal ('movie', 'series', 'anime', 'novel').
   - `language`: Idioma principal de la fuente ('es', 'en', 'sub').
2. **Registro Centralizado (`registry.dart`)**:
   - Agrupación por categorías en `fuentesRegistry`.
   - Método `getFuentesByCategory(String category)` que filtra por categoría respetando `RemoteConfigService`.
   - Búsqueda federada paralela en `buscarEnFuentes(q: query)` con deduplicación por título normalizado y consolidación de `fuentesAgrupadas`.
3. **Despachador Detalle (`detalle_scraper.dart`)**:
   - Mapeo unificado para `CanelaTV`, `Telemundo`, `JKAnime`, `TioAnime`, `AnimeFLV`, `Cinecalidad`, `PelisPlus`, `Cuevana`, `SeriesKao` y `TioPlus`.
4. **Agregador Genérico de Servidores (`main_fuentes_servidores.dart`)**:
   - Integración de los nuevos proveedores de novelas y anime.
   - Fallback genérico para cualquier fuente registrada en `fuentesRegistry` con soporte de búsqueda y detalle.

### 24.2 Nuevos Scrapers de Novelas y Anime (BLOQUE B)
1. **Canela.TV (`canelatv_scraper.dart`)**:
   - Especializado en telenovelas latinas y turcas, dramas y series clásicas.
   - Conexión con endpoints CDN JSON (`search-cdn.cms.api.canela.tv`, `data-store-cdn.cms.api.canela.tv`).
   - Extracción de temporadas, episodios individuales y streaming directo 1080p en español latino.
2. **Telemundo (`telemundo_scraper.dart`)**:
   - Especializado en telenovelas, súper-series y producciones originales.
   - Extracción de listados por género, episodios y enlaces de reproducción oficiales en audio latino.
3. **JKAnime (`jkanime_scraper.dart`)**:
   - Catálogo de anime con filtro por géneros (Shounen, Isekai, Romance, Sobrenatural, etc.).
   - Extracción de episodios a partir de la estructura del sitio y servidores de video (JKPlayer, embeds directos).
4. **TioAnime (`tioanime_scraper.dart`)**:
   - Extracción de series, películas, OVAs y especiales de anime.
   - Parseo de scripts JavaScript (`var episodes`, `var videos`) para servidores como Mega, YourUpload, StreamSB, OkRu, etc.

### 24.3 Expansión de Scrapers Existentes (BLOQUE C)
1. **Cinecalidad (`cinecalidad_scraper.dart` & `cinecalidad_extractor.dart`)**:
   - Extracción multi-calidad: detección exhaustiva de enlaces en 720p, 1080p y 4K (2160p).
   - Detección precisa de idioma por servidor (Latino `es_MX`, Castellano `es_ES`, Subtitulado `en_US`).
   - Soporte para múltiples servidores por título sin restricción artificial.
2. **PelisPlus (`pelisplus_detail_scraper.dart` & `pelisplus_extractor.dart`)**:
   - Extracción completa de todas las temporadas y episodios de series (escaneo global y por contenedores).
   - Extracción de todos los servidores disponibles por episodio (data-url, data-video, options object).
   - Habilitación de servidores subtitulados y castellano junto a latino.
3. **AnimeFLV (`animeflv_scraper.dart` & `animeflv_extractor.dart`)**:
   - Catálogo completo de anime y detección de episodios vía `var episodes` y fallback en DOM HTML.
   - Extracción de todos los servidores SUB y LAT con badges identificativos.

### 24.4 Sistema de Búsqueda Federada (BLOQUE D)
1. **Búsqueda Federada en Paralelo (`search_page.dart` & `tv_search_page.dart`)**:
   - Ejecuta simultáneamente la consulta en TMDB y en todas las fuentes de `fuentesRegistry` (`buscarEnFuentes`).
   - Normalización de títulos (`_normTitle`) para deduplicar resultados entre TMDB y los sitios web.
   - Las fichas de resultados agrupan todas las fuentes disponibles y muestran un distintivo con la cantidad de fuentes.
   - Apertura unificada de la ficha de contenido (`PageContenido`) con resolución automática de ID TMDB.

### 24.5 Rediseño del Selector de Idioma y Priorización de Servidores (BLOQUE D)
1. **Selector de Idioma en Reproductor Móvil (`player_page.dart`)**:
   - Modal de dos niveles: chips/tabs de idiomas disponibles ("Español Latino", "Castellano", "Subtitulado").
   - Al tocar un idioma, se filtran y listan exclusivamente los servidores de ese idioma con calidad indicada.
   - Al seleccionar un servidor, inicia la reproducción inmediatamente en ese servidor específico.
2. **Selector de Idioma en Android TV (`tv_player_page.dart`)**:
   - Interfaz navegable al 100% con control remoto (D-Pad).
   - Lista de idiomas que se expande para mostrar los servidores de esa opción de audio con etiquetas de calidad.
   - Selección de servidor con inicio de streaming inmediato.
3. **Agrupación y Priorización de Servidores (`ServerLoader` & `ServerFallbackService`)**:
   - Método `groupAndPrioritizeServers` y `groupServersByLanguage`.
   - Prioridad 1: Idioma preferido por el usuario (o por la pista seleccionada).
   - Prioridad 2: Mejor servidor disponible en ese idioma (verificado HLS / alta velocidad).

### 24.6 Paridad Obligatoria Móvil ↔ Android TV (BLOQUE D.5)
1. **Catálogo y Filtros en Móvil y TV (`category_list_page.dart` & `tv_discover_page.dart`)**:
   - Barra de filtros de categoría: 'Todos/Todas', 'Películas', 'Series', 'Novelas', 'Anime' con navegación completa D-Pad.
   - En Android TV, navegación fluida entre los 5 pills de cabecera (`Categoría` ↔ `Fuente` ↔ `Tipo` ↔ `Género` ↔ `Buscar`) y la fila 0 del grid de contenido.
   - Carga dinámica y filtrado por categoría mediante `getFuentesByCategory('novel')` y `getFuentesByCategory('anime')`.
2. **Búsqueda Federada en TV (`tv_search_page.dart`)**:
   - Consulta paralela a todas las fuentes del catálogo registradas.
   - Deduplicación de resultados y renderizado en grid con foco visual a distancia de TV.
   - Apertura directa de `TvContentPage` con los servidores agrupados.
3. **Selector de Idioma Agrupado en TV (`tv_player_page.dart`)**:
   - Botón de audífonos que despliega un modal con control D-Pad:
     - Flechas Arriba/Abajo: desplazamiento entre idiomas.
     - OK: expandir o contraer un idioma.
     - Flechas en lista expandida: selección de servidor individual.
     - OK en servidor: cambio inmediato al servidor preservando la posición exacta del video.
     - Back: cierre limpio del modal.

### 24.7 Resiliencia ante Cortes de Conexión (BLOQUE D.6)
1. **Detección Diferenciada de Fallas**:
   - Buffer stall temporal: `buffering == true` y `hasError == false`.
   - Falla fatal: `hasError == true` o error HTTP 403/404.
2. **Temporizador de Tolerancia de 60 Segundos**:
   - Durante 60 segundos de corte o stall, el reproductor no abandona el stream original.
   - Muestra overlay discreto con spinner y cuenta regresiva: *"Reconectando... (X s)"*.
   - Si la red se restablece antes de 60s, el overlay se retira y se notifica con SnackBar: *"Conexión restaurada"*.
3. **Plan de Contingencia Gradual tras Agotarse el Minuto**:
   - 1º Intento: fallback a menor calidad (720p / 480p) vía HLS parser sobre el mismo servidor.
   - 2º Intento: si tras 30s más no responde, salto automático a otro servidor del mismo idioma con SnackBar: *"Cambiando a un servidor más estable..."*.
   - Preservación de posición exacta de reproducción (`seekTo`) antes y después del cambio.
   - Prohibición estricta de pantallas negras o cierres del reproductor.
4. **Configuración Remota en `filmotic_config.json`**:
   - `reconnect_timeout_seconds`: 60
   - `fallback_to_lower_quality_first`: true
   - `show_reconnect_overlay`: true

### 24.8 Pre-validación de Servidores en Background (BLOQUE D.7)
1. **Validación Asíncrona sin Bloquear la UI (`ServerPreValidationService`)**:
   - Al abrir `content_page.dart` (móvil) o `tv_content_page.dart` (TV), se desencadena la pre-validación de todos los servidores en segundo plano.
   - El usuario visualiza la ficha técnica, sinopsis y trailers sin demoras.
2. **Estrategia de Sonda HTTP y Concurrencia**:
   - Intento HEAD con timeout de 5 segundos; fallback automático a GET parcial (`Range: bytes=0-512`).
   - Pool de concurrencia máxima de 5 solicitudes simultáneas para evitar saturación de red.
   - Validación exitosa en códigos HTTP 200–399 o 206 (Partial Content).
3. **Caché Persistente en Sembast (`server_validation_cache`)**:
   - Clave: hash MD5 de la URL del servidor.
   - TTL de 15 minutos configurable. Evita revalidaciones innecesarias en aperturas subsecuentes.
4. **Filtrado Dinámico y Notificación en Tiempo Real**:
   - Servidores caídos o inaccesibles se ocultan automáticamente del modal de selección.
   - Idiomas con todos los servidores caídos no se muestran. Si ningún servidor funciona, mensaje honesto: *"No hay servidores disponibles para este contenido en este momento. Intenta más tarde."*
   - Botón de audífonos muestra un sutil spinner de progreso mientras la validación está activa.
   - Si el modal se abre durante la validación, muestra los ya validados con aviso *"Validando el resto..."* y se refresca automáticamente en tiempo real al finalizar los lotes.
5. **Configuración en `filmotic_config.json`**:
   - `pre_validate_servers_on_content_open`: true
   - `pre_validation_timeout_seconds`: 5
   - `pre_validation_concurrency`: 5
   - `pre_validation_cache_ttl_minutes`: 15
