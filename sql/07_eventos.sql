-- =====================================================================
-- MediCita IPS · 07_eventos.sql
-- Fase 5 · 5 eventos (de menor a mayor dificultad) con sus pruebas
--
-- Para probarlos sin esperar, cada evento arranca 2 segundos después de
-- crearse (STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND) y se espera con
-- SELECT SLEEP(4). Dentro de cada evento se usa la fecha de corte
-- 2026-11-30 y no CURDATE(), para que el resultado no dependa del día en
-- que se ejecute el script. Al final se apagan los eventos.
-- =====================================================================

USE medicita_ips;

SET GLOBAL event_scheduler = ON;
SHOW VARIABLES LIKE 'event_scheduler';

-- ---------------------------------------------------------------------
-- E-1 · evt_marcar_inasistencias_diario
-- Citas PROGRAMADA o CONFIRMADA que empezaron antes del corte -> NO_ASISTIO.
-- El historial lo escribe el trigger T-3 con el usuario "sistema".
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_marcar_inasistencias_diario;
DELIMITER $$
CREATE EVENT evt_marcar_inasistencias_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
ON COMPLETION PRESERVE
DO
BEGIN
    DECLARE v_corte DATE DEFAULT '2026-11-30';
    DECLARE v_sistema BIGINT;

    SET v_sistema = (SELECT id FROM staff WHERE username = 'sistema');

    UPDATE appointments
    SET status = 'NO_ASISTIO',
        updated_by = v_sistema,
        status_changed_at = TIMESTAMP(v_corte, '23:59:00')
    WHERE status IN ('PROGRAMADA', 'CONFIRMADA')
      AND start_at < v_corte + INTERVAL 1 DAY;
END$$
DELIMITER ;

-- Antes: citas del corte que siguen sin atender.
SELECT id, start_at, status FROM appointments
WHERE status IN ('PROGRAMADA', 'CONFIRMADA') AND start_at < '2026-12-01'
ORDER BY start_at;
SELECT SLEEP(4);
-- Después: ya no quedan, y el historial muestra el cambio hecho por "sistema".
SELECT COUNT(*) AS pendientes_antes_del_corte FROM appointments
WHERE status IN ('PROGRAMADA', 'CONFIRMADA') AND start_at < '2026-12-01';
SELECT h.appointment_id, h.previous_status, h.new_status, h.changed_at, s.username AS responsable
FROM appointment_status_history h
JOIN staff s ON s.id = h.changed_by
WHERE h.new_status = 'NO_ASISTIO' AND h.changed_at = '2026-11-30 23:59:00'
ORDER BY h.appointment_id;

-- ---------------------------------------------------------------------
-- E-2 · evt_generar_recordatorios_diario
-- Un recordatorio PENDIENTE para cada cita del día siguiente al corte que
-- aún no tenga ninguno. Canal: CORREO si el paciente tiene correo, si no SMS.
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generar_recordatorios_diario;
DELIMITER $$
CREATE EVENT evt_generar_recordatorios_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
ON COMPLETION PRESERVE
DO
BEGIN
    DECLARE v_corte DATE DEFAULT '2026-11-30';

    INSERT INTO reminders (appointment_id, channel, scheduled_for, status)
    SELECT a.id,
           CASE WHEN p.email IS NULL THEN 'SMS' ELSE 'CORREO' END,
           TIMESTAMP(v_corte, '08:00:00'),
           'PENDIENTE'
    FROM appointments a
    JOIN patients p ON p.id = a.patient_id
    WHERE a.start_at >= v_corte + INTERVAL 1 DAY
      AND a.start_at <  v_corte + INTERVAL 2 DAY
      AND a.status IN ('PROGRAMADA', 'CONFIRMADA')
      AND NOT EXISTS (SELECT 1 FROM reminders r WHERE r.appointment_id = a.id);
END$$
DELIMITER ;

-- Antes: citas del 1 de diciembre sin recordatorio.
SELECT a.id, a.start_at, a.status
FROM appointments a
WHERE a.start_at >= '2026-12-01' AND a.start_at < '2026-12-02'
  AND a.status IN ('PROGRAMADA', 'CONFIRMADA')
  AND NOT EXISTS (SELECT 1 FROM reminders r WHERE r.appointment_id = a.id);
SELECT SLEEP(4);
-- Después: todas tienen recordatorio.
SELECT r.appointment_id, r.channel, r.scheduled_for, r.status
FROM reminders r
JOIN appointments a ON a.id = r.appointment_id
WHERE a.start_at >= '2026-12-01' AND a.start_at < '2026-12-02'
ORDER BY r.appointment_id;

-- ---------------------------------------------------------------------
-- E-3 · evt_vencer_afiliaciones_diario
-- Inactiva las afiliaciones cuya fecha de fin ya pasó al corte.
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_vencer_afiliaciones_diario;
DELIMITER $$
CREATE EVENT evt_vencer_afiliaciones_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
ON COMPLETION PRESERVE
DO
BEGIN
    DECLARE v_corte DATE DEFAULT '2026-11-30';

    UPDATE affiliations
    SET is_active = FALSE
    WHERE is_active = TRUE
      AND end_date IS NOT NULL
      AND end_date < v_corte;
END$$
DELIMITER ;

-- Antes: la afiliación de Diego Pinzón (20) terminó el 2026-11-15 y sigue activa.
SELECT id, patient_id, end_date, is_active FROM affiliations WHERE end_date < '2026-11-30';
SELECT SLEEP(4);
-- Después: inactiva.
SELECT id, patient_id, end_date, is_active FROM affiliations WHERE end_date < '2026-11-30';

