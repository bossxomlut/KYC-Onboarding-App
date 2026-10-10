ALTER TABLE users ADD COLUMN role text NOT NULL DEFAULT 'user'
  CHECK (role IN ('user','reviewer','super_admin'));
-- There is one bootstrap owner; the application never promotes another owner.
CREATE UNIQUE INDEX users_single_super_admin ON users(role) WHERE role='super_admin';

CREATE TABLE role_requests (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  requested_role text NOT NULL DEFAULT 'reviewer' CHECK (requested_role='reviewer'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reason text NOT NULL,
  decision_reason text,
  decided_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  CHECK ((status='pending' AND decided_at IS NULL AND decided_by IS NULL)
    OR (status<>'pending' AND decided_at IS NOT NULL AND decided_by IS NOT NULL))
);
CREATE UNIQUE INDEX role_requests_one_pending ON role_requests(user_id) WHERE status='pending';
CREATE INDEX role_requests_queue ON role_requests(status,created_at);

CREATE TABLE role_audit_events (
  id uuid PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES users(id),
  target_user_id uuid NOT NULL REFERENCES users(id),
  previous_role text CHECK (previous_role IN ('user','reviewer','super_admin')),
  new_role text NOT NULL CHECK (new_role IN ('user','reviewer','super_admin')),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX role_audit_target ON role_audit_events(target_user_id,created_at);

-- Legacy CLI decisions have no actor. New decisions always supply reviewed_by.
ALTER TABLE kyc_reviews ADD COLUMN reviewed_by uuid REFERENCES users(id);
ALTER TABLE kyc_reviews ADD COLUMN reason text;
CREATE INDEX kyc_profiles_review_queue ON kyc_profiles(submitted_at,user_id) WHERE status='pending_review';
