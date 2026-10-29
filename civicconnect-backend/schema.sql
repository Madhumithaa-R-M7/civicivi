-- CivicConnect Database Schema for PostgreSQL
-- Run this in pgAdmin Query Tool or psql connected to 'civicconnect' database

-- 1. Users table (citizens, staff, administrators)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(150) UNIQUE,
    phone VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255),
    role VARCHAR(20) DEFAULT 'user', -- 'user', 'staff', 'admin'
    location VARCHAR(255) DEFAULT 'Mumbai',
    points INTEGER DEFAULT 0,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Ensure columns exist in case table was created with an older schema
ALTER TABLE users ADD COLUMN IF NOT EXISTS location VARCHAR(255) DEFAULT 'Mumbai';
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE;

-- 2. OTP Verification Challenges table (for secure SMS & Email OTP authentication / recovery)
CREATE TABLE IF NOT EXISTS otp_challenges (
    id SERIAL PRIMARY KEY,
    verification_id VARCHAR(64) UNIQUE NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(150),
    otp_hash VARCHAR(255) NOT NULL,
    purpose VARCHAR(50) DEFAULT 'auth', -- 'auth', 'registration', 'login', 'password_reset'
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 5,
    is_consumed BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Schema compatibility updates for otp_challenges
ALTER TABLE otp_challenges ADD COLUMN IF NOT EXISTS email VARCHAR(150);
ALTER TABLE otp_challenges ALTER COLUMN phone DROP NOT NULL;

-- 3. Complaints table (issues reported by citizens)
CREATE TABLE IF NOT EXISTS complaints (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    category VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    priority VARCHAR(20) DEFAULT 'Medium', -- 'Low', 'Medium', 'High', 'Emergency'
    location TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_accuracy DOUBLE PRECISION,
    location_captured_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) DEFAULT 'Pending', -- 'Pending', 'In Progress', 'Resolved', 'Rejected'
    image_url TEXT,
    assigned_to INTEGER REFERENCES users(id) ON DELETE SET NULL,
    resolution_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Schema compatibility updates for complaints
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS location_accuracy DOUBLE PRECISION;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMP WITH TIME ZONE;

-- 4. Notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    complaint_id INTEGER REFERENCES complaints(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'info',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Points & Rewards transaction log
CREATE TABLE IF NOT EXISTS points_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    complaint_id INTEGER REFERENCES complaints(id) ON DELETE SET NULL,
    points INTEGER NOT NULL,
    reason VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. Departments table
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

INSERT INTO departments (name, code, description, contact_email, contact_phone)
VALUES 
    ('Roads & Traffic', 'ROADS', 'Management of potholes, asphalt resurfacing, road signs, and traffic equipment', 'roads@civicconnect.gov', '+91-22-2410-0001'),
    ('Cleanliness & Waste Management', 'SANITATION', 'Garbage collection, overflowing dumpsters, and street sweeping', 'sanitation@civicconnect.gov', '+91-22-2410-0002'),
    ('Water Supply & Drainage', 'WATER', 'Water pipeline leakages, low pressure, blocked stormwater drains and sewage', 'water@civicconnect.gov', '+91-22-2410-0003'),
    ('Street & Public Lighting', 'LIGHTING', 'Damaged streetlights, dark public alleys, and exposed electrical hazards', 'lighting@civicconnect.gov', '+91-22-2410-0004'),
    ('Public Infrastructure & Facilities', 'PUBLIC_WORKS', 'Public toilets, bus shelters, parks, footpaths, and civic structures', 'facilities@civicconnect.gov', '+91-22-2410-0005')
ON CONFLICT (code) DO NOTHING;

-- 7. Staff Profiles table
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

-- Schema compatibility updates for complaints table
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS department_id INTEGER REFERENCES departments(id) ON DELETE SET NULL;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS priority_score DOUBLE PRECISION DEFAULT 50.0;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS sla_status VARCHAR(50) DEFAULT 'ON_TRACK';
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS duplicate_of_id INTEGER REFERENCES complaints(id) ON DELETE SET NULL;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS duplicate_score DOUBLE PRECISION;

-- 8. Complaint Images table
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

-- 9. Complaint Assignments table
CREATE TABLE IF NOT EXISTS complaint_assignments (
    id SERIAL PRIMARY KEY,
    complaint_id INTEGER NOT NULL REFERENCES complaints(id) ON DELETE CASCADE,
    staff_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    department_id INTEGER REFERENCES departments(id) ON DELETE SET NULL,
    assigned_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    assignment_score DOUBLE PRECISION DEFAULT 0.0,
    assignment_method VARCHAR(50) DEFAULT 'manual',
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. Status History table (FSM Audit Log)
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

-- 11. SLA Records table
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

-- 12. Audit Logs table
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

-- 13. Auth Sessions table
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

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_otp_challenges_phone ON otp_challenges(phone);
CREATE INDEX IF NOT EXISTS idx_otp_challenges_email ON otp_challenges(email);
CREATE INDEX IF NOT EXISTS idx_otp_challenges_vid ON otp_challenges(verification_id);
CREATE INDEX IF NOT EXISTS idx_complaints_user_id ON complaints(user_id);
CREATE INDEX IF NOT EXISTS idx_complaints_status ON complaints(status);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_points_log_user_id ON points_log(user_id);
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
