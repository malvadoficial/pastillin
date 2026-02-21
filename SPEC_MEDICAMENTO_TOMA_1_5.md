# Pastillin 1.5 - Especificación Medicamento vs Toma

Fecha: 2026-02-21

## 1) Regla de dominio

1. `Medicamento` define la plantilla de tratamiento.
2. `Toma` define una ocurrencia concreta en fecha/hora concreta.
3. Las pantallas crean entidades distintas:
- Botiquín: crea/edita `Medicamento`.
- Calendario/Hoy: crea/edita `Toma`.

## 2) Flujo Botiquín (creación de medicamento)

1. Al pulsar `+` se abre creación de medicamento.
2. Nombre por texto o selección de autocomplete/AEMPS.
3. Tipo:
- Pautado
- Uso ocasional
4. Si es pautado:
- Crónico o con fecha de fin
- Pauta: cada X días o cada X meses
- Fecha inicio (por defecto hoy, editable)
5. Si es ocasional: sin pauta recurrente.
6. Al guardar pautado: se generan internamente tomas programadas.

## 3) Vista Botiquín

1. Se mantiene separación visual:
- Pautados
- Uso ocasional
2. Se mantiene info actual por medicamento.

## 4) Flujo Calendario

1. Botón `+` crea una `Toma` para el día seleccionado.
2. La toma se asocia a un medicamento existente del botiquín.
3. Debajo del calendario se listan tomas del día seleccionado.
4. Al editar una toma:
- Se puede cambiar fecha y hora.
- Si la toma pertenece a medicamento pautado y cambia de fecha:
  - Reajustar tomas futuras para respetar pauta desde la nueva fecha.
  - Eliminar tomas antiguas solapadas para evitar duplicados.

## 5) Flujo Hoy

1. Permite crear una `Toma` para hoy.
2. No crea medicamentos nuevos desde Hoy.

## 6) Flujo AEMPS

1. Seleccionar resultado AEMPS permite añadir al botiquín.
2. El alta sigue el mismo procedimiento de creación de medicamento:
- elegir pautado/ocasional
- completar pauta si aplica
- generar tomas si es pautado

## 7) Impacto técnico (implementación propuesta)

1. Mantener `Medication`.
2. Introducir nuevo modelo persistente `Intake` (o `Dose`) para tomas programadas.
3. `IntakeLog` pasa a registrar estado de cumplimiento (tomada/no tomada, hora real) sobre una toma concreta, no sobre "día + medicamento" implícito.
4. Servicio nuevo `IntakeSchedulingService`:
- generar tomas iniciales de pautados
- regenerar tomas futuras al cambiar pauta
- reajustar futuras al mover una toma pautada
- deduplicar tomas
5. Adaptar vistas:
- `CalendarView`: lista/edición de tomas
- `TodayView`: filtra tomas del día
- `MedicationsView` y `EditMedicationView`: solo medicamento y pauta

## 8) Fases de implementación

1. Fase A - Modelo y servicios
- Crear modelo `Intake`
- Crear servicio de planificación y deduplicado
- Migrar datos existentes mínimos

2. Fase B - Botiquín
- Guardado de medicamento genera tomas pautadas
- Ocasional no genera pauta recurrente

3. Fase C - Calendario
- `+` crea toma
- Lista diaria basada en tomas
- Edición de toma + reajuste de futuras

4. Fase D - Hoy
- Lista y creación de tomas de hoy
- Acciones tomada/no tomada sobre toma

5. Fase E - AEMPS + QA
- Alta desde búsqueda AEMPS al flujo unificado de botiquín
- Pruebas de no duplicado y consistencia temporal

## 9) Criterios de aceptación mínimos

1. Crear medicamento pautado produce tomas futuras visibles en Calendario/Hoy.
2. Crear toma desde Calendario y Hoy no crea medicamento.
3. Mover una toma pautada reajusta futuras y no deja duplicados.
4. AEMPS alta medicamento usa flujo unificado.
5. Build Debug y Release sin errores.
