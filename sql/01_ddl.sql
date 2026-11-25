-- =====================================================================
-- MediCita IPS · 01_ddl.sql
-- Fase 2 · Definición de la estructura (MySQL 8)
-- Convenciones: tablas y columnas en inglés snake_case, id BIGINT
-- AUTO_INCREMENT en todas, FK sin nombre, ENUM en español MAYÚSCULAS,
-- CHECK para reglas de una fila, dinero en DECIMAL(12,2).
-- =====================================================================

DROP DATABASE IF EXISTS medicita_ips;
CREATE DATABASE medicita_ips;
USE medicita_ips;

-- =====================================================================
-- BLOQUE 1 · Organización: ciudades, sedes, consultorios
-- =====================================================================

-- 3FN: el departamento depende de la ciudad, no del paciente ni de la sede.
CREATE TABLE cities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    department VARCHAR(80) NOT NULL,
    UNIQUE (name, department)
);

CREATE TABLE branches (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(60) NOT NULL UNIQUE,
    city_id BIGINT NOT NULL,
    address VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NULL,
    FOREIGN KEY (city_id) REFERENCES cities(id)
);

-- 3FN: la sede se deduce del consultorio; por eso las citas no guardan branch_id.
CREATE TABLE offices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    branch_id BIGINT NOT NULL,
    code VARCHAR(10) NOT NULL,
    floor TINYINT NULL CHECK (floor BETWEEN -2 AND 20),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (branch_id, code),
    FOREIGN KEY (branch_id) REFERENCES branches(id)
);

-- =====================================================================
-- BLOQUE 2 · Médicos, especialidades, sedes, horarios y novedades
-- =====================================================================

