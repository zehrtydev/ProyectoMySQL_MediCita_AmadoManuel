-- =====================================================================
-- MediCita IPS · 06_triggers.sql
-- Fase 5 · 5 triggers del enunciado (de menor a mayor dificultad) y
-- 4 triggers adicionales para reglas que comparan varias filas.
-- Los nombres coinciden con mis tablas: no fue necesario ajustarlos.
--
-- Error 1442: un trigger no puede modificar la tabla que lo disparó.
--   · T-3 se dispara en appointments y solo escribe en appointment_status_history.
--   · T-4 se dispara en payments y solo actualiza invoices.
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- T-1 · trg_vital_signs_before_insert
-- Mensajes claros para signos vitales imposibles. Los CHECK del DDL
-- también los rechazan, pero con un mensaje genérico (3819). Como el
-- BEFORE INSERT corre antes que los CHECK, el usuario ve este mensaje.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_vital_signs_before_insert;
DELIMITER $$
CREATE TRIGGER trg_vital_signs_before_insert
BEFORE INSERT ON vital_signs
FOR EACH ROW
BEGIN
    DECLARE v_mensaje VARCHAR(255);

    IF NEW.systolic_bp NOT BETWEEN 60 AND 260 THEN
        SET v_mensaje = CONCAT('Presión sistólica imposible: ', NEW.systolic_bp, ' (rango permitido 60–260 mmHg).');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF NEW.diastolic_bp NOT BETWEEN 30 AND 160 THEN
        SET v_mensaje = CONCAT('Presión diastólica imposible: ', NEW.diastolic_bp, ' (rango permitido 30–160 mmHg).');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF NEW.diastolic_bp >= NEW.systolic_bp THEN
        SET v_mensaje = CONCAT('La diastólica (', NEW.diastolic_bp, ') debe ser menor que la sistólica (', NEW.systolic_bp, ').');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF NEW.temperature_c IS NOT NULL AND NEW.temperature_c NOT BETWEEN 30 AND 45 THEN
        SET v_mensaje = CONCAT('Temperatura imposible: ', NEW.temperature_c, ' °C (rango permitido 30–45 °C).');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF NEW.heart_rate IS NOT NULL AND NEW.heart_rate NOT BETWEEN 20 AND 250 THEN
        SET v_mensaje = CONCAT('Frecuencia cardíaca imposible: ', NEW.heart_rate, ' lpm (rango permitido 20–250).');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
END$$
DELIMITER ;

-- Prueba que funciona: nueva toma de presión de Hernando Prada (atención 116).
INSERT INTO vital_signs (encounter_id, taken_at, systolic_bp, diastolic_bp, heart_rate, temperature_c, weight_kg, height_cm)
VALUES (116, '2026-11-30 07:30:00', 150, 92, 78, 36.6, 95.70, 185.0);
SELECT * FROM vital_signs WHERE encounter_id = 116 ORDER BY taken_at;
-- ⚠️ ESPERADO: ERROR 1644 La diastólica (130) debe ser menor que la sistólica (120).
INSERT INTO vital_signs (encounter_id, taken_at, systolic_bp, diastolic_bp, heart_rate, temperature_c)
VALUES (116, '2026-11-30 07:35:00', 120, 130, 78, 36.6);
-- ⚠️ ESPERADO: ERROR 1644 Temperatura imposible: 5.0 °C (rango permitido 30–45 °C).
INSERT INTO vital_signs (encounter_id, taken_at, systolic_bp, diastolic_bp, heart_rate, temperature_c)
VALUES (116, '2026-11-30 07:35:00', 120, 80, 78, 5.0);

-- ---------------------------------------------------------------------
-- T-2 · trg_invoices_before_delete
-- Las facturas nunca se borran (DIAN y auditoría): se anulan.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_invoices_before_delete;
DELIMITER $$
CREATE TRIGGER trg_invoices_before_delete
BEFORE DELETE ON invoices
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las facturas no se borran: anúlela.';
END$$
DELIMITER ;

-- ⚠️ ESPERADO: ERROR 1644 Las facturas no se borran: anúlela.
DELETE FROM invoices WHERE id = 29;
-- Prueba de que sigue ahí:
SELECT id, invoice_number, status FROM invoices WHERE id = 29;

