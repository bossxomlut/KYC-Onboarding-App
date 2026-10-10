CREATE TABLE users (
  id uuid PRIMARY KEY,
  email_normalized text UNIQUE NOT NULL,
  password_hash text NOT NULL,
  email_verified_at timestamptz,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','disabled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id uuid NOT NULL,
  refresh_token_hash text UNIQUE NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by_session_id uuid REFERENCES auth_sessions(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions(user_id);
CREATE INDEX auth_sessions_family_idx ON auth_sessions(family_id);
CREATE TABLE email_verification_tokens (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  attempt_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX verification_user_idx ON email_verification_tokens(user_id, created_at DESC);
CREATE TABLE password_reset_tokens (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text UNIQUE NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE kyc_profiles (
  id uuid PRIMARY KEY,
  user_id uuid UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_started','in_progress','pending_review','verified','rejected')),
  personal_details text,
  rejection_reason text,
  required_steps text[] NOT NULL DEFAULT '{}',
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE kyc_media (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('document','selfie')),
  document_type text CHECK (document_type IN ('passport','national_id','driving_licence')),
  mime_type text NOT NULL,
  size integer NOT NULL,
  storage_key uuid UNIQUE NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id,kind)
);
CREATE TABLE kyc_reviews (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  decision text NOT NULL CHECK (decision IN ('verified','rejected')),
  required_steps text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
