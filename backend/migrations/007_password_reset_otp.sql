ALTER TABLE password_reset_tokens
  ADD COLUMN attempt_count integer NOT NULL DEFAULT 0
    CHECK (attempt_count BETWEEN 0 AND 5);

CREATE INDEX password_reset_user_idx
  ON password_reset_tokens(user_id, created_at DESC);

-- Link tokens and their queued emails must not survive the switch to OTP.
UPDATE password_reset_tokens SET consumed_at=now() WHERE consumed_at IS NULL;
DELETE FROM email_outbox WHERE kind='reset';
