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

### Preparación de Publicidad (Sin Google AdMob)
> **POLÍTICA ESTRICTA**: No se utiliza Google AdMob debido a que las políticas de Google prohíben contenido con derechos de autor y suspenden cuentas de inmediato.

El sistema se preparó mediante el servicio modular **`AdService`** (`lib/core/services/ad_service.dart`) optimizado para redes de streaming compatibles:
1. **Adsterra (Banners Discretos)**:
   - Formato estándar de banner 320x50 ubicado exclusivamente en la parte inferior del catálogo y al final de la ficha de contenido.
   - Espacio pre-reservado con contenedor elegante que no rompe el diseño ni genera *Cumulative Layout Shift* (CLS).
   - Prohibido terminantemente mostrar banners flotantes sobre el reproductor o tapando los controles.
2. **HilltopAds (Video VAST Pre-roll)**:
   - Soporte para anuncios VAST antes de iniciar la reproducción de video.
   - Limitado con control de frecuencia (máximo una vez cada 15 minutos) para evitar saturación y garantizar una excelente experiencia de usuario.
   - Prohibidos terminantemente popunders, banners intrusivos durante la película y redirecciones al hacer clic en controles de video.

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

