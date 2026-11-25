-- =====================================================================
-- MediCita IPS · 03_dql.sql
-- Fase 4 · 30 consultas
-- Fecha de corte: 2026-11-30. "Hasta el corte" incluye todo ese día,
-- por eso se compara con start_at < '2026-12-01'.
-- Vigente al corte: start_date <= '2026-11-30' AND (end_date IS NULL OR end_date >= '2026-11-30').
-- =====================================================================

USE medicita_ips;

-- =====================================================================
-- UNA TABLA (1–8)
-- =====================================================================

-- Q1. Negocio: pacientes nacidos antes de 1960, del mayor al menor.
-- Técnica: filtro por fecha y orden ascendente por fecha de nacimiento
-- (la fecha más antigua es la persona mayor).
SELECT document_number AS documento,
       CONCAT(first_name, ' ', last_name) AS nombre_completo,
       birth_date AS fecha_nacimiento
FROM patients
WHERE birth_date < '1960-01-01'
ORDER BY birth_date ASC;

-- Q2. Negocio: médicos activos con registro y correo, por apellido.
-- Técnica: filtro booleano y orden por dos columnas.
SELECT last_name AS apellidos, first_name AS nombres,
       medical_registry AS registro_medico, institutional_email AS correo
FROM doctors
WHERE is_active = TRUE
ORDER BY last_name, first_name;

-- Q3. Negocio: citas que inician entre el 1 y el 7 de diciembre, incluido todo el 7.
-- Técnica: rango semiabierto [2026-12-01, 2026-12-08) para no perder
-- las citas del 7 después de las 00:00 (BETWEEN '...-07' las cortaría).
SELECT id AS cita, patient_id AS paciente, doctor_id AS medico,
       DATE(start_at) AS fecha, TIME(start_at) AS hora, status AS estado
FROM appointments
WHERE start_at >= '2026-12-01' AND start_at < '2026-12-08'
ORDER BY start_at;

-- Q4. Negocio: exámenes medidos en mg/dL con su rango de referencia.
-- Técnica: filtro por igualdad.
SELECT name AS examen, unit AS unidad, reference_min AS minimo, reference_max AS maximo
FROM lab_tests
WHERE unit = 'mg/dL'
ORDER BY name;

-- Q5. Negocio: cuántas citas hay en cada estado, de la más a la menos frecuente.
-- Técnica: GROUP BY con COUNT y orden por el agregado.
SELECT status AS estado, COUNT(*) AS total_citas
FROM appointments
GROUP BY status
ORDER BY total_citas DESC;

-- Q6. Negocio: facturas de noviembre con total mayor a 150.000, de mayor a menor.
-- Técnica: filtro por rango de fechas y monto. Se excluyen las ANULADAS
-- porque una factura anulada ya no representa un cobro.
SELECT invoice_number AS factura, issued_at AS fecha_emision,
       total_amount AS total, status AS estado
FROM invoices
WHERE issued_at >= '2026-11-01' AND issued_at < '2026-12-01'
  AND total_amount > 150000
  AND status <> 'ANULADA'
ORDER BY total_amount DESC;

-- Q7. Negocio: pacientes sin correo registrado.
-- Técnica: IS NULL (no "= NULL", que nunca es verdadero).
SELECT document_number AS documento,
       CONCAT(first_name, ' ', last_name) AS nombre_completo
FROM patients
WHERE email IS NULL
ORDER BY last_name;

-- Q8. Negocio: los 5 servicios con la tarifa vigente al corte más alta para PARTICULAR.
-- Técnica: filtro de vigencia con fin abierto (NULL) y LIMIT.
-- plan_id = 4 es PARTICULAR (catálogo fijo cargado en 02_dml.sql).
SELECT service_id AS servicio, price AS tarifa, valid_from AS vigente_desde
FROM tariffs
WHERE plan_id = 4
  AND valid_from <= '2026-11-30'
  AND (valid_to IS NULL OR valid_to >= '2026-11-30')
ORDER BY price DESC
LIMIT 5;

-- =====================================================================
-- JOINS (9–15)
-- =====================================================================