CREATE TABLE specialties (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE doctors (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    medical_registry VARCHAR(20) NOT NULL UNIQUE,
    institutional_email VARCHAR(120) NOT NULL UNIQUE,
    phone VARCHAR(20) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (institutional_email LIKE '%@%.%')
);

-- 4FN (parte 1): médico ->> especialidad. RP-03 corregida: N:M.
CREATE TABLE doctor_specialties (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    specialty_id BIGINT NOT NULL,
    UNIQUE (doctor_id, specialty_id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (specialty_id) REFERENCES specialties(id)
);

-- 4FN (parte 2): médico ->> sede, independiente de la especialidad.
CREATE TABLE doctor_branches (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    branch_id BIGINT NOT NULL,
    UNIQUE (doctor_id, branch_id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (branch_id) REFERENCES branches(id)
);

-- Horario semanal. day_of_week: 1 = lunes … 7 = domingo (WEEKDAY(fecha) + 1).
CREATE TABLE doctor_schedules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    office_id BIGINT NOT NULL,
    day_of_week TINYINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    UNIQUE (doctor_id, day_of_week, start_time),
    CHECK (end_time > start_time),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (office_id) REFERENCES offices(id)
);

-- Novedades: en estas fechas no se agenda (RP-07).
CREATE TABLE doctor_absences (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    absence_type ENUM('VACACIONES', 'INCAPACIDAD', 'CAPACITACION') NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    notes VARCHAR(255) NULL,
    CHECK (end_date >= start_date),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id)
);

-- Personal que agenda, cancela o cambia estados ("quién lo hizo").
CREATE TABLE staff (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(120) NOT NULL,
    username VARCHAR(40) NOT NULL UNIQUE,
    staff_role ENUM('RECEPCION', 'MEDICO', 'FACTURACION', 'AUDITORIA', 'ADMINISTRACION', 'SISTEMA') NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- =====================================================================
-- BLOQUE 3 · Pacientes
-- =====================================================================

CREATE TABLE document_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(5) NOT NULL UNIQUE,
    name VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE patients (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_type_id BIGINT NOT NULL,
    document_number VARCHAR(20) NOT NULL,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    birth_date DATE NOT NULL CHECK (birth_date >= '1900-01-01'),
    sex ENUM('FEMENINO', 'MASCULINO', 'INTERSEXUAL') NOT NULL,
    address VARCHAR(150) NULL,
    city_id BIGINT NULL,
    email VARCHAR(120) NULL CHECK (email LIKE '%@%.%'),
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- RP-01: el número no se repite dentro del mismo tipo.
    UNIQUE (document_type_id, document_number),
    FOREIGN KEY (document_type_id) REFERENCES document_types(id),
    FOREIGN KEY (city_id) REFERENCES cities(id)
);

-- 1FN: el teléfono era multivaluado. RP-02 corregida.
-- Un solo principal por paciente, por estructura: primary_guard vale 1 si
-- es principal y NULL si no. UNIQUE no compara NULL, así que solo puede
-- existir una fila (paciente, 1).
CREATE TABLE patient_phones (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    phone_type ENUM('CELULAR', 'FIJO', 'TRABAJO') NOT NULL DEFAULT 'CELULAR',
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    primary_guard TINYINT GENERATED ALWAYS AS (CASE WHEN is_primary THEN 1 END) STORED,
    UNIQUE (patient_id, phone_number),
    UNIQUE (patient_id, primary_guard),
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);

CREATE TABLE emergency_contacts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    relationship VARCHAR(40) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);

-- =====================================================================
-- BLOQUE 4 · Aseguramiento
-- =====================================================================

CREATE TABLE insurers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    nit VARCHAR(20) NOT NULL UNIQUE,
    insurer_type ENUM('EPS', 'PREPAGADA') NOT NULL,
    phone VARCHAR(20) NULL,
    email VARCHAR(120) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Catálogo fijado por el negocio: 4 planes, particular = 100 %.
CREATE TABLE plans (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name ENUM('CONTRIBUTIVO', 'SUBSIDIADO', 'PREPAGADA', 'PARTICULAR') NOT NULL UNIQUE,
    copay_percentage DECIMAL(5,2) NOT NULL CHECK (copay_percentage BETWEEN 0 AND 100)
);

-- RP-10 corregida: historial de afiliaciones, una sola vigente.
-- active_guard aplica el mismo truco del teléfono principal: solo una
-- afiliación activa por paciente. El solapamiento de fechas compara
-- varias filas y se resuelve fuera del DDL (ver README).
CREATE TABLE affiliations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    insurer_id BIGINT NOT NULL,
    plan_id BIGINT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    active_guard TINYINT GENERATED ALWAYS AS (CASE WHEN is_active THEN 1 END) STORED,
    UNIQUE (patient_id, active_guard),
    CHECK (end_date IS NULL OR end_date >= start_date),
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (insurer_id) REFERENCES insurers(id),
    FOREIGN KEY (plan_id) REFERENCES plans(id)
);

-- =====================================================================
-- BLOQUE 5 · Agenda
-- =====================================================================

-- RP-05: el tipo de cita define la duración.
CREATE TABLE appointment_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    duration_minutes SMALLINT NOT NULL CHECK (duration_minutes IN (20, 30, 40))
);

CREATE TABLE cancellation_reasons (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- La FK compuesta (doctor_id, specialty_id) -> doctor_specialties obliga,
-- por estructura, a que la especialidad sea una que el médico tiene.
-- end_at se guarda (no se recalcula) para que un cambio futuro en la
-- duración del tipo de cita no altere citas ya agendadas.
-- RP-08 corregida: CHECK "cancelada <=> tiene motivo".
CREATE TABLE appointments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    specialty_id BIGINT NOT NULL,
    office_id BIGINT NOT NULL,
    appointment_type_id BIGINT NOT NULL,
    start_at DATETIME NOT NULL,
    end_at DATETIME NOT NULL,
    status ENUM('PROGRAMADA', 'CONFIRMADA', 'ATENDIDA', 'CANCELADA', 'NO_ASISTIO') NOT NULL DEFAULT 'PROGRAMADA',
    cancellation_reason_id BIGINT NULL,
    created_by BIGINT NOT NULL,
    updated_by BIGINT NULL,
    status_changed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_at > start_at),
    CHECK ((status = 'CANCELADA') = (cancellation_reason_id IS NOT NULL)),
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (doctor_id, specialty_id) REFERENCES doctor_specialties(doctor_id, specialty_id),
    FOREIGN KEY (specialty_id) REFERENCES specialties(id),
    FOREIGN KEY (office_id) REFERENCES offices(id),
    FOREIGN KEY (appointment_type_id) REFERENCES appointment_types(id),
    FOREIGN KEY (cancellation_reason_id) REFERENCES cancellation_reasons(id),
    FOREIGN KEY (created_by) REFERENCES staff(id),
    FOREIGN KEY (updated_by) REFERENCES staff(id)
);

