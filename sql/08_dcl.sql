-- =====================================================================
-- MediCita IPS · 08_dcl.sql
-- Fase 6 · Roles, usuarios, permisos (privilegio mínimo) y pruebas
-- Ejecutar como root. Las contraseñas son SOLO de práctica.
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- Procedimiento de apoyo: sp_anular_factura
-- Facturación nunca cambia el estado de una factura a mano:
-- PARCIAL/PAGADA las pone T-4, VENCIDA el evento E-4 y ANULADA este procedimiento.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_anular_factura;
DELIMITER $$
CREATE PROCEDURE sp_anular_factura(
    IN p_factura BIGINT,
    IN p_fecha   DATE,
    IN p_motivo  VARCHAR(255)
)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_emision DATE;

    SET v_estado  = (SELECT status FROM invoices WHERE id = p_factura);
    SET v_emision = (SELECT issued_at FROM invoices WHERE id = p_factura);

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura no existe.';
    END IF;
    IF v_estado = 'ANULADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura ya está anulada.';
    END IF;
    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El motivo de anulación es obligatorio.';
    END IF;
    IF EXISTS (SELECT 1 FROM payments WHERE invoice_id = p_factura) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura tiene abonos: no se puede anular.';
    END IF;
    IF p_fecha IS NULL OR p_fecha < v_emision THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de anulación no puede ser anterior a la emisión.';
    END IF;

    UPDATE invoices
    SET status = 'ANULADA', voided_at = p_fecha, void_reason = TRIM(p_motivo)
    WHERE id = p_factura;
END$$
DELIMITER ;

-- Prueba que funciona: la factura 114 (PENDIENTE, sin abonos) se anula.
SELECT id, invoice_number, status, voided_at, void_reason FROM invoices WHERE id = 114;
CALL sp_anular_factura(114, '2026-11-30', 'Se registró un procedimiento que no se realizó');
SELECT id, invoice_number, status, voided_at, void_reason FROM invoices WHERE id = 114;
-- ⚠️ ESPERADO: ERROR 1644 La factura no existe.
CALL sp_anular_factura(99999, '2026-11-30', 'Prueba');
-- ⚠️ ESPERADO: ERROR 1644 La factura ya está anulada.
CALL sp_anular_factura(44, '2026-11-30', 'Prueba');
-- ⚠️ ESPERADO: ERROR 1644 El motivo de anulación es obligatorio.
CALL sp_anular_factura(116, '2026-11-30', '   ');
-- ⚠️ ESPERADO: ERROR 1644 La factura tiene abonos: no se puede anular.
CALL sp_anular_factura(29, '2026-11-30', 'Prueba con abonos');

-- ---------------------------------------------------------------------
-- Limpieza previa (para que el script se pueda ejecutar varias veces)
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'u_recepcion'@'localhost', 'u_medico'@'localhost', 'u_facturacion'@'localhost',
                    'u_auditor'@'localhost', 'u_admin_bd'@'localhost';
DROP ROLE IF EXISTS 'rol_recepcion', 'rol_medico', 'rol_facturacion', 'rol_auditor', 'rol_admin_bd';

CREATE ROLE 'rol_recepcion', 'rol_medico', 'rol_facturacion', 'rol_auditor', 'rol_admin_bd';

-- ---------------------------------------------------------------------
-- rol_recepcion
-- Puede: consultar pacientes, médicos, agenda y catálogos; registrar
--        pacientes, agendar y cancelar SOLO con los procedimientos.
-- No puede: ver datos clínicos ni de facturación; modificar citas directamente
--           (no tiene INSERT/UPDATE/DELETE sobre ninguna tabla).
-- ---------------------------------------------------------------------
GRANT SELECT ON medicita_ips.patients                   TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.patient_phones             TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.emergency_contacts         TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.affiliations               TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctors                    TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_specialties         TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_branches            TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_schedules           TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_absences            TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.appointments               TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.appointment_status_history TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.reminders                  TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.cities                     TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.branches                   TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.offices                    TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.specialties                TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.document_types             TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.insurers                   TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.plans                      TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.appointment_types          TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.cancellation_reasons       TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.staff                      TO 'rol_recepcion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_registrar_paciente TO 'rol_recepcion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_agendar_cita       TO 'rol_recepcion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_cancelar_cita      TO 'rol_recepcion';
GRANT EXECUTE ON FUNCTION  medicita_ips.fn_medico_disponible  TO 'rol_recepcion';