-- Q9. Negocio: agenda del martes 1 de diciembre.
-- Técnica: INNER JOIN de cinco tablas. Se excluyen las canceladas
-- porque ya no ocupan la agenda.
SELECT TIME(a.start_at) AS hora,
       CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       CONCAT(d.first_name, ' ', d.last_name) AS medico,
       s.name AS especialidad,
       o.code AS consultorio,
       b.name AS sede
FROM appointments a
JOIN patients p    ON p.id = a.patient_id
JOIN doctors d     ON d.id = a.doctor_id
JOIN specialties s ON s.id = a.specialty_id
JOIN offices o     ON o.id = a.office_id
JOIN branches b    ON b.id = o.branch_id
WHERE a.start_at >= '2026-12-01' AND a.start_at < '2026-12-02'
  AND a.status <> 'CANCELADA'
ORDER BY a.start_at, b.name;

-- Q10. Negocio: cada paciente con su afiliación vigente al corte.
-- Técnica: INNER JOIN, los pacientes sin afiliación vigente quedan por
-- fuera de forma natural (el paciente 20 terminó el 2026-11-15).
SELECT CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       i.name AS aseguradora, pl.name AS plan,
       af.start_date AS inicio, af.end_date AS fin
FROM patients p
JOIN affiliations af ON af.patient_id = p.id
JOIN insurers i      ON i.id = af.insurer_id
JOIN plans pl        ON pl.id = af.plan_id
WHERE af.start_date <= '2026-11-30'
  AND (af.end_date IS NULL OR af.end_date >= '2026-11-30')
ORDER BY p.last_name;

-- Q11. Negocio: cada médico con sus especialidades y sedes, una fila por combinación.
-- Técnica: JOIN de doctor_specialties con doctor_branches por médico.
-- Reconstruye el producto que la 4FN separó: Pabón da 2 x 2 = 4 filas.
SELECT CONCAT(d.first_name, ' ', d.last_name) AS medico,
       s.name AS especialidad, b.name AS sede
FROM doctors d
JOIN doctor_specialties ds ON ds.doctor_id = d.id
JOIN specialties s         ON s.id = ds.specialty_id
JOIN doctor_branches db    ON db.doctor_id = d.id
JOIN branches b            ON b.id = db.branch_id
ORDER BY d.last_name, s.name, b.name;

-- Q12. Negocio: diagnósticos principales de las atenciones de noviembre.
-- Técnica: JOIN atención -> cita -> paciente/médico y filtro is_primary.
SELECT DATE(e.started_at) AS fecha,
       CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       CONCAT(d.first_name, ' ', d.last_name) AS medico,
       c.code AS codigo_cie10, c.description AS diagnostico
FROM encounters e
JOIN appointments a         ON a.id = e.appointment_id
JOIN patients p             ON p.id = a.patient_id
JOIN doctors d              ON d.id = a.doctor_id
JOIN encounter_diagnoses ed ON ed.encounter_id = e.id AND ed.is_primary = TRUE
JOIN cie10_codes c          ON c.id = ed.cie10_id
WHERE e.started_at >= '2026-11-01' AND e.started_at < '2026-12-01'
ORDER BY e.started_at;

-- Q13. Negocio: fórmulas emitidas con su detalle.
-- Técnica: JOIN de siete tablas, de la fórmula al principio activo.
SELECT DATE(rx.issued_at) AS fecha,
       CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       CONCAT(d.first_name, ' ', d.last_name) AS medico,
       m.name AS medicamento, ai.name AS principio_activo,
       pi.dose AS dosis, CONCAT('Cada ', pi.frequency_hours, ' h') AS frecuencia,
       pi.duration_days AS dias
FROM prescriptions rx
JOIN prescription_items pi  ON pi.prescription_id = rx.id
JOIN medications m          ON m.id = pi.medication_id
JOIN active_ingredients ai  ON ai.id = m.active_ingredient_id
JOIN encounters e           ON e.id = rx.encounter_id
JOIN appointments a         ON a.id = e.appointment_id
JOIN patients p             ON p.id = a.patient_id
JOIN doctors d              ON d.id = a.doctor_id
ORDER BY rx.issued_at, paciente;

