# Space Master 2025

**Autor:** Jose Tavio  
**Fecha de desarrollo:** 2025-06-06

## Descripción general

**Space Master 2025** es un shoot’em up en 3D desarrollado en Swift utilizando **SceneKit**, **SpriteKit**, **CoreMotion** y **GameKit**. El jugador controla una nave espacial que debe destruir asteroides esquivando colisiones, mientras acumula puntuación e intenta sobrevivir con una barra de vida visible en pantalla.

---

## Características principales

- 🎮 **Estados del juego**: título, introducción, en juego y game over.
- 🚀 **Control de la nave**: mediante giroscopio con `CoreMotion`.
- 💣 **Colisiones** entre disparos, asteroides y nave, con efectos visuales y sonoros.
- 🔊 **Sonido ambiental y de explosiones** con `SCNAudioSource`.
- 🎯 **Contador de impactos y barra de vida dinámica** (verde, naranja, roja).
- 🌌 **Animación de título y pantalla final Game Over** con puntuación.
- 🧨 **Explosiones personalizadas** usando partículas (`Explode.scnp`).
- 🧠 **Game Center**: integración de logros y clasificación en el ranking.
- 📱 **Diseñado para iPhone y iPad**.

---

## Game Center

El juego integra Game Center para:
- Autenticación automática de jugador.
- Publicar puntuación en el ranking `SpaceMaster`.
- Desbloqueo automático de logros:
  - **WorstPlayer**: no destruye ningún asteroide.
  - **FirstHit**: destruye al menos 1 asteroide.
  - **Asteroid20**: destruye al menos 20 asteroides.

---

## Efectos visuales y sonoros

- Partículas `Explode.scnp` al destruir asteroides o sufrir impacto.
- Sonido `bomb.wav` en cada colisión.
- Música de fondo `rolemusic_step_to_space.mp3`, reproducida en bucle.

---

## HUD

El `overlaySKScene` de SpriteKit muestra:
- **Marcador** de impactos (HITS).
- **Barra de vida** dinámica a la izquierda (verde >60%, naranja >30%, roja <30%).

---

## Controles

- **Inicio**: toca en pantalla en el título.
- **Disparo**: tap en cualquier momento durante la partida.
- **Movimiento**: giroscopio (inclina el dispositivo).

---

## Archivos necesarios

- `ship.scn`: escena principal con la nave.
- `rock.scn`: asteroide base.
- `Explode.scnp`: sistema de partículas para impactos.
- `bomb.wav`: sonido de explosión.
- `rolemusic_step_to_space.mp3`: música de fondo.
- Fuente `University.ttf` para los textos 3D.

---

## Dificultades superadas

- Correcta integración de `CoreMotion` para controlar la nave sin colisiones abruptas.
- Creación de geometría 3D animada y alineada visualmente con `SceneKit`.
- Sincronización entre `SCNAction`, `SCNAudioSource` y `SCNParticleSystem`.
- Gestión de múltiples estados de juego sin interferencias.
- Inclusión de Game Center con logros progresivos y feedback visual.

---

## Compilación

El proyecto se desarrolla en **Xcode 15+**, compatible con iOS 16+.  
Requiere habilitar Game Center en capabilities y registrar los IDs de logros y clasificaciones.

---

## Capturas

🧪 (Aquí puedes añadir capturas del gameplay, HUD y efectos visuales)