-- ---------------------------------------------------------------------
-- rol_medico
-- Puede: consultar pacientes y su agenda; registrar atenciones, signos
--        vitales, diagnósticos, fórmulas y laboratorio (INSERT y UPDATE).
-- No puede: ver facturación; borrar datos clínicos (no tiene DELETE).
-- ---------------------------------------------------------------------
GRANT SELECT ON medicita_ips.patients             TO 'rol_medico';
GRANT SELECT ON medicita_ips.patient_phones       TO 'rol_medico';
GRANT SELECT ON medicita_ips.emergency_contacts   TO 'rol_medico';
GRANT SELECT ON medicita_ips.document_types       TO 'rol_medico';
GRANT SELECT ON medicita_ips.appointments         TO 'rol_medico';
GRANT SELECT ON medicita_ips.appointment_types    TO 'rol_medico';
GRANT SELECT ON medicita_ips.doctors              TO 'rol_medico';
GRANT SELECT ON medicita_ips.specialties          TO 'rol_medico';
GRANT SELECT ON medicita_ips.doctor_schedules     TO 'rol_medico';
GRANT SELECT ON medicita_ips.offices              TO 'rol_medico';
GRANT SELECT ON medicita_ips.branches             TO 'rol_medico';
GRANT SELECT ON medicita_ips.cie10_codes          TO 'rol_medico';
GRANT SELECT ON medicita_ips.services             TO 'rol_medico';
GRANT SELECT ON medicita_ips.medications          TO 'rol_medico';
GRANT SELECT ON medicita_ips.active_ingredients   TO 'rol_medico';
GRANT SELECT ON medicita_ips.lab_tests            TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.patient_allergies    TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.encounters           TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.vital_signs          TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.encounter_diagnoses  TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.encounter_procedures TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.prescriptions        TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.prescription_items   TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.lab_orders           TO 'rol_medico';
GRANT SELECT, INSERT, UPDATE ON medicita_ips.lab_order_items      TO 'rol_medico';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_edad TO 'rol_medico';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_imc  TO 'rol_medico';

-- ---------------------------------------------------------------------
-- rol_facturacion
-- Puede: consultar atenciones y tarifas; facturar con sp_facturar_atencion;
--        registrar abonos (INSERT en payments; T-4 actualiza el estado);
--        anular con sp_anular_factura.
-- No puede: ver diagnósticos, fórmulas, laboratorio ni signos vitales;
--           UPDATE o DELETE sobre invoices.
-- encounter_procedures sí se le da: son los servicios que se cobran,
-- no información clínica sensible.
-- ---------------------------------------------------------------------
GRANT SELECT ON medicita_ips.encounters           TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.encounter_procedures TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.appointments         TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.patients             TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.affiliations         TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.doctors              TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.offices              TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.branches             TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.services             TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.tariffs              TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.plans                TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.insurers             TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.payment_methods      TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.invoices             TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.invoice_items        TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.production_summaries TO 'rol_facturacion';
GRANT SELECT, INSERT ON medicita_ips.payments     TO 'rol_facturacion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_facturar_atencion  TO 'rol_facturacion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_anular_factura     TO 'rol_facturacion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_reporte_produccion TO 'rol_facturacion';
GRANT EXECUTE ON FUNCTION  medicita_ips.fn_saldo_factura      TO 'rol_facturacion';
GRANT EXECUTE ON FUNCTION  medicita_ips.fn_tarifa_vigente     TO 'rol_facturacion';