-- ---------------------------------------------------------------------
-- T-3 · trg_appointments_after_update
-- Cuando cambia el estado, registra en el historial el estado anterior,
-- el nuevo, la fecha y el responsable. Quien hace el UPDATE informa el
-- responsable (updated_by) y la fecha (status_changed_at). Si la fecha
-- no se actualizó en este UPDATE, se usa NOW() para no repetir una vieja.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_appointments_after_update;
DELIMITER $$
CREATE TRIGGER trg_appointments_after_update
AFTER UPDATE ON appointments
FOR EACH ROW
BEGIN
    DECLARE v_fecha DATETIME;
    DECLARE v_responsable BIGINT;

    IF NOT (OLD.status <=> NEW.status) THEN
        IF NEW.status_changed_at IS NULL OR NEW.status_changed_at <=> OLD.status_changed_at THEN
            SET v_fecha = NOW();
        ELSE
            SET v_fecha = NEW.status_changed_at;
        END IF;

        SET v_responsable = COALESCE(NEW.updated_by,
                                     (SELECT id FROM staff WHERE username = 'sistema'));

        INSERT INTO appointment_status_history
            (appointment_id, previous_status, new_status, cancellation_reason_id, changed_at, changed_by)
        VALUES
            (NEW.id, OLD.status, NEW.status,
             CASE WHEN NEW.status = 'CANCELADA' THEN NEW.cancellation_reason_id END,
             v_fecha, v_responsable);
    END IF;
END$$
DELIMITER ;

-- Prueba que funciona 1: la cancelación de la cita 183 (la de 05, ahora sí con historial).
CALL sp_cancelar_cita(183, 'Viaje', 2, '2026-11-30 10:00:00');
-- Prueba que funciona 2: recepción confirma por teléfono la cita 185.
UPDATE appointments
SET status = 'CONFIRMADA', updated_by = 3, status_changed_at = '2026-11-30 09:15:00'
WHERE id = 185;
-- Un UPDATE que no cambia el estado NO deja historial:
UPDATE appointments SET office_id = office_id WHERE id = 185;
SELECT h.appointment_id, h.previous_status, h.new_status, r.name AS motivo, h.changed_at, s.full_name AS responsable
FROM appointment_status_history h
LEFT JOIN cancellation_reasons r ON r.id = h.cancellation_reason_id
JOIN staff s ON s.id = h.changed_by
WHERE h.appointment_id IN (183, 185)
ORDER BY h.appointment_id, h.changed_at;

-- ---------------------------------------------------------------------
-- T-4 · trg_payments_after_insert
-- Después de cada abono recalcula el estado de la factura:
-- PAGADA si el saldo llega a 0; PARCIAL si queda saldo. Una factura
-- VENCIDA con saldo sigue VENCIDA (el abono no la pone al día).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_payments_after_insert;
DELIMITER $$
CREATE TRIGGER trg_payments_after_insert
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_estado VARCHAR(20);
    DECLARE v_abonado DECIMAL(12,2);

    SET v_total  = (SELECT total_amount FROM invoices WHERE id = NEW.invoice_id);
    SET v_estado = (SELECT status FROM invoices WHERE id = NEW.invoice_id);
    SET v_abonado = (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE invoice_id = NEW.invoice_id);

    IF v_abonado >= v_total THEN
        UPDATE invoices SET status = 'PAGADA' WHERE id = NEW.invoice_id;
    ELSEIF v_estado IN ('PENDIENTE', 'PARCIAL') THEN
        UPDATE invoices SET status = 'PARCIAL' WHERE id = NEW.invoice_id;
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- Adicional · trg_payments_before_insert
-- Complemento de T-4: no se abona a una factura anulada ni por encima del saldo.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_payments_before_insert;
DELIMITER $$
CREATE TRIGGER trg_payments_before_insert
BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    DECLARE v_mensaje VARCHAR(255);
    DECLARE v_saldo DECIMAL(12,2);

    IF (SELECT status FROM invoices WHERE id = NEW.invoice_id) = 'ANULADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pueden registrar abonos a una factura ANULADA.';
    END IF;

    SET v_saldo = fn_saldo_factura(NEW.invoice_id);
    IF NEW.amount > v_saldo THEN
        SET v_mensaje = CONCAT('El abono (', NEW.amount, ') supera el saldo de la factura (', v_saldo, ').');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
END$$
DELIMITER ;