CREATE INDEX idx_appointments_doctor_start ON appointments (doctor_id, start_at);
CREATE INDEX idx_appointments_office_start ON appointments (office_id, start_at);
CREATE INDEX idx_appointments_status ON appointments (status);

-- RP-09: de cuál a cuál, cuándo y quién. La llena el trigger T-3.
CREATE TABLE appointment_status_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    previous_status ENUM('PROGRAMADA', 'CONFIRMADA', 'ATENDIDA', 'CANCELADA', 'NO_ASISTIO') NULL,
    new_status ENUM('PROGRAMADA', 'CONFIRMADA', 'ATENDIDA', 'CANCELADA', 'NO_ASISTIO') NOT NULL,
    cancellation_reason_id BIGINT NULL,
    changed_at DATETIME NOT NULL,
    changed_by BIGINT NOT NULL,
    CHECK (new_status <> 'CANCELADA' OR cancellation_reason_id IS NOT NULL),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id),
    FOREIGN KEY (cancellation_reason_id) REFERENCES cancellation_reasons(id),
    FOREIGN KEY (changed_by) REFERENCES staff(id)
);

CREATE TABLE reminders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    channel ENUM('SMS', 'CORREO', 'WHATSAPP') NOT NULL,
    scheduled_for DATETIME NOT NULL,
    status ENUM('PENDIENTE', 'ENVIADO', 'FALLIDO') NOT NULL DEFAULT 'PENDIENTE',
    sent_at DATETIME NULL,
    UNIQUE (appointment_id, channel),
    CHECK (status = 'PENDIENTE' OR sent_at IS NOT NULL),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
);

-- Una encuesta por cita (UNIQUE) y calificación 1–5 (CHECK).
-- "Solo citas ATENDIDAS" compara con otra tabla: va en un trigger.
CREATE TABLE satisfaction_surveys (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE,
    score TINYINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment VARCHAR(500) NULL,
    answered_at DATETIME NOT NULL,
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
);

-- =====================================================================
-- BLOQUE 6 · Atención clínica
-- =====================================================================

-- Una atención por cita. Paciente y médico se obtienen de la cita (3FN).
CREATE TABLE encounters (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE,
    started_at DATETIME NOT NULL,
    ended_at DATETIME NULL,
    reason_for_visit VARCHAR(255) NULL,
    notes TEXT NULL,
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
);

-- Rangos posibles protegidos por CHECK (además del trigger T-1, que da
-- un mensaje claro en español antes de que actúe el CHECK).
CREATE TABLE vital_signs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    encounter_id BIGINT NOT NULL,
    taken_at DATETIME NOT NULL,
    systolic_bp SMALLINT NOT NULL CHECK (systolic_bp BETWEEN 60 AND 260),
    diastolic_bp SMALLINT NOT NULL CHECK (diastolic_bp BETWEEN 30 AND 160),
    heart_rate SMALLINT NULL CHECK (heart_rate BETWEEN 20 AND 250),
    temperature_c DECIMAL(4,1) NULL CHECK (temperature_c BETWEEN 30 AND 45),
    weight_kg DECIMAL(5,2) NULL CHECK (weight_kg > 0 AND weight_kg <= 400),
    height_cm DECIMAL(5,1) NULL CHECK (height_cm > 0 AND height_cm <= 250),
    CHECK (diastolic_bp < systolic_bp),
    FOREIGN KEY (encounter_id) REFERENCES encounters(id)
);

