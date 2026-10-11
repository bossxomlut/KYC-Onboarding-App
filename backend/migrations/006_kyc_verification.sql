-- The payload may contain document PII. Only AES-256-GCM ciphertext is stored.
ALTER TABLE kyc_profiles ADD COLUMN verification text;
ALTER TABLE kyc_profiles ADD COLUMN verification_attempt_id uuid;
ALTER TABLE kyc_profiles ADD COLUMN verification_started_at timestamptz;
ALTER TABLE kyc_submissions ADD COLUMN verification text;
