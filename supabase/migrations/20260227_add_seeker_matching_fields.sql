-- Migration: Add matching fields to Job Seeker Profile
-- Date: 2026-02-27

ALTER TABLE job_seeker_profiles 
ADD COLUMN IF NOT EXISTS assets TEXT[] DEFAULT '{}';

COMMENT ON COLUMN job_seeker_profiles.assets IS 'List of assets owned by the applicant: Own Bike, Driving License, Smartphone, Laptop';