-- ---------------------------------------------------------------------
-- rol_auditor
-- Puede: leer todo, excepto el documento y los datos de contacto de los
--        pacientes. En patients el permiso es POR COLUMNAS (sin
--        document_type_id, document_number, address ni email) y no tiene
--        acceso a patient_phones ni a emergency_contacts.
-- No puede: modificar nada (solo SELECT).
-- ---------------------------------------------------------------------
GRANT SELECT (id, first_name, last_name, birth_date, sex, city_id, created_at)
      ON medicita_ips.patients TO 'rol_auditor';
GRANT SELECT ON medicita_ips.active_ingredients         TO 'rol_auditor';
GRANT SELECT ON medicita_ips.affiliations               TO 'rol_auditor';
GRANT SELECT ON medicita_ips.appointment_status_history TO 'rol_auditor';
GRANT SELECT ON medicita_ips.appointment_types          TO 'rol_auditor';
GRANT SELECT ON medicita_ips.appointments               TO 'rol_auditor';
GRANT SELECT ON medicita_ips.branches                   TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cancellation_reasons       TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cie10_codes                TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cities                     TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_absences            TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_branches            TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_schedules           TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_specialties         TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctors                    TO 'rol_auditor';
GRANT SELECT ON medicita_ips.document_types             TO 'rol_auditor';
GRANT SELECT ON medicita_ips.encounter_diagnoses        TO 'rol_auditor';
GRANT SELECT ON medicita_ips.encounter_procedures       TO 'rol_auditor';
GRANT SELECT ON medicita_ips.encounters                 TO 'rol_auditor';
GRANT SELECT ON medicita_ips.insurers                   TO 'rol_auditor';
GRANT SELECT ON medicita_ips.invoice_items              TO 'rol_auditor';
GRANT SELECT ON medicita_ips.invoices                   TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_order_items            TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_orders                 TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_tests                  TO 'rol_auditor';
GRANT SELECT ON medicita_ips.medications                TO 'rol_auditor';
GRANT SELECT ON medicita_ips.offices                    TO 'rol_auditor';
GRANT SELECT ON medicita_ips.patient_allergies          TO 'rol_auditor';
GRANT SELECT ON medicita_ips.payment_methods            TO 'rol_auditor';
GRANT SELECT ON medicita_ips.payments                   TO 'rol_auditor';
GRANT SELECT ON medicita_ips.plans                      TO 'rol_auditor';
GRANT SELECT ON medicita_ips.prescription_items         TO 'rol_auditor';
GRANT SELECT ON medicita_ips.prescriptions              TO 'rol_auditor';
GRANT SELECT ON medicita_ips.production_summaries       TO 'rol_auditor';
GRANT SELECT ON medicita_ips.reminders                  TO 'rol_auditor';
GRANT SELECT ON medicita_ips.satisfaction_surveys       TO 'rol_auditor';
GRANT SELECT ON medicita_ips.services                   TO 'rol_auditor';
GRANT SELECT ON medicita_ips.specialties                TO 'rol_auditor';
GRANT SELECT ON medicita_ips.staff                      TO 'rol_auditor';
GRANT SELECT ON medicita_ips.tariffs                    TO 'rol_auditor';
GRANT SELECT ON medicita_ips.vital_signs                TO 'rol_auditor';

-- ---------------------------------------------------------------------
-- rol_admin_bd
-- Puede: todo sobre medicita_ips. No puede: nada fuera de medicita_ips
-- (el permiso es a nivel de base, no global *.*).
-- ---------------------------------------------------------------------
GRANT ALL PRIVILEGES ON medicita_ips.* TO 'rol_admin_bd';

