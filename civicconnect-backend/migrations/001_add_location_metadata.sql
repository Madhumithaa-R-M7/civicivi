-- Migration 001: Add GPS location accuracy and location capture timestamp to complaints table
-- CivicConnect PostgreSQL Database

ALTER TABLE complaints ADD COLUMN IF NOT EXISTS location_accuracy DOUBLE PRECISION;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS location_captured_at TIMESTAMP WITH TIME ZONE;

-- Add index on created_at and location_captured_at for efficient chronological queries
CREATE INDEX IF NOT EXISTS idx_complaints_created_at ON complaints(created_at);
CREATE INDEX IF NOT EXISTS idx_complaints_location_captured_at ON complaints(location_captured_at);