-- Q14. Negocio: resultados de laboratorio fuera del rango de referencia.
-- Técnica: JOIN y comparación entre columnas de dos tablas (resultado
-- contra el rango del examen). Los pendientes (NULL) no salen.
SELECT CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       t.name AS examen, li.result_value AS valor, t.unit AS unidad,
       t.reference_min AS minimo, t.reference_max AS maximo
FROM lab_order_items li
JOIN lab_tests t     ON t.id = li.lab_test_id
JOIN lab_orders lo   ON lo.id = li.lab_order_id
JOIN encounters e    ON e.id = lo.encounter_id
JOIN appointments a  ON a.id = e.appointment_id
JOIN patients p      ON p.id = a.patient_id
WHERE li.result_value < t.reference_min OR li.result_value > t.reference_max
ORDER BY paciente, t.name;

-- Q15. Negocio: citas canceladas con su motivo, quién y cuándo, según el historial.
-- Técnica: JOIN del historial con el motivo y el personal responsable.
SELECT h.appointment_id AS cita,
       CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       r.name AS motivo,
       st.full_name AS cancelada_por,
       h.changed_at AS fecha_cancelacion
FROM appointment_status_history h
JOIN appointments a          ON a.id = h.appointment_id
JOIN patients p              ON p.id = a.patient_id
JOIN cancellation_reasons r  ON r.id = h.cancellation_reason_id
JOIN staff st                ON st.id = h.changed_by
WHERE h.new_status = 'CANCELADA'
ORDER BY h.changed_at;

-- =====================================================================
-- AGREGACIÓN Y LEFT JOIN (16–20)
-- =====================================================================

-- Q16. Negocio: atenciones por especialidad y mes, solo combinaciones con 3 o más.
-- Técnica: GROUP BY por dos expresiones y HAVING sobre el conteo.
SELECT s.name AS especialidad,
       DATE_FORMAT(e.started_at, '%Y-%m') AS mes,
       COUNT(*) AS atenciones
FROM encounters e
JOIN appointments a ON a.id = e.appointment_id
JOIN specialties s  ON s.id = a.specialty_id
GROUP BY s.name, DATE_FORMAT(e.started_at, '%Y-%m')
HAVING COUNT(*) >= 3
ORDER BY mes, atenciones DESC;

-- Q17. Negocio: médicos activos sin ninguna cita en diciembre de 2026.
-- Técnica: anti-join con LEFT JOIN, la condición de diciembre va en el ON,
-- no en el WHERE, para no convertir el LEFT JOIN en INNER JOIN.
SELECT CONCAT(d.first_name, ' ', d.last_name) AS medico,
       d.medical_registry AS registro_medico
FROM doctors d
LEFT JOIN appointments a
       ON a.doctor_id = d.id
      AND a.start_at >= '2026-12-01' AND a.start_at < '2027-01-01'
WHERE d.is_active = TRUE
  AND a.id IS NULL
ORDER BY d.last_name;

-- Q18. Negocio: % de inasistencia por sede sobre las citas hasta el corte (incluye canceladas).
-- Técnica: agregación condicional SUM(status = 'NO_ASISTIO') dividida
-- entre el total, LEFT JOIN para no perder sedes sin citas.
SELECT b.name AS sede,
       COUNT(a.id) AS citas_hasta_corte,
       SUM(a.status = 'NO_ASISTIO') AS inasistencias,
       ROUND(100 * SUM(a.status = 'NO_ASISTIO') / NULLIF(COUNT(a.id), 0), 2) AS porcentaje_inasistencia
FROM branches b
LEFT JOIN offices o       ON o.branch_id = b.id
LEFT JOIN appointments a  ON a.office_id = o.id AND a.start_at < '2026-12-01'
GROUP BY b.id, b.name
ORDER BY porcentaje_inasistencia DESC;

