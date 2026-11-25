-- =====================================================================
-- MediCita IPS · 04_funciones.sql
-- Fase 5 · 5 funciones (de menor a mayor dificultad) con sus pruebas
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- F-1 · fn_edad: edad en años cumplidos a una fecha.
-- DETERMINISTIC NO SQL: solo opera con sus parámetros.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_edad;
DELIMITER $$
CREATE FUNCTION fn_edad(p_fecha_nacimiento DATE, p_fecha_ref DATE)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    IF p_fecha_nacimiento IS NULL OR p_fecha_ref IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_fecha_ref < p_fecha_nacimiento THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La fecha de referencia no puede ser anterior a la fecha de nacimiento.';
    END IF;
    -- TIMESTAMPDIFF cuenta años completos: si aún no cumple años en la
    -- fecha de referencia, no suma ese año.
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, p_fecha_ref);
END$$
DELIMITER ;

-- Prueba que funciona: Rosa Elena nació el 1952-03-14 -> 74 años al corte.
SELECT fn_edad('1952-03-14', '2026-11-30') AS edad_rosa;          -- 74
-- Prueba de borde: cumple el 1 de diciembre, al corte aún no -> 63.
SELECT fn_edad('1962-12-01', '2026-11-30') AS edad_luz_marina;    -- 63
-- Uso sobre la tabla: edad de los pacientes al corte.
SELECT first_name, last_name, fn_edad(birth_date, '2026-11-30') AS edad
FROM patients
ORDER BY edad DESC
LIMIT 5;
-- ⚠️ ESPERADO: ERROR 1644 La fecha de referencia no puede ser anterior a la fecha de nacimiento.
SELECT fn_edad('2026-12-31', '2026-11-30');