CREATE TABLE cie10_codes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE,
    description VARCHAR(200) NOT NULL
);

-- Un diagnóstico no se repite en la atención; a lo sumo uno principal.
CREATE TABLE encounter_diagnoses (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    encounter_id BIGINT NOT NULL,
    cie10_id BIGINT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    primary_guard TINYINT GENERATED ALWAYS AS (CASE WHEN is_primary THEN 1 END) STORED,
    UNIQUE (encounter_id, cie10_id),
    UNIQUE (encounter_id, primary_guard),
    FOREIGN KEY (encounter_id) REFERENCES encounters(id),
    FOREIGN KEY (cie10_id) REFERENCES cie10_codes(id)
);

-- Servicios CUPS: se usan como procedimientos y como renglones de factura.
CREATE TABLE services (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cups_code VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE encounter_procedures (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    encounter_id BIGINT NOT NULL,
    service_id BIGINT NOT NULL,
    quantity SMALLINT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    UNIQUE (encounter_id, service_id),
    FOREIGN KEY (encounter_id) REFERENCES encounters(id),
    FOREIGN KEY (service_id) REFERENCES services(id)
);

-- =====================================================================
-- BLOQUE 7 · Medicamentos, alergias y fórmulas
-- =====================================================================

CREATE TABLE active_ingredients (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE medications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    active_ingredient_id BIGINT NOT NULL,
    concentration VARCHAR(40) NOT NULL,
    pharmaceutical_form VARCHAR(40) NOT NULL,
    UNIQUE (name, concentration, pharmaceutical_form),
    FOREIGN KEY (active_ingredient_id) REFERENCES active_ingredients(id)
);

-- RP-12: la alergia se registra contra el principio activo, no la marca.
CREATE TABLE patient_allergies (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    active_ingredient_id BIGINT NOT NULL,
    reaction VARCHAR(150) NULL,
    severity ENUM('LEVE', 'MODERADA', 'SEVERA') NOT NULL,
    recorded_at DATE NOT NULL,
    UNIQUE (patient_id, active_ingredient_id),
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (active_ingredient_id) REFERENCES active_ingredients(id)
);

CREATE TABLE prescriptions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    encounter_id BIGINT NOT NULL,
    issued_at DATETIME NOT NULL,
    notes VARCHAR(255) NULL,
    FOREIGN KEY (encounter_id) REFERENCES encounters(id)
);

-- El cruce contra alergias lo hace el trigger T-5.
CREATE TABLE prescription_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    prescription_id BIGINT NOT NULL,
    medication_id BIGINT NOT NULL,
    dose VARCHAR(60) NOT NULL,
    frequency_hours SMALLINT NOT NULL CHECK (frequency_hours BETWEEN 1 AND 72),
    duration_days SMALLINT NOT NULL CHECK (duration_days BETWEEN 1 AND 365),
    instructions VARCHAR(255) NULL,
    UNIQUE (prescription_id, medication_id),
    FOREIGN KEY (prescription_id) REFERENCES prescriptions(id),
    FOREIGN KEY (medication_id) REFERENCES medications(id)
);

-- =====================================================================
-- BLOQUE 8 · Laboratorio
-- =====================================================================

-- 2FN: unidad y rango dependen solo del examen, no del renglón de la orden.
CREATE TABLE lab_tests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    unit VARCHAR(20) NOT NULL,
    reference_min DECIMAL(10,2) NOT NULL,
    reference_max DECIMAL(10,2) NOT NULL,
    CHECK (reference_max > reference_min)
);

CREATE TABLE lab_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    encounter_id BIGINT NOT NULL,
    ordered_at DATETIME NOT NULL,
    notes VARCHAR(255) NULL,
    FOREIGN KEY (encounter_id) REFERENCES encounters(id)
);