-- Q19. Negocio: por aseguradora, total facturado (sin anuladas), total abonado y saldo.
-- Técnica: se agrega ANTES de unir (tablas derivadas). Si se uniera
-- facturas con abonos y luego se sumara, el total de una factura con
-- dos abonos se contaría dos veces.
SELECT i.name AS aseguradora,
       CAST(COALESCE(f.facturado, 0) AS DECIMAL(12,2)) AS total_facturado,
       CAST(COALESCE(ab.abonado, 0) AS DECIMAL(12,2)) AS total_abonado,
       CAST(COALESCE(f.facturado, 0) - COALESCE(ab.abonado, 0) AS DECIMAL(12,2)) AS saldo
FROM insurers i
LEFT JOIN (SELECT insurer_id, SUM(total_amount) AS facturado
           FROM invoices
           WHERE status <> 'ANULADA'
           GROUP BY insurer_id) f ON f.insurer_id = i.id
LEFT JOIN (SELECT inv.insurer_id, SUM(pay.amount) AS abonado
           FROM payments pay
           JOIN invoices inv ON inv.id = pay.invoice_id
           WHERE inv.status <> 'ANULADA'
           GROUP BY inv.insurer_id) ab ON ab.insurer_id = i.id
ORDER BY saldo DESC;

-- Q20. Negocio: promedio de satisfacción por médico (2 o más encuestas), del mejor al peor.
-- Técnica: AVG con HAVING sobre COUNT.
SELECT CONCAT(d.first_name, ' ', d.last_name) AS medico,
       ROUND(AVG(sv.score), 2) AS promedio_satisfaccion,
       COUNT(*) AS encuestas
FROM satisfaction_surveys sv
JOIN appointments a ON a.id = sv.appointment_id
JOIN doctors d      ON d.id = a.doctor_id
GROUP BY d.id, d.first_name, d.last_name
HAVING COUNT(*) >= 2
ORDER BY promedio_satisfaccion DESC, encuestas DESC;

-- =====================================================================
-- SUBCONSULTAS (21–30)
-- =====================================================================

-- Q21. Negocio: pacientes cuyo número de citas supera el promedio por paciente.
-- Técnica: subconsulta escalar en el HAVING. El promedio se toma sobre
-- todos los pacientes (incluidos los que tienen 0 citas).
SELECT CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       COUNT(a.id) AS citas
FROM patients p
JOIN appointments a ON a.patient_id = p.id
GROUP BY p.id, p.first_name, p.last_name
HAVING COUNT(a.id) > (SELECT COUNT(*) / (SELECT COUNT(*) FROM patients) FROM appointments)
ORDER BY citas DESC;

-- Q22. Negocio: médicos que han atendido al paciente con más atenciones (con empates).
-- Técnica: subconsulta anidada: el máximo de atenciones por paciente, los
-- pacientes que lo alcanzan (IN admite varios por empate) y sus médicos.
SELECT DISTINCT CONCAT(d.first_name, ' ', d.last_name) AS medico,
       CONCAT(p.first_name, ' ', p.last_name) AS paciente
FROM encounters e
JOIN appointments a ON a.id = e.appointment_id
JOIN doctors d      ON d.id = a.doctor_id
JOIN patients p     ON p.id = a.patient_id
WHERE a.patient_id IN (
        SELECT a2.patient_id
        FROM encounters e2
        JOIN appointments a2 ON a2.id = e2.appointment_id
        GROUP BY a2.patient_id
        HAVING COUNT(*) = (SELECT MAX(n)
                           FROM (SELECT COUNT(*) AS n
                                 FROM encounters e3
                                 JOIN appointments a3 ON a3.id = e3.appointment_id
                                 GROUP BY a3.patient_id) t))
ORDER BY paciente, medico;

-- Q23. Negocio: consultorios que nunca han tenido una cita.
-- Técnica: NOT EXISTS correlacionado.
SELECT b.name AS sede, o.code AS consultorio
FROM offices o
JOIN branches b ON b.id = o.branch_id
WHERE NOT EXISTS (SELECT 1 FROM appointments a WHERE a.office_id = o.id)
ORDER BY b.name, o.code;