-- ---------------------------------------------------------------------
-- F-2 · fn_imc: índice de masa corporal con 2 decimales.
-- DETERMINISTIC NO SQL: fórmula pura peso / talla(m)^2.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_imc;
DELIMITER $$
CREATE FUNCTION fn_imc(p_peso_kg DECIMAL(5,2), p_talla_cm DECIMAL(5,1))
RETURNS DECIMAL(5,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_talla_m DECIMAL(6,3);
    IF p_talla_cm IS NULL OR p_talla_cm = 0 OR p_peso_kg IS NULL THEN
        RETURN NULL;
    END IF;
    SET v_talla_m = p_talla_cm / 100;
    RETURN ROUND(p_peso_kg / (v_talla_m * v_talla_m), 2);
END$$
DELIMITER ;

-- Prueba que funciona: 88 kg y 160 cm -> 34.38.
SELECT fn_imc(88, 160) AS imc;
-- Talla 0 o nula -> NULL (no error).
SELECT fn_imc(70, 0) AS imc_talla_cero, fn_imc(70, NULL) AS imc_talla_nula;
-- Uso sobre la tabla: IMC de las tomas del 30 de noviembre.
SELECT vs.encounter_id, vs.weight_kg, vs.height_cm, fn_imc(vs.weight_kg, vs.height_cm) AS imc
FROM vital_signs vs
WHERE vs.taken_at >= '2026-11-30'
ORDER BY imc DESC;

-- ---------------------------------------------------------------------
-- F-3 · fn_tarifa_vigente: precio del servicio para el plan en una fecha.
-- NOT DETERMINISTIC READS SQL DATA: lee tariffs, que puede cambiar.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_tarifa_vigente;
DELIMITER $$
CREATE FUNCTION fn_tarifa_vigente(p_servicio BIGINT, p_plan BIGINT, p_fecha DATE)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(12,2);
    DECLARE v_mensaje VARCHAR(255);

    -- Asignación con subconsulta: si no hay filas, v_precio queda NULL
    -- (sin el aviso "No data" que deja un SELECT ... INTO vacío).
    SET v_precio = (SELECT t.price
                    FROM tariffs t
                    WHERE t.service_id = p_servicio
                      AND t.plan_id = p_plan
                      AND t.valid_from <= p_fecha
                      AND (t.valid_to IS NULL OR t.valid_to >= p_fecha)
                    ORDER BY t.valid_from DESC
                    LIMIT 1);

    IF v_precio IS NULL THEN
        SET v_mensaje = CONCAT('No hay tarifa vigente para el servicio ', p_servicio,
                               ' en el plan ', p_plan, ' el ', DATE_FORMAT(p_fecha, '%Y-%m-%d'), '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    RETURN v_precio;
END$$
DELIMITER ;

-- Prueba que funciona: consulta especializada (3) PARTICULAR (4).
-- El 15 de septiembre rige la tarifa antigua y el 15 de noviembre la actual.
SELECT fn_tarifa_vigente(3, 4, '2026-09-15') AS tarifa_septiembre,   -- 142500.00
       fn_tarifa_vigente(3, 4, '2026-11-15') AS tarifa_noviembre;    -- 150000.00
-- ⚠️ ESPERADO: ERROR 1644 No hay tarifa vigente para el servicio 11 en el plan 4 el 2026-11-30.
SELECT fn_tarifa_vigente(11, 4, '2026-11-30');

-- ---------------------------------------------------------------------
-- F-4 · fn_saldo_factura: total menos abonos (anuladas = 0).
-- NOT DETERMINISTIC READS SQL DATA: el saldo cambia con cada abono.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_saldo_factura;
DELIMITER $$
CREATE FUNCTION fn_saldo_factura(p_factura BIGINT)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_estado VARCHAR(20);
    DECLARE v_abonado DECIMAL(12,2);

    SELECT total_amount, status INTO v_total, v_estado
    FROM invoices
    WHERE id = p_factura;

    IF v_total IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura no existe.';
    END IF;
    IF v_estado = 'ANULADA' THEN
        RETURN 0;
    END IF;

    SET v_abonado = (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE invoice_id = p_factura);
    RETURN v_total - v_abonado;
END$$
DELIMITER ;

-- Prueba que funciona: saldo de varias facturas en distintos estados.
SELECT id, invoice_number, status, total_amount, fn_saldo_factura(id) AS saldo
FROM invoices
WHERE id IN (1, 2, 29, 44)
ORDER BY id;
-- La factura 44 está ANULADA -> saldo 0.
-- ⚠️ ESPERADO: ERROR 1644 La factura no existe.
SELECT fn_saldo_factura(99999);

-- ---------------------------------------------------------------------
-- F-5 · fn_medico_disponible: 1 si el médico puede atender en el intervalo.
-- NOT DETERMINISTIC READS SQL DATA: lee horarios, novedades y citas.
-- Condiciones:
--   a) el intervalo cae completo dentro de un horario de ese día de la semana,
--   b) ninguna novedad cubre la fecha,
--   c) no se cruza con otra cita del médico que no esté CANCELADA.
-- Dos intervalos [i1, f1) y [i2, f2) se cruzan si i1 < f2 AND i2 < f1.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_medico_disponible;
DELIMITER $$
CREATE FUNCTION fn_medico_disponible(p_medico BIGINT, p_inicio DATETIME, p_duracion_min INT)
RETURNS TINYINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fin DATETIME;
    DECLARE v_dia TINYINT;

    IF p_duracion_min IS NULL OR p_duracion_min <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La duración de la cita debe ser mayor que 0 minutos.';
    END IF;

    SET v_fin = p_inicio + INTERVAL p_duracion_min MINUTE;
    SET v_dia = WEEKDAY(p_inicio) + 1;          -- 1 = lunes … 7 = domingo

    -- Médico inactivo: no se le agenda.
    IF NOT EXISTS (SELECT 1 FROM doctors WHERE id = p_medico AND is_active = TRUE) THEN
        RETURN 0;
    END IF;

    -- a) Dentro de su horario (y sin pasar a otro día).
    IF DATE(v_fin) <> DATE(p_inicio) OR NOT EXISTS (
        SELECT 1 FROM doctor_schedules s
        WHERE s.doctor_id = p_medico
          AND s.day_of_week = v_dia
          AND s.start_time <= TIME(p_inicio)
          AND s.end_time >= TIME(v_fin)) THEN
        RETURN 0;
    END IF;

    -- b) Sin novedad que cubra la fecha.
    IF EXISTS (
        SELECT 1 FROM doctor_absences n
        WHERE n.doctor_id = p_medico
          AND DATE(p_inicio) BETWEEN n.start_date AND n.end_date) THEN
        RETURN 0;
    END IF;

    -- c) Sin cruce con otra cita no cancelada.
    IF EXISTS (
        SELECT 1 FROM appointments a
        WHERE a.doctor_id = p_medico
          AND a.status <> 'CANCELADA'
          AND a.start_at < v_fin
          AND p_inicio < a.end_at) THEN
        RETURN 0;
    END IF;

    RETURN 1;
END$$
DELIMITER ;

-- Prueba que funciona: Méndez (3) el lunes 14 de diciembre a las 7:00 está libre.
SELECT fn_medico_disponible(3, '2026-12-14 07:00:00', 20) AS mendez_libre;          -- 1
-- No disponible por cruce: Méndez ya tiene cita el 14 de diciembre de 9:00 a 9:30.
SELECT fn_medico_disponible(3, '2026-12-14 09:10:00', 20) AS mendez_cruce;          -- 0
-- No disponible por novedad: Vargas (7) está de vacaciones del 1 al 15 de diciembre.
SELECT fn_medico_disponible(7, '2026-12-02 08:00:00', 30) AS vargas_vacaciones;     -- 0
-- No disponible por horario: Méndez termina a las 12:00 (11:50 + 20 min se pasa).
SELECT fn_medico_disponible(3, '2026-12-14 11:50:00', 20) AS mendez_fuera_horario;  -- 0
-- Una cita cancelada no ocupa el espacio: se busca una cancelada futura y se prueba su hora.
SELECT a.id, a.doctor_id, a.start_at, a.status,
       fn_medico_disponible(a.doctor_id, a.start_at, TIMESTAMPDIFF(MINUTE, a.start_at, a.end_at)) AS disponible
FROM appointments a
WHERE a.status = 'CANCELADA' AND a.start_at >= '2026-12-01'
ORDER BY a.start_at
LIMIT 3;
-- ⚠️ ESPERADO: ERROR 1644 La duración de la cita debe ser mayor que 0 minutos.
SELECT fn_medico_disponible(3, '2026-12-14 07:00:00', 0);
