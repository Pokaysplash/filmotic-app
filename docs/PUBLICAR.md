# 📦 Guía de Publicación de APK y Releases en GitHub

Esta guía detalla el procedimiento exacto para compilar, empaquetar y publicar nuevas versiones de **Filmotic** en GitHub Releases, asegurando que la landing page y el sistema de actualización automática en la app funcionen de forma ininterrumpida.

---

## 1. Actualizar la Versión en el Código

Antes de generar el binario para una nueva versión:

1. Abre `pubspec.yaml` y localiza el campo `version`:
   ```yaml
   # Para versión inicial:
   version: 1.0.0+1

   # Para la siguiente actualización:
   version: 1.0.1+2
   ```
   - El número antes del `+` (`1.0.1`) es el nombre semántico que ven los usuarios y el Remote Config.
   - El número después del `+` (`2`) es el `buildNumber` que Android utiliza internamente para permitir actualizar sobre una app ya instalada.

2. En `lib/main.dart`, verifica o actualiza la constante `currentVersion`:
   ```dart
   const currentVersion = '1.0.0'; // (o '1.0.1')
   ```

---

## 2. Compilar el APK Release

Ejecuta en la raíz de tu proyecto local:

```bash
flutter clean
flutter pub get
flutter build apk --release
```

El APK compilado y optimizado se generará en la ruta:
```text
build/app/outputs/flutter-apk/app-release.apk
```

---

## 3. Crear el Release en GitHub

1. Ingresa a tu repositorio en GitHub:  
   `https://github.com/Pokaysplash/filmotic-app`
2. En la barra lateral derecha, haz clic en **Releases** y luego en **Draft a new release** (o "Create a new release").
3. Configura los campos del release:
   - **Choose a tag**: Escribe la etiqueta, por ejemplo `v1.0.0` (o `v1.0.1`) y haz clic en *Create new tag: v1.0.0 on publish*.
   - **Target**: Rama `main`.
   - **Release title**: `Filmotic v1.0.0` (o el número de versión).
   - **Describe this release**: Escribe un breve resumen de novedades, correcciones o nuevos servidores añadidos.
4. **Subir y Renombrar el APK (¡MUY IMPORTANTE!)**:
   - Arrastra el archivo generado `build/app/outputs/flutter-apk/app-release.apk` a la zona de archivos adjuntos (*Attach binaries by dropping them here*).
   - **Renombra el archivo a `filmotic.apk`** en la interfaz de GitHub antes o después de subirlo.
   > ⚠️ **¿Por qué `filmotic.apk`?**  
   > Porque el botón de descarga directa de la Landing Page y el diálogo de actualización dentro de la app apuntan de forma permanente a la URL fija:  
   > `https://github.com/Pokaysplash/filmotic-app/releases/latest/download/filmotic.apk`  
   > Si el archivo no se llama exactamente `filmotic.apk`, la descarga dará un error 404.
5. Haz clic en **Publish release**.

---

## 4. Notificar Actualizaciones Remotamente (`filmotic_config.json`)

Una vez publicado el release en GitHub:

1. Abre el archivo `filmotic_config.json` en la raíz del repositorio.
2. Modifica la sección `"app"`:
   ```json
   "app": {
     "min_version": "1.0.0",
     "latest_version": "1.0.1",
     "update_url": "https://github.com/Pokaysplash/filmotic-app/releases/latest/download/filmotic.apk",
     "update_message": "¡Filmotic v1.0.1 ya está disponible! Incluye nuevos servidores y mejoras en la reproducción.",
     "force_update": false
   }
   ```
   - **Actualización Suave (Opcional)**: Cambia `"latest_version": "1.0.1"`. Los usuarios verán un diálogo informativo para actualizar con botones *"Actualizar"* y *"Más tarde"*. Si pulsan *"Más tarde"*, no se les volverá a molestar con esa versión.
   - **Actualización Obligatoria (Crítica / Bloqueante)**: Cambia `"min_version": "1.0.1"` o `"force_update": true`. Cualquier app instalada con versión menor no podrá avanzar hasta que el usuario descargue e instale la nueva versión.
3. Haz `git commit` y `git push origin main`. En cuanto GitHub Raw sirva el nuevo JSON, los clientes detectarán el cambio automáticamente.