-- ---------------------------------------------------------------------
-- Usuarios de prueba (uno por rol). Contraseñas SOLO de práctica.
-- SET DEFAULT ROLE hace que el rol quede activo al iniciar sesión.
-- ---------------------------------------------------------------------
CREATE USER 'u_recepcion'@'localhost'   IDENTIFIED BY 'Recepcion#2026';
CREATE USER 'u_medico'@'localhost'      IDENTIFIED BY 'Medico#2026';
CREATE USER 'u_facturacion'@'localhost' IDENTIFIED BY 'Facturacion#2026';
CREATE USER 'u_auditor'@'localhost'     IDENTIFIED BY 'Auditor#2026';
CREATE USER 'u_admin_bd'@'localhost'    IDENTIFIED BY 'AdminBD#2026';

GRANT 'rol_recepcion'   TO 'u_recepcion'@'localhost';
GRANT 'rol_medico'      TO 'u_medico'@'localhost';
GRANT 'rol_facturacion' TO 'u_facturacion'@'localhost';
GRANT 'rol_auditor'     TO 'u_auditor'@'localhost';
GRANT 'rol_admin_bd'    TO 'u_admin_bd'@'localhost';

SET DEFAULT ROLE 'rol_recepcion'   TO 'u_recepcion'@'localhost';
SET DEFAULT ROLE 'rol_medico'      TO 'u_medico'@'localhost';
SET DEFAULT ROLE 'rol_facturacion' TO 'u_facturacion'@'localhost';
SET DEFAULT ROLE 'rol_auditor'     TO 'u_auditor'@'localhost';
SET DEFAULT ROLE 'rol_admin_bd'    TO 'u_admin_bd'@'localhost';

-- ---------------------------------------------------------------------
-- SHOW GRANTS de cada usuario (USING muestra lo que el rol le da)
-- ---------------------------------------------------------------------
SHOW GRANTS FOR 'u_recepcion'@'localhost'   USING 'rol_recepcion';
SHOW GRANTS FOR 'u_medico'@'localhost'      USING 'rol_medico';
SHOW GRANTS FOR 'u_facturacion'@'localhost' USING 'rol_facturacion';
SHOW GRANTS FOR 'u_auditor'@'localhost'     USING 'rol_auditor';
SHOW GRANTS FOR 'u_admin_bd'@'localhost'    USING 'rol_admin_bd';