-- Q24. Negocio: pacientes con alergia que tienen fórmulas, para revisar choques.
-- Técnica: dos EXISTS correlacionados, la columna choques_con_alergia
-- (subconsulta escalar) debe dar 0 en todos gracias al trigger T-5.
SELECT CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       (SELECT GROUP_CONCAT(ai.name ORDER BY ai.name SEPARATOR ', ')
          FROM patient_allergies pa
          JOIN active_ingredients ai ON ai.id = pa.active_ingredient_id
         WHERE pa.patient_id = p.id) AS alergias,
       (SELECT COUNT(*)
          FROM prescription_items pi
          JOIN prescriptions rx ON rx.id = pi.prescription_id
          JOIN encounters e     ON e.id = rx.encounter_id
          JOIN appointments a   ON a.id = e.appointment_id
          JOIN medications m    ON m.id = pi.medication_id
          JOIN patient_allergies pa ON pa.patient_id = a.patient_id
                                   AND pa.active_ingredient_id = m.active_ingredient_id
         WHERE a.patient_id = p.id) AS choques_con_alergia
FROM patients p
WHERE EXISTS (SELECT 1 FROM patient_allergies pa WHERE pa.patient_id = p.id)
  AND EXISTS (SELECT 1
                FROM prescriptions rx
                JOIN encounters e   ON e.id = rx.encounter_id
                JOIN appointments a ON a.id = e.appointment_id
               WHERE a.patient_id = p.id)
ORDER BY paciente;

-- Q25. Negocio: por especialidad, el médico con más atenciones (con empates).
-- Técnica: tabla derivada con los conteos y subconsulta correlacionada
-- que busca el máximo de la misma especialidad.
SELECT s.name AS especialidad,
       CONCAT(d.first_name, ' ', d.last_name) AS medico,
       c.atenciones
FROM (SELECT a.specialty_id, a.doctor_id, COUNT(*) AS atenciones
      FROM encounters e
      JOIN appointments a ON a.id = e.appointment_id
      GROUP BY a.specialty_id, a.doctor_id) c
JOIN specialties s ON s.id = c.specialty_id
JOIN doctors d     ON d.id = c.doctor_id
WHERE c.atenciones = (SELECT MAX(c2.atenciones)
                      FROM (SELECT a2.specialty_id, COUNT(*) AS atenciones
                            FROM encounters e2
                            JOIN appointments a2 ON a2.id = e2.appointment_id
                            GROUP BY a2.specialty_id, a2.doctor_id) c2
                      WHERE c2.specialty_id = c.specialty_id)
ORDER BY s.name, medico;

-- Q26. Negocio: facturas cuyo total supera el promedio de su misma aseguradora.
-- Técnica: subconsulta correlacionada. Se usa <=> (igualdad segura con
-- NULL) para que las facturas particulares (insurer_id NULL) se comparen
-- con el promedio de las particulares.
SELECT inv.invoice_number AS factura,
       COALESCE(i.name, 'PARTICULAR') AS aseguradora,
       inv.total_amount AS total,
       CAST((SELECT AVG(i2.total_amount)
               FROM invoices i2
              WHERE i2.insurer_id <=> inv.insurer_id
                AND i2.status <> 'ANULADA') AS DECIMAL(12,2)) AS promedio_aseguradora
FROM invoices inv
LEFT JOIN insurers i ON i.id = inv.insurer_id
WHERE inv.status <> 'ANULADA'
  AND inv.total_amount > (SELECT AVG(i2.total_amount)
                            FROM invoices i2
                           WHERE i2.insurer_id <=> inv.insurer_id
                             AND i2.status <> 'ANULADA')
ORDER BY aseguradora, total DESC;

-- Q27. Negocio: producción por sede en noviembre y su participación sobre la IPS.
-- Técnica: subconsultas en el FROM: una por sede y otra con el gran total.
SELECT ps.sede,
       ps.total_facturado,
       ROUND(100 * ps.total_facturado / tot.total_ips, 2) AS participacion_pct
