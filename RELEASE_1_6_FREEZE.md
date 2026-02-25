# Pastillin 1.6 - Alcance Congelado (Draft)

Fecha de congelación: 2026-02-23  
Rama de trabajo: `codex/pastillin-v1-6`

## Objetivo de la 1.6
Aplicar correcciones y mejoras de UX/estabilidad sobre la base de 1.5, manteniendo el producto consistente en Hoy/Calendario/Botiquín/Ajustes.

## Entra en 1.6 (IN)

1. Correcciones funcionales reportadas por usuario
- Ajustes de visualización, navegación y comportamiento en Hoy/Calendario/Botiquín.
- Correcciones de listas, estados vacíos y filtros.
- Corrección de textos y localización visible en interfaz.

2. Rendimiento y fluidez
- Reducir operaciones costosas en vistas con listas y refrescos frecuentes.
- Mejorar respuesta al marcar tomas y al cambiar estado.

3. Estabilidad de ejecución
- Validar arranque y ejecución en iOS Simulator y dispositivos.
- Corregir problemas de firma/configuración de build que bloqueen el lanzamiento.

4. Documentación y release
- Mantener README y notas de versión alineadas.
- Publicar release con artefacto DMG actualizado.

## No entra en 1.6 (OUT)

1. Nuevos módulos funcionales fuera del flujo actual.
2. Integraciones externas adicionales no existentes.
3. Migraciones grandes de arquitectura/modelo sin necesidad de bugfix.
4. Replanteamiento completo de diseño visual de la app.

## Criterio de cierre (Definition of Done)

1. Build Debug y Release compilan sin errores.
2. Flujos críticos validados manualmente:
- Alta/edición/baja de medicamentos.
- Alta/edición de tomas desde Hoy y Calendario.
- Marcado tomada/no tomada.
- Pendientes y accesos desde iconos.
- Carrito y estados de agotamiento.
3. Sin crashes en smoke test de 15-20 minutos.
4. Localización ES/EN sin claves técnicas visibles en UI.
5. Release publicada con notas y DMG.