-- =====================================================================
-- EVIDENCIA 1 · Resultado real de SHOW GRANTS (MySQL 8.0)
-- =====================================================================
-- mysql> SHOW GRANTS FOR 'u_recepcion'@'localhost' USING 'rol_recepcion';
--   GRANT USAGE ON *.* TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`affiliations` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointment_status_history` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointment_types` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointments` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`branches` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`cancellation_reasons` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`cities` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_absences` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_branches` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_schedules` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_specialties` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctors` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`document_types` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`emergency_contacts` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`insurers` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`offices` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`patient_phones` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`patients` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`plans` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`reminders` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`specialties` TO `u_recepcion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`staff` TO `u_recepcion`@`localhost`
--   GRANT EXECUTE ON PROCEDURE `medicita_ips`.`sp_agendar_cita` TO `u_recepcion`@`localhost`
--   GRANT EXECUTE ON PROCEDURE `medicita_ips`.`sp_cancelar_cita` TO `u_recepcion`@`localhost`
--   GRANT EXECUTE ON PROCEDURE `medicita_ips`.`sp_registrar_paciente` TO `u_recepcion`@`localhost`
--   GRANT EXECUTE ON FUNCTION `medicita_ips`.`fn_medico_disponible` TO `u_recepcion`@`localhost`
--   GRANT `rol_recepcion`@`%` TO `u_recepcion`@`localhost`
--
-- mysql> SHOW GRANTS FOR 'u_medico'@'localhost' USING 'rol_medico';
--   GRANT USAGE ON *.* TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`active_ingredients` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointment_types` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointments` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`branches` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`cie10_codes` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_schedules` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctors` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`document_types` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`emergency_contacts` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`encounter_diagnoses` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`encounter_procedures` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`encounters` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`lab_order_items` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`lab_orders` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`lab_tests` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`medications` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`offices` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`patient_allergies` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`patient_phones` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`patients` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`prescription_items` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`prescriptions` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`services` TO `u_medico`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`specialties` TO `u_medico`@`localhost`
--   GRANT SELECT, INSERT, UPDATE ON `medicita_ips`.`vital_signs` TO `u_medico`@`localhost`
--   GRANT EXECUTE ON FUNCTION `medicita_ips`.`fn_edad` TO `u_medico`@`localhost`
--   GRANT EXECUTE ON FUNCTION `medicita_ips`.`fn_imc` TO `u_medico`@`localhost`
--   GRANT `rol_medico`@`%` TO `u_medico`@`localhost`
--
-- mysql> SHOW GRANTS FOR 'u_facturacion'@'localhost' USING 'rol_facturacion';
--   GRANT USAGE ON *.* TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`affiliations` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointments` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`branches` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctors` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`encounter_procedures` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`encounters` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`insurers` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`invoice_items` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`invoices` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`offices` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`patients` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`payment_methods` TO `u_facturacion`@`localhost`
--   GRANT SELECT, INSERT ON `medicita_ips`.`payments` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`plans` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`production_summaries` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`services` TO `u_facturacion`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`tariffs` TO `u_facturacion`@`localhost`
--   GRANT EXECUTE ON PROCEDURE `medicita_ips`.`sp_anular_factura` TO `u_facturacion`@`localhost`
--   GRANT EXECUTE ON PROCEDURE `medicita_ips`.`sp_facturar_atencion` TO `u_facturacion`@`localhost`
--   GRANT EXECUTE ON PROCEDURE `medicita_ips`.`sp_reporte_produccion` TO `u_facturacion`@`localhost`
--   GRANT EXECUTE ON FUNCTION `medicita_ips`.`fn_saldo_factura` TO `u_facturacion`@`localhost`
--   GRANT EXECUTE ON FUNCTION `medicita_ips`.`fn_tarifa_vigente` TO `u_facturacion`@`localhost`
--   GRANT `rol_facturacion`@`%` TO `u_facturacion`@`localhost`
--
-- mysql> SHOW GRANTS FOR 'u_auditor'@'localhost' USING 'rol_auditor';
--   GRANT USAGE ON *.* TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`active_ingredients` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`affiliations` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointment_status_history` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointment_types` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`appointments` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`branches` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`cancellation_reasons` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`cie10_codes` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`cities` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_absences` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_branches` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_schedules` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctor_specialties` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`doctors` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`document_types` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`encounter_diagnoses` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`encounter_procedures` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`encounters` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`insurers` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`invoice_items` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`invoices` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`lab_order_items` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`lab_orders` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`lab_tests` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`medications` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`offices` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`patient_allergies` TO `u_auditor`@`localhost`
--   GRANT SELECT (`birth_date`, `city_id`, `created_at`, `first_name`, `id`, `last_name`, `sex`) ON `medicita_ips`.`patients` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`payment_methods` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`payments` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`plans` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`prescription_items` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`prescriptions` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`production_summaries` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`reminders` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`satisfaction_surveys` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`services` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`specialties` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`staff` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`tariffs` TO `u_auditor`@`localhost`
--   GRANT SELECT ON `medicita_ips`.`vital_signs` TO `u_auditor`@`localhost`
--   GRANT `rol_auditor`@`%` TO `u_auditor`@`localhost`
--
-- mysql> SHOW GRANTS FOR 'u_admin_bd'@'localhost' USING 'rol_admin_bd';
--   GRANT USAGE ON *.* TO `u_admin_bd`@`localhost`
--   GRANT ALL PRIVILEGES ON `medicita_ips`.* TO `u_admin_bd`@`localhost`
--   GRANT `rol_admin_bd`@`%` TO `u_admin_bd`@`localhost`
--
-- =====================================================================
-- EVIDENCIA 2 · Acciones permitidas y denegadas por rol (ejecución real)
-- Cada bloque se ejecutó conectado como el usuario indicado:
--   mysql -u <usuario> -p medicita_ips
-- =====================================================================
--
-- ----- u_recepcion -----
-- PERMITIDA: consultar pacientes
-- u_recepcion> SELECT id, first_name, last_name FROM patients ORDER BY id LIMIT 3;
--   +----+-----------------+-----------------+
--   | id | first_name      | last_name       |
--   +----+-----------------+-----------------+
--   |  1 | Rosa Elena      | Martínez Díaz   |
--   |  2 | José Luis       | Ramírez Torres  |
--   |  3 | María Fernanda  | Peña Gil        |
--   +----+-----------------+-----------------+
-- PERMITIDA: agendar con el procedimiento
-- u_recepcion> CALL sp_agendar_cita(26, 3, 1, 1, 2, '2026-12-14 07:20:00', 2, @c); SELECT @c AS cita_creada;
--   +-------------+
--   | cita_creada |
--   +-------------+
--   |         214 |
--   +-------------+
-- DENEGADA: ver datos clínicos (1142)
-- u_recepcion> SELECT * FROM encounter_diagnoses LIMIT 1;
--   ERROR 1142 (42000) at line 1: SELECT command denied to user 'u_recepcion'@'localhost' for table 'encounter_diagnoses'
-- DENEGADA: modificar citas directamente (1142)
-- u_recepcion> UPDATE appointments SET status = 'CONFIRMADA' WHERE id = 186;
--   ERROR 1142 (42000) at line 1: UPDATE command denied to user 'u_recepcion'@'localhost' for table 'appointments'
-- DENEGADA: ejecutar un procedimiento de facturación (1370)
-- u_recepcion> CALL sp_facturar_atencion(118, '2026-11-30', @f);
--   ERROR 1370 (42000) at line 1: execute command denied to user 'u_recepcion'@'localhost' for routine 'medicita_ips.sp_facturar_atencion'
--
-- ----- u_medico -----
-- PERMITIDA: registrar signos vitales
-- u_medico> INSERT INTO vital_signs (encounter_id, taken_at, systolic_bp, diastolic_bp, heart_rate, temperature_c) VALUES (118, '2026-11-30 08:10:00', 148, 90, 76, 36.5); SELECT COUNT(*) AS tomas_atencion_118 FROM vital_signs WHERE encounter_id = 118;
--   +--------------------+
--   | tomas_atencion_118 |
--   +--------------------+
--   |                  3 |
--   +--------------------+
-- DENEGADA: ver facturación (1142)
-- u_medico> SELECT * FROM invoices LIMIT 1;
--   ERROR 1142 (42000) at line 1: SELECT command denied to user 'u_medico'@'localhost' for table 'invoices'
-- DENEGADA: borrar datos clínicos (1142)
-- u_medico> DELETE FROM vital_signs WHERE encounter_id = 118;
--   ERROR 1142 (42000) at line 1: DELETE command denied to user 'u_medico'@'localhost' for table 'vital_signs'
--
-- ----- u_facturacion -----
-- PERMITIDA: facturar con el procedimiento
-- u_facturacion> CALL sp_facturar_atencion(118, '2026-11-30', @f); SELECT id, invoice_number, total_amount, status FROM invoices WHERE id = @f;
--   +-----+----------------+--------------+-----------+
--   | id  | invoice_number | total_amount | status    |
--   +-----+----------------+--------------+-----------+
--   | 120 | FV-000119      |     52500.00 | PENDIENTE |
--   +-----+----------------+--------------+-----------+
-- PERMITIDA: registrar un abono (T-4 pasa la factura a PARCIAL)
-- u_facturacion> INSERT INTO payments (invoice_id, payment_method_id, payer, amount, paid_at) VALUES (116, 6, 'PACIENTE', 7510.00, '2026-11-30 12:00:00'); SELECT id, status FROM invoices WHERE id = 116;
--   +-----+---------+
--   | id  | status  |
--   +-----+---------+
--   | 116 | PARCIAL |
--   +-----+---------+
-- DENEGADA: ver diagnósticos (1142)
-- u_facturacion> SELECT * FROM encounter_diagnoses LIMIT 1;
--   ERROR 1142 (42000) at line 1: SELECT command denied to user 'u_facturacion'@'localhost' for table 'encounter_diagnoses'
-- DENEGADA: cambiar el estado de una factura a mano (1142)
-- u_facturacion> UPDATE invoices SET status = 'PAGADA' WHERE id = 117;
--   ERROR 1142 (42000) at line 1: UPDATE command denied to user 'u_facturacion'@'localhost' for table 'invoices'
-- DENEGADA: borrar facturas (1142)
-- u_facturacion> DELETE FROM invoices WHERE id = 117;
--   ERROR 1142 (42000) at line 1: DELETE command denied to user 'u_facturacion'@'localhost' for table 'invoices'
--
-- ----- u_auditor -----
-- PERMITIDA: leer columnas no sensibles de pacientes
-- u_auditor> SELECT id, first_name, last_name, birth_date FROM patients ORDER BY id LIMIT 3;
--   +----+-----------------+-----------------+------------+
--   | id | first_name      | last_name       | birth_date |
--   +----+-----------------+-----------------+------------+
--   |  1 | Rosa Elena      | Martínez Díaz   | 1952-03-14 |
--   |  2 | José Luis       | Ramírez Torres  | 1958-07-22 |
--   |  3 | María Fernanda  | Peña Gil        | 1990-05-10 |
--   +----+-----------------+-----------------+------------+
-- DENEGADA: leer el documento (permiso por columnas, 1143)
-- u_auditor> SELECT document_number, email FROM patients LIMIT 1;
--   ERROR 1143 (42000) at line 1: SELECT command denied to user 'u_auditor'@'localhost' for column 'document_number' in table 'patients'
-- DENEGADA: leer teléfonos de pacientes (1142)
-- u_auditor> SELECT * FROM patient_phones LIMIT 1;
--   ERROR 1142 (42000) at line 1: SELECT command denied to user 'u_auditor'@'localhost' for table 'patient_phones'
-- DENEGADA: modificar (1142)
-- u_auditor> UPDATE invoices SET status = 'PAGADA' WHERE id = 117;
--   ERROR 1142 (42000) at line 1: UPDATE command denied to user 'u_auditor'@'localhost' for table 'invoices'
--
-- ----- u_admin_bd -----
-- PERMITIDA: crear y borrar una tabla dentro de medicita_ips
-- u_admin_bd> CREATE TABLE tmp_prueba_admin (id BIGINT AUTO_INCREMENT PRIMARY KEY); DROP TABLE tmp_prueba_admin; SELECT 'OK: creó y borró una tabla en medicita_ips' AS resultado;
--   +----------------------------------------------+
--   | resultado                                    |
--   +----------------------------------------------+
--   | OK: creó y borró una tabla en medicita_ips   |
--   +----------------------------------------------+
-- DENEGADA: leer fuera de medicita_ips (1142)
-- u_admin_bd> SELECT user, host FROM mysql.user;
--   ERROR 1142 (42000) at line 1: SELECT command denied to user 'u_admin_bd'@'localhost' for table 'user'
-- DENEGADA: crear otra base de datos (1044, acceso a nivel de base)
-- u_admin_bd> CREATE DATABASE otra_base;
--   ERROR 1044 (42000) at line 1: Access denied for user 'u_admin_bd'@'localhost' to database 'otra_base'

-- =====================================================================
-- LIMPIEZA (ejecutar solo cuando se quiera retirar usuarios y roles)
-- =====================================================================
-- DROP USER IF EXISTS 'u_recepcion'@'localhost', 'u_medico'@'localhost', 'u_facturacion'@'localhost',
--                     'u_auditor'@'localhost', 'u_admin_bd'@'localhost';
-- DROP ROLE IF EXISTS 'rol_recepcion', 'rol_medico', 'rol_facturacion', 'rol_auditor', 'rol_admin_bd';
-- DROP DATABASE IF EXISTS medicita_ips;