-- Prueba que funciona: factura 29 (PENDIENTE, total 47.000: paciente 9.400 y prepagada 37.600).
SELECT id, invoice_number, status, total_amount, fn_saldo_factura(id) AS saldo FROM invoices WHERE id = 29;
-- 1) el paciente paga su copago -> PARCIAL
INSERT INTO payments (invoice_id, payment_method_id, payer, amount, paid_at)
VALUES (29, 1, 'PACIENTE', 9400.00, '2026-11-30 10:30:00');
SELECT id, status, fn_saldo_factura(id) AS saldo FROM invoices WHERE id = 29;
-- 2) la aseguradora paga el resto -> PAGADA
INSERT INTO payments (invoice_id, payment_method_id, payer, amount, paid_at, reference)
VALUES (29, 4, 'ASEGURADORA', 37600.00, '2026-11-30 11:00:00', 'TR-778899');
SELECT id, status, fn_saldo_factura(id) AS saldo FROM invoices WHERE id = 29;
-- ⚠️ ESPERADO: ERROR 1644 No se pueden registrar abonos a una factura ANULADA.
INSERT INTO payments (invoice_id, payment_method_id, payer, amount, paid_at)
VALUES (44, 1, 'PACIENTE', 1000.00, '2026-11-30 11:30:00');
-- ⚠️ ESPERADO: ERROR 1644 El abono (100000.00) supera el saldo de la factura (75100.00).
INSERT INTO payments (invoice_id, payment_method_id, payer, amount, paid_at)
VALUES (116, 1, 'PACIENTE', 100000.00, '2026-11-30 11:30:00');

-- ---------------------------------------------------------------------
-- T-5 · trg_prescription_items_before_insert
-- Rechaza formular un medicamento cuyo principio activo está entre las
-- alergias del paciente de esa fórmula (fórmula -> atención -> cita -> paciente).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prescription_items_before_insert;
DELIMITER $$
CREATE TRIGGER trg_prescription_items_before_insert
BEFORE INSERT ON prescription_items
FOR EACH ROW
BEGIN
    DECLARE v_paciente BIGINT;
    DECLARE v_principio VARCHAR(100);
    DECLARE v_medicamento VARCHAR(100);
    DECLARE v_mensaje VARCHAR(255);

    SET v_paciente = (SELECT a.patient_id
                      FROM prescriptions rx
                      JOIN encounters e   ON e.id = rx.encounter_id
                      JOIN appointments a ON a.id = e.appointment_id
                      WHERE rx.id = NEW.prescription_id);

    SET v_principio = (SELECT ai.name
                       FROM medications m
                       JOIN active_ingredients ai ON ai.id = m.active_ingredient_id
                       JOIN patient_allergies pa  ON pa.active_ingredient_id = m.active_ingredient_id
                       WHERE m.id = NEW.medication_id
                         AND pa.patient_id = v_paciente);

    IF v_principio IS NOT NULL THEN
        SET v_medicamento = (SELECT name FROM medications WHERE id = NEW.medication_id);
        SET v_mensaje = CONCAT('No se puede formular ', v_medicamento, ': el paciente es alérgico a su principio activo (',
                               v_principio, ').');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
END$$
DELIMITER ;

-- María Fernanda Peña (paciente 3) es alérgica al IBUPROFENO. Nueva fórmula en su atención 104.
INSERT INTO prescriptions (encounter_id, issued_at, notes)
VALUES (104, '2026-11-18 11:40:00', 'Manejo del dolor');
SET @formula = LAST_INSERT_ID();
-- ⚠️ ESPERADO: ERROR 1644 No se puede formular Advil: el paciente es alérgico a su principio activo (Ibuprofeno).
-- (Advil es una marca: la alergia se detecta por el principio activo, no por el nombre.)
INSERT INTO prescription_items (prescription_id, medication_id, dose, frequency_hours, duration_days)
VALUES (@formula, 2, '1 tableta', 8, 5);
-- Prueba que funciona: acetaminofén (Dolex) sí se le puede formular.
INSERT INTO prescription_items (prescription_id, medication_id, dose, frequency_hours, duration_days)
VALUES (@formula, 4, '1 tableta', 8, 5);
SELECT pi.prescription_id, m.name, ai.name AS principio_activo, pi.dose
FROM prescription_items pi
JOIN medications m ON m.id = pi.medication_id
JOIN active_ingredients ai ON ai.id = m.active_ingredient_id
WHERE pi.prescription_id = @formula;

-- ---------------------------------------------------------------------
-- Adicional · trg_affiliations_before_insert
-- Una sola afiliación vigente: no se aceptan vigencias que se crucen.
-- Tampoco se afilia a PARTICULAR: particular es la AUSENCIA de afiliación.
-- Dos vigencias se cruzan si inicio1 <= fin2 y inicio2 <= fin1 (fin NULL = abierta).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_affiliations_before_insert;
DELIMITER $$
CREATE TRIGGER trg_affiliations_before_insert
BEFORE INSERT ON affiliations
FOR EACH ROW
BEGIN
    IF NEW.plan_id = (SELECT id FROM plans WHERE name = 'PARTICULAR') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PARTICULAR no es una afiliación: el paciente sin afiliación vigente se atiende como particular.';
    END IF;
    IF EXISTS (SELECT 1 FROM affiliations af
               WHERE af.patient_id = NEW.patient_id
                 AND NEW.start_date <= COALESCE(af.end_date, '9999-12-31')
                 AND af.start_date <= COALESCE(NEW.end_date, '9999-12-31')) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La vigencia se cruza con otra afiliación del paciente: solo puede haber una vigente.';
    END IF;