-- Resultado y fecha van juntos: ambos nulos o ambos con valor.
CREATE TABLE lab_order_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    lab_order_id BIGINT NOT NULL,
    lab_test_id BIGINT NOT NULL,
    result_value DECIMAL(10,2) NULL,
    resulted_at DATETIME NULL,
    UNIQUE (lab_order_id, lab_test_id),
    CHECK ((result_value IS NULL) = (resulted_at IS NULL)),
    FOREIGN KEY (lab_order_id) REFERENCES lab_orders(id),
    FOREIGN KEY (lab_test_id) REFERENCES lab_tests(id)
);

-- =====================================================================
-- BLOQUE 9 · Tarifas, facturación y cartera
-- =====================================================================

-- RP-13 corregida: el precio depende del servicio, el plan y la vigencia.
CREATE TABLE tariffs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    service_id BIGINT NOT NULL,
    plan_id BIGINT NOT NULL,
    price DECIMAL(12,2) NOT NULL CHECK (price > 0),
    valid_from DATE NOT NULL,
    valid_to DATE NULL,
    UNIQUE (service_id, plan_id, valid_from),
    CHECK (valid_to IS NULL OR valid_to > valid_from),
    FOREIGN KEY (service_id) REFERENCES services(id),
    FOREIGN KEY (plan_id) REFERENCES plans(id)
);

CREATE TABLE payment_methods (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(40) NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Una factura por atención (UNIQUE encounter_id), incluso si se anula.
-- plan_id e insurer_id son la foto del aseguramiento al facturar:
-- si el paciente cambia de EPS, la factura vieja no cambia.
-- insurer_id NULL = particular.
-- RP-14 corregida: no se borra; ANULADA exige fecha y motivo.
CREATE TABLE invoices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_number VARCHAR(20) NOT NULL UNIQUE,
    encounter_id BIGINT NOT NULL UNIQUE,
    issued_at DATE NOT NULL,
    plan_id BIGINT NOT NULL,
    insurer_id BIGINT NULL,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    patient_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (patient_amount >= 0),
    insurer_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (insurer_amount >= 0),
    status ENUM('PENDIENTE', 'PARCIAL', 'PAGADA', 'VENCIDA', 'ANULADA') NOT NULL DEFAULT 'PENDIENTE',
    voided_at DATE NULL,
    void_reason VARCHAR(255) NULL,
    CHECK (patient_amount + insurer_amount = total_amount),
    CHECK ((status = 'ANULADA') = (voided_at IS NOT NULL)),
    CHECK (status <> 'ANULADA' OR (void_reason IS NOT NULL AND TRIM(void_reason) <> '')),
    FOREIGN KEY (encounter_id) REFERENCES encounters(id),
    FOREIGN KEY (plan_id) REFERENCES plans(id),
    FOREIGN KEY (insurer_id) REFERENCES insurers(id)
);

-- El precio se COPIA del día de la atención (no es FK a la tarifa).
-- line_total es columna generada: no se puede desincronizar.
CREATE TABLE invoice_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    service_id BIGINT NOT NULL,
    quantity SMALLINT NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    UNIQUE (invoice_id, service_id),
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (service_id) REFERENCES services(id)
);

-- Abonos: varios por factura, distintos medios, siempre > 0.
CREATE TABLE payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    payment_method_id BIGINT NOT NULL,
    payer ENUM('PACIENTE', 'ASEGURADORA') NOT NULL,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    paid_at DATETIME NOT NULL,
    reference VARCHAR(60) NULL,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (payment_method_id) REFERENCES payment_methods(id)
);

-- Resumen mensual que llena el evento E-5.
CREATE TABLE production_summaries (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    period_year SMALLINT NOT NULL CHECK (period_year BETWEEN 2020 AND 2100),
    period_month TINYINT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    encounters_count INT NOT NULL CHECK (encounters_count >= 0),
    billed_amount DECIMAL(12,2) NOT NULL CHECK (billed_amount >= 0),
    generated_at DATETIME NOT NULL,
    UNIQUE (doctor_id, period_year, period_month),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id)
);

-- Verificación rápida: deben aparecer 43 tablas.
SELECT COUNT(*) AS total_tablas
FROM information_schema.tables
WHERE table_schema = 'medicita_ips';
