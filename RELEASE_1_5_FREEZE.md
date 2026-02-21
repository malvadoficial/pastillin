# Pastillin 1.5 - Alcance Congelado (Draft)

Fecha de congelación: 2026-02-21  
Rama de trabajo: `codex/pastillin-v1-5`

## Objetivo de la 1.5
Introducir la distinción de dominio entre **Medicamento** y **Toma** (cambio principal de producto), manteniendo estabilidad general en Hoy/Calendario/Botiquín/Ajustes.

## Entra en 1.5 (IN)

1. Cambio principal: separación Medicamento/Toma
- Botiquín crea y edita medicamentos (pautado u ocasional).
- Los medicamentos pautados generan internamente tomas programadas.
- Calendario y Hoy crean/gestionan tomas (no medicamentos).
- El ajuste de fecha/hora de una toma pautada reprograma tomas futuras para mantener la pauta sin duplicados.

2. Estabilidad de recordatorios
- Validar flujo de 1-3 recordatorios diarios.
- Validar acción "Posponer 1h" y apertura a pestaña "Hoy".
- Corregir inconsistencias detectadas en programación/cancelación.

3. Fiabilidad de backup/restore y borrado total
- Exportar copia y compartir sin errores.
- Restaurar copia con confirmación y recarga correcta de estado.
- Borrado total con flujo completo (incluido disclaimer legal posterior).

4. Pulido de UX en pantallas clave
- Hoy: estados vacíos, acciones rápidas, coherencia visual de tomas.
- Pendientes: acceso y conteo coherentes con reglas actuales.
- Carrito/Botiquín: consistencia de orden y mensajes de agotamiento.

5. Calidad de localización (ES/EN)
- Revisar textos visibles de Settings, Hoy, Tutorial y Help.
- Corregir claves/copy inconsistentes o truncadas.

6. Corrección de bugs de release
- Fixes de regresiones en flujos existentes (sin rediseños profundos).

## No entra en 1.5 (OUT)

1. Sincronización en nube/cuentas multi-dispositivo.
2. Nuevas plataformas (watchOS, widgets, macOS nativo).
3. Integración con HealthKit u otras APIs médicas.
4. Reescritura grande de arquitectura o migraciones complejas de modelo.
5. Nuevos módulos funcionales no presentes en navegación actual.

## Criterio de cierre (Definition of Done)

1. Build Debug y Release compilan sin errores en Xcode.
2. Flujo manual validado:
- Alta/edición/baja de medicamento en Botiquín.
- Alta/edición de toma en Calendario y Hoy.
- Marcado tomada/no tomada sobre tomas existentes.
- Pendientes y acceso desde icono/aviso.
- Carrito y cálculo de agotamiento.
- Exportar y restaurar backup.
- Activar/desactivar recordatorios y probar acciones de notificación.
3. Sin crashes en un smoke test de 15-20 minutos.
4. ES/EN revisado en pantallas principales.

## Nota
Este freeze es intencionalmente conservador para cerrar una 1.5 estable.  
Cualquier feature nueva fuera de este documento se mueve a 1.6.