-- ---------------------------------------------------------------------
-- E-4 · evt_marcar_facturas_vencidas_diario
-- PENDIENTE o PARCIAL emitidas hace más de 30 días al corte -> VENCIDA.
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_marcar_facturas_vencidas_diario;
DELIMITER $$
CREATE EVENT evt_marcar_facturas_vencidas_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
ON COMPLETION PRESERVE
DO
BEGIN
    DECLARE v_corte DATE DEFAULT '2026-11-30';

    UPDATE invoices
    SET status = 'VENCIDA'
    WHERE status IN ('PENDIENTE', 'PARCIAL')
      AND DATEDIFF(v_corte, issued_at) > 30;
END$$
DELIMITER ;

-- Antes
SELECT status, COUNT(*) AS facturas FROM invoices GROUP BY status ORDER BY status;
SELECT SLEEP(4);
-- Después: aparecen las VENCIDA; las emitidas en los últimos 30 días siguen igual.
SELECT status, COUNT(*) AS facturas FROM invoices GROUP BY status ORDER BY status;
SELECT invoice_number, issued_at, DATEDIFF('2026-11-30', issued_at) AS dias, status, fn_saldo_factura(id) AS saldo
FROM invoices
WHERE status = 'VENCIDA'
ORDER BY issued_at
LIMIT 10;

-- ---------------------------------------------------------------------
-- E-5 · evt_resumen_produccion_mensual
-- El primer día de cada mes guarda, por médico, las atenciones y el valor
-- facturado (sin anuladas) del mes anterior. La "fecha de ejecución" es
-- el día siguiente al corte (2026-12-01), así que resume NOVIEMBRE.
-- Es idempotente: borra el resumen del periodo antes de volver a generarlo.
-- En producción se programaría: EVERY 1 MONTH STARTS '2027-01-01 00:05:00'.
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_resumen_produccion_mensual;
DELIMITER $$
CREATE EVENT evt_resumen_produccion_mensual
ON SCHEDULE EVERY 1 MONTH STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
ON COMPLETION PRESERVE
DO
BEGIN
    DECLARE v_corte DATE DEFAULT '2026-11-30';
    DECLARE v_ejecucion DATE;
    DECLARE v_desde DATE;
    DECLARE v_hasta DATE;

    SET v_ejecucion = v_corte + INTERVAL 1 DAY;                                  -- 2026-12-01
    SET v_desde = DATE_FORMAT(v_ejecucion - INTERVAL 1 MONTH, '%Y-%m-01');       -- 2026-11-01
    SET v_hasta = LAST_DAY(v_desde);                                             -- 2026-11-30

    DELETE FROM production_summaries
    WHERE period_year = YEAR(v_desde) AND period_month = MONTH(v_desde);

    INSERT INTO production_summaries (doctor_id, period_year, period_month, encounters_count,
                                      billed_amount, generated_at)
    SELECT d.id,
           YEAR(v_desde),
           MONTH(v_desde),
           (SELECT COUNT(*)
              FROM encounters e
              JOIN appointments a ON a.id = e.appointment_id
             WHERE a.doctor_id = d.id
               AND DATE(e.started_at) BETWEEN v_desde AND v_hasta),
           (SELECT COALESCE(SUM(i.total_amount), 0)
              FROM invoices i
              JOIN encounters e   ON e.id = i.encounter_id
              JOIN appointments a ON a.id = e.appointment_id
             WHERE a.doctor_id = d.id
               AND i.status <> 'ANULADA'
               AND DATE(e.started_at) BETWEEN v_desde AND v_hasta),
           TIMESTAMP(v_ejecucion, '00:05:00')
    FROM doctors d
    WHERE EXISTS (SELECT 1
                    FROM encounters e
                    JOIN appointments a ON a.id = e.appointment_id
                   WHERE a.doctor_id = d.id
                     AND DATE(e.started_at) BETWEEN v_desde AND v_hasta);
END$$
DELIMITER ;

-- Antes: solo hay resúmenes de septiembre y octubre.
SELECT period_year, period_month, COUNT(*) AS medicos FROM production_summaries
GROUP BY period_year, period_month ORDER BY period_year, period_month;
SELECT SLEEP(4);
-- Después: aparece noviembre de 2026.
SELECT CONCAT(d.first_name, ' ', d.last_name) AS medico, ps.encounters_count AS atenciones,
       ps.billed_amount AS valor_facturado, ps.generated_at
FROM production_summaries ps
JOIN doctors d ON d.id = ps.doctor_id
WHERE ps.period_year = 2026 AND ps.period_month = 11
ORDER BY ps.billed_amount DESC;

-- ---------------------------------------------------------------------
-- Estado de los eventos y apagado de los eventos de prueba
-- ---------------------------------------------------------------------
SELECT event_name, status, interval_value, interval_field, last_executed
FROM information_schema.events
WHERE event_schema = 'medicita_ips'
ORDER BY event_name;

ALTER EVENT evt_marcar_inasistencias_diario     DISABLE;
ALTER EVENT evt_generar_recordatorios_diario    DISABLE;
ALTER EVENT evt_vencer_afiliaciones_diario      DISABLE;
ALTER EVENT evt_marcar_facturas_vencidas_diario DISABLE;
ALTER EVENT evt_resumen_produccion_mensual      DISABLE;

SELECT event_name, status
FROM information_schema.events
WHERE event_schema = 'medicita_ips'
ORDER BY event_name;