END$$
DELIMITER ;

-- ⚠️ ESPERADO: ERROR 1644 La vigencia se cruza con otra afiliación del paciente: solo puede haber una vigente.
-- (el paciente 10 tiene Nueva EPS vigente desde 2026-09-01)
INSERT INTO affiliations (patient_id, insurer_id, plan_id, start_date, is_active)
VALUES (10, 2, 1, '2026-11-01', FALSE);
-- ⚠️ ESPERADO: ERROR 1644 PARTICULAR no es una afiliación: el paciente sin afiliación vigente se atiende como particular.
INSERT INTO affiliations (patient_id, insurer_id, plan_id, start_date)
VALUES (6, 1, 4, '2026-12-01');
-- Prueba que funciona: Luis Alberto Briceño (6, particular) se afilia a Sura EPS desde diciembre.
INSERT INTO affiliations (patient_id, insurer_id, plan_id, start_date)
VALUES (6, 3, 1, '2026-12-01');
SELECT * FROM affiliations WHERE patient_id = 6;

-- ---------------------------------------------------------------------
-- Adicional · trg_tariffs_before_insert
-- Las vigencias de un mismo servicio y plan no se cruzan; si no, la
-- "tarifa del día" sería ambigua.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_tariffs_before_insert;
DELIMITER $$
CREATE TRIGGER trg_tariffs_before_insert
BEFORE INSERT ON tariffs
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM tariffs t
               WHERE t.service_id = NEW.service_id
                 AND t.plan_id = NEW.plan_id
                 AND NEW.valid_from <= COALESCE(t.valid_to, '9999-12-31')
                 AND t.valid_from <= COALESCE(NEW.valid_to, '9999-12-31')) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La vigencia se cruza con otra tarifa del mismo servicio y plan.';
    END IF;
END$$
DELIMITER ;

-- ⚠️ ESPERADO: ERROR 1644 La vigencia se cruza con otra tarifa del mismo servicio y plan.
INSERT INTO tariffs (service_id, plan_id, price, valid_from) VALUES (1, 4, 70000.00, '2026-11-01');
-- Prueba que funciona: la nebulización (11) recibe su primera tarifa PARTICULAR desde diciembre.
INSERT INTO tariffs (service_id, plan_id, price, valid_from) VALUES (11, 4, 30000.00, '2026-12-01');
SELECT * FROM tariffs WHERE service_id = 11;

-- ---------------------------------------------------------------------
-- Adicional · trg_satisfaction_surveys_before_insert
-- Solo se encuesta a citas ATENDIDA (la unicidad por cita es UNIQUE).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_satisfaction_surveys_before_insert;
DELIMITER $$
CREATE TRIGGER trg_satisfaction_surveys_before_insert
BEFORE INSERT ON satisfaction_surveys
FOR EACH ROW
BEGIN
    IF (SELECT status FROM appointments WHERE id = NEW.appointment_id) <> 'ATENDIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se encuestan citas ATENDIDAS.';
    END IF;
END$$
DELIMITER ;

-- ⚠️ ESPERADO: ERROR 1644 Solo se encuestan citas ATENDIDAS.
-- (la cita 17 quedó NO_ASISTIO)
INSERT INTO satisfaction_surveys (appointment_id, score, answered_at) VALUES (17, 5, '2026-11-30 12:00:00');
-- Prueba que funciona: la cita 149 (ATENDIDA el 30 de noviembre).
INSERT INTO satisfaction_surveys (appointment_id, score, comment, answered_at)
VALUES (149, 4, 'Buena atención, algo de espera.', '2026-11-30 12:00:00');
-- ⚠️ ESPERADO: ERROR 1062 Duplicate entry '149' for key 'satisfaction_surveys.appointment_id'
INSERT INTO satisfaction_surveys (appointment_id, score, answered_at) VALUES (149, 5, '2026-11-30 13:00:00');

-- Resumen de triggers creados.
SELECT trigger_name, event_manipulation AS evento, event_object_table AS tabla, action_timing AS momento
FROM information_schema.triggers
WHERE trigger_schema = 'medicita_ips'
ORDER BY event_object_table, trigger_name;
