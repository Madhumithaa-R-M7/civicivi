-- Migration 002: Enterprise Schema Expansion for CivicConnect
-- Adds departments, staff_profiles, complaint_images, complaint_assignments,
-- status_history, sla_records, audit_logs, and auth_sessions.

-- 1. Update users role check and add missing columns if needed
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_role'
    ) THEN
        ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_role;
        ALTER TABLE users ADD CONSTRAINT chk_users_role 
            CHECK (role IN ('user', 'staff', 'admin', 'super_admin'));
    END IF;
END $$;

-- 2. Departments table
CREATE TABLE IF NOT EXISTS departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    code VARCHAR(20) NOT NULL UNIQUE,
    description TEXT,
    contact_email VARCHAR(150),
    contact_phone VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Seed core municipal departments
INSERT INTO departments (name, code, description, contact_email, contact_phone)
VALUES 
    ('Roads & Traffic', 'ROADS', 'Management of potholes, asphalt resurfacing, road signs, and traffic equipment', 'roads@civicconnect.gov', '+91-22-2410-0001'),
    ('Cleanliness & Waste Management', 'SANITATION', 'Garbage collection, overflowing dumpsters, and street sweeping', 'sanitation@civicconnect.gov', '+91-22-2410-0002'),
    ('Water Supply & Drainage', 'WATER', 'Water pipeline leakages, low pressure, blocked stormwater drains and sewage', 'water@civicconnect.gov', '+91-22-2410-0003'),
    ('Street & Public Lighting', 'LIGHTING', 'Damaged streetlights, dark public alleys, and exposed electrical hazards', 'lighting@civicconnect.gov', '+91-22-2410-0004'),
    ('Public Infrastructure & Facilities', 'PUBLIC_WORKS', 'Public toilets, bus shelters, parks, footpaths, and civic structures', 'facilities@civicconnect.gov', '+91-22-2410-0005')
ON CONFLICT (code) DO NOTHING;

-- 3. Staff Profiles table
CREATE TABLE IF NOT EXISTS staff_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    department_id INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    employee_id VARCHAR(50) UNIQUE,
    skills TEXT[] DEFAULT '{}',
    jurisdiction VARCHAR(100) DEFAULT 'All',
    is_available BOOLEAN DEFAULT TRUE,
    max_capacity INTEGER DEFAULT 5,
    current_load INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Extend complaints table with enterprise columns
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS department_id INTEGER REFERENCES departments(id) ON DELETE SET NULL;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS priority_score DOUBLE PRECISION DEFAULT 50.0;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS sla_status VARCHAR(50) DEFAULT 'ON_TRACK';
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS duplicate_of_id INTEGER REFERENCES complaints(id) ON DELETE SET NULL;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS duplicate_score DOUBLE PRECISION;

-- 5. Complaint Images table (for multiple photos, SHA-256 integrity & pHash)
CREATE TABLE IF NOT EXISTS complaint_images (
    id SERIAL PRIMARY KEY,
    complaint_id INTEGER NOT NULL REFERENCES complaints(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size INTEGER,
    mime_type VARCHAR(50),
    sha256_hash VARCHAR(64),
    phash VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. Complaint Assignments table (tracking MCDA assignments)
CREATE TABLE IF NOT EXISTS complaint_assignments (
    id SERIAL PRIMARY KEY,
    complaint_id INTEGER NOT NULL REFERENCES complaints(id) ON DELETE CASCADE,
    staff_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    department_id INTEGER REFERENCES departments(id) ON DELETE SET NULL,
    assigned_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    assignment_score DOUBLE PRECISION DEFAULT 0.0,
    assignment_method VARCHAR(50) DEFAULT 'manual', -- 'manual', 'algorithmic_mcda', 'reassigned'
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. Status History table (Finite-State Machine audit trail)
CREATE TABLE IF NOT EXISTS status_history (
    id SERIAL PRIMARY KEY,
    complaint_id INTEGER NOT NULL REFERENCES complaints(id) ON DELETE CASCADE,
    from_status VARCHAR(50) NOT NULL,
    to_status VARCHAR(50) NOT NULL,
    changed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    reason TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. SLA Records table (tracking resolution deadlines & escalations)
CREATE TABLE IF NOT EXISTS sla_records (
    id SERIAL PRIMARY KEY,
    complaint_id INTEGER NOT NULL REFERENCES complaints(id) ON DELETE CASCADE UNIQUE,
    response_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    resolution_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    responded_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    is_breached BOOLEAN DEFAULT FALSE,
    escalation_level INTEGER DEFAULT 0,
    escalated_at TIMESTAMP WITH TIME ZONE,
    policy_name VARCHAR(100) DEFAULT 'Standard Municipal SLA',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. Audit Logs table (administrative & security audit events)
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. Auth Sessions table (token revocation & active session management)
CREATE TABLE IF NOT EXISTS auth_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    ip_address VARCHAR(45),
    user_agent TEXT,
    is_revoked BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for optimal performance
CREATE INDEX IF NOT EXISTS idx_staff_profiles_dept ON staff_profiles(department_id);
CREATE INDEX IF NOT EXISTS idx_staff_profiles_available ON staff_profiles(is_available);
CREATE INDEX IF NOT EXISTS idx_complaint_images_complaint_id ON complaint_images(complaint_id);
CREATE INDEX IF NOT EXISTS idx_complaint_images_sha256 ON complaint_images(sha256_hash);
CREATE INDEX IF NOT EXISTS idx_complaint_assignments_complaint ON complaint_assignments(complaint_id);
CREATE INDEX IF NOT EXISTS idx_complaint_assignments_staff ON complaint_assignments(staff_id);
CREATE INDEX IF NOT EXISTS idx_status_history_complaint ON status_history(complaint_id);
CREATE INDEX IF NOT EXISTS idx_status_history_created ON status_history(created_at);
CREATE INDEX IF NOT EXISTS idx_sla_records_deadlines ON sla_records(resolution_deadline, is_breached);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_token ON auth_sessions(user_id, token_hash);