FROM (SELECT b.name AS sede, CAST(SUM(inv.total_amount) AS DECIMAL(12,2)) AS total_facturado
      FROM invoices inv
      JOIN encounters e   ON e.id = inv.encounter_id
      JOIN appointments a ON a.id = e.appointment_id
      JOIN offices o      ON o.id = a.office_id
      JOIN branches b     ON b.id = o.branch_id
      WHERE inv.status <> 'ANULADA'
        AND inv.issued_at >= '2026-11-01' AND inv.issued_at < '2026-12-01'
      GROUP BY b.name) ps
CROSS JOIN (SELECT SUM(total_amount) AS total_ips
            FROM invoices
            WHERE status <> 'ANULADA'
              AND issued_at >= '2026-11-01' AND issued_at < '2026-12-01') tot
ORDER BY ps.total_facturado DESC;

-- Q28. Negocio: última cita de cada paciente hasta el corte y días transcurridos.
-- Técnica: subconsulta correlacionada con MAX por paciente, las citas
-- futuras quedan fuera con start_at < '2026-12-01'.
SELECT CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       a.start_at AS ultima_cita,
       a.status AS estado,
       DATEDIFF('2026-11-30', DATE(a.start_at)) AS dias_hasta_corte
FROM appointments a
JOIN patients p ON p.id = a.patient_id
WHERE a.start_at = (SELECT MAX(a2.start_at)
                    FROM appointments a2
                    WHERE a2.patient_id = a.patient_id
                      AND a2.start_at < '2026-12-01')
ORDER BY dias_hasta_corte DESC, paciente;

-- Q29. Negocio: hipertensos (I10) cuya última sistólica registrada es 140 o más.
-- Técnica: EXISTS para el diagnóstico y subconsulta correlacionada con
-- MAX(taken_at) para la última toma de presión del paciente.
SELECT CONCAT(p.first_name, ' ', p.last_name) AS paciente,
       vs.taken_at AS ultima_toma,
       vs.systolic_bp AS sistolica,
       vs.diastolic_bp AS diastolica
FROM patients p
JOIN appointments a ON a.patient_id = p.id
JOIN encounters e   ON e.appointment_id = a.id
JOIN vital_signs vs ON vs.encounter_id = e.id
WHERE EXISTS (SELECT 1
                FROM encounter_diagnoses ed
                JOIN cie10_codes c  ON c.id = ed.cie10_id AND c.code = 'I10'
                JOIN encounters e2  ON e2.id = ed.encounter_id
                JOIN appointments a2 ON a2.id = e2.appointment_id
               WHERE a2.patient_id = p.id)
  AND vs.taken_at = (SELECT MAX(vs2.taken_at)
                       FROM vital_signs vs2
                       JOIN encounters e3   ON e3.id = vs2.encounter_id
                       JOIN appointments a3 ON a3.id = e3.appointment_id
                      WHERE a3.patient_id = p.id)
  AND vs.systolic_bp >= 140
ORDER BY vs.systolic_bp DESC;

-- Q30. Negocio: los 3 diagnósticos más frecuentes de cada sede, con su posición.
-- Técnica: CTE + ROW_NUMBER() OVER (PARTITION BY sede ORDER BY frecuencia
-- DESC, código ASC). Se usa ROW_NUMBER y no RANK porque el negocio pide
-- desempatar por el menor código: así cada sede tiene exactamente 3 puestos.
WITH frecuencias AS (
    SELECT b.name AS sede, c.code, c.description, COUNT(*) AS frecuencia
    FROM encounter_diagnoses ed
    JOIN cie10_codes c  ON c.id = ed.cie10_id
    JOIN encounters e   ON e.id = ed.encounter_id
    JOIN appointments a ON a.id = e.appointment_id
    JOIN offices o      ON o.id = a.office_id
    JOIN branches b     ON b.id = o.branch_id
    GROUP BY b.name, c.code, c.description
),
ranking AS (
    SELECT sede, code, description, frecuencia,
           ROW_NUMBER() OVER (PARTITION BY sede ORDER BY frecuencia DESC, code ASC) AS posicion
    FROM frecuencias
)
SELECT sede, posicion, code AS codigo_cie10, description AS diagnostico, frecuencia
FROM ranking
WHERE posicion <= 3
ORDER BY sede, posicion;
