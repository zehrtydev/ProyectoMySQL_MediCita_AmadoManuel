-- =====================================================================
-- MediCita IPS · 05_procedimientos.sql
-- Fase 5 · 5 procedimientos (de menor a mayor dificultad) con sus pruebas
-- Requiere 04_funciones.sql (P-3 usa fn_medico_disponible y P-4 usa
-- fn_tarifa_vigente).
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- P-1 · sp_registrar_paciente
-- Registra un paciente con su teléfono principal, en una transacción:
-- si falla el teléfono, tampoco queda el paciente.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_paciente;
DELIMITER $$
CREATE PROCEDURE sp_registrar_paciente(
    IN  p_tipo_documento   VARCHAR(5),
    IN  p_numero_documento VARCHAR(20),
    IN  p_nombres          VARCHAR(60),
    IN  p_apellidos        VARCHAR(60),
    IN  p_fecha_nacimiento DATE,
    IN  p_sexo             VARCHAR(15),
    IN  p_direccion        VARCHAR(150),
    IN  p_ciudad           BIGINT,
    IN  p_correo           VARCHAR(120),
    IN  p_telefono         VARCHAR(20),
    OUT p_paciente_id      BIGINT
)
BEGIN
    DECLARE v_tipo_id BIGINT;
    DECLARE v_mensaje VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_paciente_id = NULL;
        RESIGNAL;
    END;

    SET p_paciente_id = NULL;
    SET v_tipo_id = (SELECT id FROM document_types WHERE code = p_tipo_documento);

    IF v_tipo_id IS NULL THEN
        SET v_mensaje = CONCAT('El tipo de documento ', COALESCE(p_tipo_documento, 'NULL'), ' no existe.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF p_numero_documento IS NULL OR TRIM(p_numero_documento) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de documento es obligatorio.';
    END IF;
    IF EXISTS (SELECT 1 FROM patients
               WHERE document_type_id = v_tipo_id AND document_number = TRIM(p_numero_documento)) THEN
        SET v_mensaje = CONCAT('Ya existe un paciente con ', p_tipo_documento, ' ', TRIM(p_numero_documento), '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF p_sexo NOT IN ('FEMENINO', 'MASCULINO', 'INTERSEXUAL') OR p_sexo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El sexo debe ser FEMENINO, MASCULINO o INTERSEXUAL.';
    END IF;
    IF p_telefono IS NULL OR TRIM(p_telefono) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El teléfono principal es obligatorio.';
    END IF;

    START TRANSACTION;
        INSERT INTO patients (document_type_id, document_number, first_name, last_name, birth_date,
                              sex, address, city_id, email)
        VALUES (v_tipo_id, TRIM(p_numero_documento), p_nombres, p_apellidos, p_fecha_nacimiento,
                p_sexo, p_direccion, p_ciudad, p_correo);
        SET p_paciente_id = LAST_INSERT_ID();

        INSERT INTO patient_phones (patient_id, phone_number, phone_type, is_primary)
        VALUES (p_paciente_id, TRIM(p_telefono), 'CELULAR', TRUE);
    COMMIT;
END$$
DELIMITER ;

-- Prueba que funciona: nuevo paciente con su teléfono principal.
CALL sp_registrar_paciente('CC', '1098333444', 'Mariana', 'Becerra Solano', '1998-02-14', 'FEMENINO',
                           'Calle 9 # 23-15', 1, 'mariana.becerra@gmail.com', '3165550101', @nuevo_paciente);
SELECT @nuevo_paciente AS paciente_creado;
SELECT p.id, p.first_name, p.last_name, ph.phone_number, ph.is_primary
FROM patients p
JOIN patient_phones ph ON ph.patient_id = p.id
WHERE p.id = @nuevo_paciente;

-- El mismo número con OTRO tipo sí se permite (RP-01).
CALL sp_registrar_paciente('PA', '1098333444', 'Mark', 'Taylor', '1975-06-01', 'MASCULINO',
                           NULL, 1, NULL, '3165550202', @otro_paciente);
SELECT @otro_paciente AS paciente_creado_con_pasaporte;

-- ⚠️ ESPERADO: ERROR 1644 Ya existe un paciente con CC 63345120.
CALL sp_registrar_paciente('CC', '63345120', 'Rosa', 'Repetida', '1952-03-14', 'FEMENINO',
                           NULL, 1, NULL, '3000000000', @repetido);

-- ⚠️ ESPERADO: ERROR 1644 El teléfono principal es obligatorio.
CALL sp_registrar_paciente('CC', '1098999000', 'Sin', 'Teléfono', '1990-01-01', 'MASCULINO',
                           NULL, 1, NULL, '', @sin_telefono);

-- ---------------------------------------------------------------------
-- P-2 · sp_cancelar_cita
-- Cancela una cita PROGRAMADA o CONFIRMADA con un motivo del catálogo.
-- No escribe el historial: de eso se encarga el trigger T-3, que lee
-- updated_by, status_changed_at y cancellation_reason_id de la fila.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cancelar_cita;
DELIMITER $$
CREATE PROCEDURE sp_cancelar_cita(
    IN p_cita        BIGINT,
    IN p_motivo      VARCHAR(80),
    IN p_responsable BIGINT,
    IN p_fecha       DATETIME
)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_motivo_id BIGINT;
    DECLARE v_mensaje VARCHAR(255);

    SET v_estado = (SELECT status FROM appointments WHERE id = p_cita);

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cita no existe.';
    END IF;
    IF v_estado = 'ATENDIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede cancelar una cita que ya fue ATENDIDA.';
    END IF;
    IF v_estado = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cita ya está CANCELADA.';
    END IF;
    IF v_estado = 'NO_ASISTIO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede cancelar una cita marcada como NO_ASISTIO.';
    END IF;
    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El motivo de cancelación es obligatorio.';
    END IF;

    SET v_motivo_id = (SELECT id FROM cancellation_reasons
                       WHERE name = TRIM(p_motivo) AND is_active = TRUE);
    IF v_motivo_id IS NULL THEN
        SET v_mensaje = CONCAT('El motivo "', TRIM(p_motivo), '" no existe en el catálogo de motivos de cancelación.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM staff WHERE id = p_responsable AND is_active = TRUE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El responsable de la cancelación no existe o está inactivo.';
    END IF;
    IF p_fecha IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de cancelación es obligatoria.';
    END IF;

    UPDATE appointments
    SET status = 'CANCELADA',
        cancellation_reason_id = v_motivo_id,
        updated_by = p_responsable,
        status_changed_at = p_fecha
    WHERE id = p_cita;
END$$
DELIMITER ;

-- Prueba que funciona: se cancela la cita 183 (PROGRAMADA, 3 de diciembre).
-- Se hace dentro de una transacción que se deshace, porque el trigger T-3
-- todavía no existe: la cancelación "de verdad" se repite en 06_triggers.sql
-- para que quede en el historial.
SELECT id, status, cancellation_reason_id FROM appointments WHERE id = 183;
START TRANSACTION;
CALL sp_cancelar_cita(183, 'Viaje', 2, '2026-11-30 10:00:00');
SELECT a.id, a.status, r.name AS motivo, a.updated_by, a.status_changed_at
FROM appointments a
JOIN cancellation_reasons r ON r.id = a.cancellation_reason_id
WHERE a.id = 183;
ROLLBACK;

-- ⚠️ ESPERADO: ERROR 1644 El motivo de cancelación es obligatorio.
CALL sp_cancelar_cita(184, '', 2, '2026-11-30 10:00:00');
-- ⚠️ ESPERADO: ERROR 1644 El motivo "Pereza" no existe en el catálogo de motivos de cancelación.
CALL sp_cancelar_cita(184, 'Pereza', 2, '2026-11-30 10:00:00');
-- ⚠️ ESPERADO: ERROR 1644 No se puede cancelar una cita que ya fue ATENDIDA.
CALL sp_cancelar_cita(149, 'Viaje', 2, '2026-11-30 10:00:00');
-- ⚠️ ESPERADO: ERROR 1644 La cita ya está CANCELADA.
CALL sp_cancelar_cita(174, 'Viaje', 2, '2026-11-30 10:00:00');

-- ---------------------------------------------------------------------
-- P-3 · sp_agendar_cita
-- Valida especialidad, sede, disponibilidad del médico y del consultorio.
-- La cita nace PROGRAMADA y se registra su primer estado en el historial
-- (T-3 solo actúa en UPDATE, no en INSERT).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_agendar_cita;
DELIMITER $$
CREATE PROCEDURE sp_agendar_cita(
    IN  p_paciente     BIGINT,
    IN  p_medico       BIGINT,
    IN  p_especialidad BIGINT,
    IN  p_consultorio  BIGINT,
    IN  p_tipo_cita    BIGINT,
    IN  p_inicio       DATETIME,
    IN  p_responsable  BIGINT,
    OUT p_cita_id      BIGINT
)
BEGIN
    DECLARE v_duracion INT;
    DECLARE v_sede BIGINT;
    DECLARE v_fin DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_cita_id = NULL;
        RESIGNAL;
    END;

    SET p_cita_id = NULL;

    IF NOT EXISTS (SELECT 1 FROM patients WHERE id = p_paciente) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El paciente no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM doctors WHERE id = p_medico AND is_active = TRUE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El médico no existe o está inactivo.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM staff WHERE id = p_responsable AND is_active = TRUE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El responsable no existe o está inactivo.';
    END IF;

    SET v_duracion = (SELECT duration_minutes FROM appointment_types WHERE id = p_tipo_cita);
    IF v_duracion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de cita no existe.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM doctor_specialties
                   WHERE doctor_id = p_medico AND specialty_id = p_especialidad) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El médico no tiene esa especialidad.';
    END IF;

    SET v_sede = (SELECT branch_id FROM offices WHERE id = p_consultorio AND is_active = TRUE);
    IF v_sede IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El consultorio no existe o está inactivo.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM doctor_branches WHERE doctor_id = p_medico AND branch_id = v_sede) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El médico no atiende en la sede de ese consultorio.';
    END IF;

    IF fn_medico_disponible(p_medico, p_inicio, v_duracion) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El médico no está disponible: fuera de su horario, con una novedad o con otra cita a esa hora.';
    END IF;

    SET v_fin = p_inicio + INTERVAL v_duracion MINUTE;
    IF EXISTS (SELECT 1 FROM appointments
               WHERE office_id = p_consultorio
                 AND status <> 'CANCELADA'
                 AND start_at < v_fin
                 AND p_inicio < end_at) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El consultorio ya está ocupado en ese horario.';
    END IF;

    START TRANSACTION;
        INSERT INTO appointments (patient_id, doctor_id, specialty_id, office_id, appointment_type_id,
                                  start_at, end_at, status, created_by)
        VALUES (p_paciente, p_medico, p_especialidad, p_consultorio, p_tipo_cita,
                p_inicio, v_fin, 'PROGRAMADA', p_responsable);
        SET p_cita_id = LAST_INSERT_ID();

        INSERT INTO appointment_status_history (appointment_id, previous_status, new_status, changed_at, changed_by)
        VALUES (p_cita_id, NULL, 'PROGRAMADA', NOW(), p_responsable);
    COMMIT;
END$$
DELIMITER ;

-- Prueba que funciona 1: Ana Lucía (24) con Méndez (3), medicina general, consultorio 101 de Cabecera,
-- lunes 14 de diciembre 7:00, control de 20 minutos (tipo 2).
CALL sp_agendar_cita(24, 3, 1, 1, 2, '2026-12-14 07:00:00', 2, @cita_1);
-- Prueba que funciona 2: Juan Camilo (13) con Salazar (1) en Medicina interna, consultorio 102, a las 15:00.
CALL sp_agendar_cita(13, 1, 2, 2, 4, '2026-12-14 15:00:00', 2, @cita_2);
SELECT a.id, a.start_at, a.end_at, a.status, d.last_name AS medico, s.name AS especialidad, o.code AS consultorio
FROM appointments a
JOIN doctors d ON d.id = a.doctor_id
JOIN specialties s ON s.id = a.specialty_id
JOIN offices o ON o.id = a.office_id
WHERE a.id IN (@cita_1, @cita_2);
SELECT * FROM appointment_status_history WHERE appointment_id IN (@cita_1, @cita_2);

-- ⚠️ ESPERADO: ERROR 1644 El médico no tiene esa especialidad.
CALL sp_agendar_cita(13, 3, 6, 1, 3, '2026-12-14 07:20:00', 2, @falla);
-- ⚠️ ESPERADO: ERROR 1644 El médico no atiende en la sede de ese consultorio.
-- (consultorio 5 = Cañaveral 101; Méndez solo atiende en Cabecera)
CALL sp_agendar_cita(13, 3, 1, 5, 2, '2026-12-14 07:20:00', 2, @falla);
-- ⚠️ ESPERADO: ERROR 1644 El médico no está disponible: fuera de su horario, con una novedad o con otra cita a esa hora.
-- (Vargas está de vacaciones del 1 al 15 de diciembre)
CALL sp_agendar_cita(8, 7, 6, 2, 4, '2026-12-09 08:00:00', 2, @falla);
-- ⚠️ ESPERADO: ERROR 1644 El médico no está disponible: fuera de su horario, con una novedad o con otra cita a esa hora.
-- (Méndez ya tiene la cita recién creada a las 7:00)
CALL sp_agendar_cita(13, 3, 1, 1, 2, '2026-12-14 07:10:00', 2, @falla);
-- ⚠️ ESPERADO: ERROR 1644 El consultorio ya está ocupado en ese horario.
-- (Herrera sí está disponible el lunes a las 15:00 y atiende en Cabecera,
-- pero el consultorio 102 lo ocupa la cita de Salazar)
CALL sp_agendar_cita(9, 8, 7, 2, 8, '2026-12-14 15:00:00', 2, @falla);

-- ---------------------------------------------------------------------
-- P-4 · sp_facturar_atencion
-- Factura una atención en una transacción: cabecera + un renglón por
-- servicio con la tarifa vigente EL DÍA DE LA ATENCIÓN (no el de la
-- factura), y reparte el total según el copago del plan vigente ese día
-- (PARTICULAR = 100 % si no hay afiliación vigente).
-- Si cualquier paso falla, el EXIT HANDLER hace ROLLBACK: no queda nada.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_facturar_atencion;
DELIMITER $$
CREATE PROCEDURE sp_facturar_atencion(
    IN  p_atencion   BIGINT,
    IN  p_fecha      DATE,
    OUT p_factura_id BIGINT
)
BEGIN
    DECLARE v_paciente BIGINT;
    DECLARE v_fecha_atencion DATE;
    DECLARE v_plan BIGINT;
    DECLARE v_aseguradora BIGINT;
    DECLARE v_copago DECIMAL(5,2);
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_parte_paciente DECIMAL(12,2);
    DECLARE v_consecutivo INT;
    DECLARE v_factura_existente VARCHAR(20);
    DECLARE v_mensaje VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_factura_id = NULL;
        RESIGNAL;
    END;

    SET p_factura_id = NULL;

    SET v_paciente = (SELECT a.patient_id
                      FROM encounters e JOIN appointments a ON a.id = e.appointment_id
                      WHERE e.id = p_atencion);
    SET v_fecha_atencion = (SELECT DATE(started_at) FROM encounters WHERE id = p_atencion);

    IF v_paciente IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La atención no existe.';
    END IF;

    SET v_factura_existente = (SELECT invoice_number FROM invoices WHERE encounter_id = p_atencion);
    IF v_factura_existente IS NOT NULL THEN
        SET v_mensaje = CONCAT('La atención ', p_atencion, ' ya tiene la factura ', v_factura_existente,
                               ': no se factura dos veces.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
    IF p_fecha IS NULL OR p_fecha < v_fecha_atencion THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la factura no puede ser anterior a la atención.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM encounter_diagnoses WHERE encounter_id = p_atencion AND is_primary = TRUE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La atención no tiene diagnóstico principal: no se puede facturar.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM encounter_procedures WHERE encounter_id = p_atencion) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La atención no tiene servicios registrados.';
    END IF;

    -- Plan y aseguradora vigentes el día de la atención.
    SET v_plan = (SELECT af.plan_id FROM affiliations af
                  WHERE af.patient_id = v_paciente
                    AND af.start_date <= v_fecha_atencion
                    AND (af.end_date IS NULL OR af.end_date >= v_fecha_atencion)
                  ORDER BY af.start_date DESC LIMIT 1);
    SET v_aseguradora = (SELECT af.insurer_id FROM affiliations af
                         WHERE af.patient_id = v_paciente
                           AND af.start_date <= v_fecha_atencion
                           AND (af.end_date IS NULL OR af.end_date >= v_fecha_atencion)
                         ORDER BY af.start_date DESC LIMIT 1);
    IF v_plan IS NULL THEN
        SET v_plan = (SELECT id FROM plans WHERE name = 'PARTICULAR');
        SET v_aseguradora = NULL;
    END IF;
    SET v_copago = (SELECT copay_percentage FROM plans WHERE id = v_plan);

    SET v_consecutivo = (SELECT COALESCE(MAX(CAST(SUBSTRING(invoice_number, 4) AS UNSIGNED)), 0) + 1
                         FROM invoices);

    START TRANSACTION;
        INSERT INTO invoices (invoice_number, encounter_id, issued_at, plan_id, insurer_id)
        VALUES (CONCAT('FV-', LPAD(v_consecutivo, 6, '0')), p_atencion, p_fecha, v_plan, v_aseguradora);
        SET p_factura_id = LAST_INSERT_ID();

        -- Un renglón por servicio prestado, con el precio COPIADO del día de la atención.
        -- Si un servicio no tiene tarifa, fn_tarifa_vigente lanza error y todo se deshace.
        INSERT INTO invoice_items (invoice_id, service_id, quantity, unit_price)
        SELECT p_factura_id, ep.service_id, ep.quantity,
               fn_tarifa_vigente(ep.service_id, v_plan, v_fecha_atencion)
        FROM encounter_procedures ep
        WHERE ep.encounter_id = p_atencion;

        SET v_total = (SELECT SUM(line_total) FROM invoice_items WHERE invoice_id = p_factura_id);
        SET v_parte_paciente = ROUND(v_total * v_copago / 100, 2);

        UPDATE invoices
        SET total_amount = v_total,
            patient_amount = v_parte_paciente,
            insurer_amount = v_total - v_parte_paciente
        WHERE id = p_factura_id;
    COMMIT;
END$$
DELIMITER ;

-- Prueba que funciona 1: atención 116 (Hernando Prada, Nueva EPS, CONTRIBUTIVO 10 %).
CALL sp_facturar_atencion(116, '2026-11-30', @factura_1);
-- Prueba que funciona 2: atención 119 (Diego Pinzón). Su afiliación terminó el 15 de
-- noviembre, así que el 30 se factura como PARTICULAR (paciente paga el 100 %).
CALL sp_facturar_atencion(119, '2026-11-30', @factura_2);
SELECT i.id, i.invoice_number, pl.name AS plan, COALESCE(ins.name, 'PARTICULAR') AS aseguradora,
       i.total_amount, i.patient_amount, i.insurer_amount, i.status
FROM invoices i
JOIN plans pl ON pl.id = i.plan_id
LEFT JOIN insurers ins ON ins.id = i.insurer_id
WHERE i.id IN (@factura_1, @factura_2);
SELECT ii.invoice_id, s.cups_code, s.name, ii.quantity, ii.unit_price, ii.line_total
FROM invoice_items ii
JOIN services s ON s.id = ii.service_id
WHERE ii.invoice_id IN (@factura_1, @factura_2);

-- ⚠️ ESPERADO: ERROR 1644 La atención 116 ya tiene la factura FV-000116: no se factura dos veces.
CALL sp_facturar_atencion(116, '2026-11-30', @falla);

-- Prueba de atomicidad: a la atención 117 se le agrega una nebulización (servicio 11),
-- que no tiene tarifa. La factura falla y NO queda ni cabecera ni renglones.
INSERT INTO encounter_procedures (encounter_id, service_id, quantity) VALUES (117, 11, 1);
-- ⚠️ ESPERADO: ERROR 1644 No hay tarifa vigente para el servicio 11 en el plan 4 el 2026-11-30.
CALL sp_facturar_atencion(117, '2026-11-30', @falla);
SELECT COUNT(*) AS facturas_de_la_atencion_117 FROM invoices WHERE encounter_id = 117;   -- 0
-- Se retira el servicio sin tarifa y ahora sí se factura.
SELECT id, encounter_id, service_id FROM encounter_procedures WHERE encounter_id = 117 AND service_id = 11;
DELETE FROM encounter_procedures WHERE encounter_id = 117 AND service_id = 11;
CALL sp_facturar_atencion(117, '2026-11-30', @factura_3);
-- Nota: el id de la factura salta un número. El intento fallido alcanzó a
-- reservar un AUTO_INCREMENT antes del ROLLBACK, e InnoDB no lo devuelve.
-- El consecutivo FV-xxxxxx sí queda continuo porque se calcula con MAX.
SELECT id, invoice_number, total_amount, patient_amount, insurer_amount FROM invoices WHERE id = @factura_3;

-- ---------------------------------------------------------------------
-- P-5 · sp_reporte_produccion
-- Recorre los médicos con un cursor y arma el reporte del rango:
-- atenciones, valor facturado (sin anuladas) y promedio por atención.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_reporte_produccion;
DELIMITER $$
CREATE PROCEDURE sp_reporte_produccion(IN p_desde DATE, IN p_hasta DATE)
BEGIN
    DECLARE v_fin_cursor TINYINT DEFAULT 0;
    DECLARE v_medico_id BIGINT;
    DECLARE v_medico VARCHAR(130);
    DECLARE v_atenciones INT;
    DECLARE v_facturado DECIMAL(12,2);

    DECLARE cur_medicos CURSOR FOR
        SELECT id, CONCAT(first_name, ' ', last_name)
        FROM doctors
        ORDER BY last_name, first_name;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin_cursor = 1;

    IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta < p_desde THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El rango de fechas no es válido: la fecha final debe ser igual o posterior a la inicial.';
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_reporte_produccion;
    CREATE TEMPORARY TABLE tmp_reporte_produccion (
        medico VARCHAR(130),
        atenciones INT,
        valor_facturado DECIMAL(12,2),
        promedio_por_atencion DECIMAL(12,2)
    );

    OPEN cur_medicos;
    leer_medicos: LOOP
        FETCH cur_medicos INTO v_medico_id, v_medico;
        IF v_fin_cursor = 1 THEN
            LEAVE leer_medicos;
        END IF;

        SET v_atenciones = (SELECT COUNT(*)
                            FROM encounters e
                            JOIN appointments a ON a.id = e.appointment_id
                            WHERE a.doctor_id = v_medico_id
                              AND DATE(e.started_at) BETWEEN p_desde AND p_hasta);

        SET v_facturado = (SELECT COALESCE(SUM(i.total_amount), 0)
                           FROM invoices i
                           JOIN encounters e   ON e.id = i.encounter_id
                           JOIN appointments a ON a.id = e.appointment_id
                           WHERE a.doctor_id = v_medico_id
                             AND i.status <> 'ANULADA'
                             AND DATE(e.started_at) BETWEEN p_desde AND p_hasta);

        INSERT INTO tmp_reporte_produccion
        VALUES (v_medico, v_atenciones, v_facturado,
                CASE WHEN v_atenciones = 0 THEN 0 ELSE ROUND(v_facturado / v_atenciones, 2) END);
    END LOOP;
    CLOSE cur_medicos;

    SELECT medico, atenciones, valor_facturado, promedio_por_atencion
    FROM tmp_reporte_produccion
    ORDER BY valor_facturado DESC, medico;

    DROP TEMPORARY TABLE IF EXISTS tmp_reporte_produccion;
END$$
DELIMITER ;

-- Prueba que funciona: producción de noviembre de 2026.
CALL sp_reporte_produccion('2026-11-01', '2026-11-30');
-- ⚠️ ESPERADO: ERROR 1644 El rango de fechas no es válido: la fecha final debe ser igual o posterior a la inicial.
CALL sp_reporte_produccion('2026-11-30', '2026-11-01');
