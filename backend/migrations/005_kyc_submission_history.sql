CREATE TABLE kyc_submissions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  personal_details text,
  status text NOT NULL CHECK (status IN ('pending_review','verified','rejected')),
  rejection_reason text,
  required_steps text[] NOT NULL DEFAULT '{}',
  submitted_at timestamptz,
  updated_at timestamptz NOT NULL,
  review_decision text CHECK (review_decision IN ('verified','rejected')),
  review_reason text,
  review_required_steps text[] NOT NULL DEFAULT '{}',
  reviewed_at timestamptz,
  -- Identity snapshots deliberately do not depend on the actor's current account.
  reviewed_by uuid,
  reviewer_email text,
  reviewer_role text CHECK (reviewer_role IN ('user','reviewer','super_admin')),
  UNIQUE(user_id,version),
  CHECK ((review_decision IS NULL AND reviewed_at IS NULL) OR
    (review_decision = status AND reviewed_at IS NOT NULL))
);
CREATE UNIQUE INDEX kyc_submissions_one_pending ON kyc_submissions(user_id) WHERE status='pending_review';

CREATE TABLE kyc_submission_media (
  submission_id uuid NOT NULL REFERENCES kyc_submissions(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('document','selfie')),
  media_id uuid NOT NULL,
  document_type text CHECK (document_type IN ('passport','national_id','driving_licence')),
  mime_type text NOT NULL,
  size integer NOT NULL,
  storage_key uuid NOT NULL,
  client_capture_id text,
  PRIMARY KEY(submission_id,kind)
);
CREATE INDEX kyc_submission_media_storage ON kyc_submission_media(storage_key);
ALTER TABLE kyc_profiles ADD COLUMN current_submission_id uuid REFERENCES kyc_submissions(id);

-- Only the current submission's actual remaining details/photos can be recovered.
-- Older review events alone cannot recreate the assets they reviewed.
INSERT INTO kyc_submissions(id,user_id,profile_id,version,personal_details,status,rejection_reason,required_steps,submitted_at,updated_at,review_decision,review_reason,review_required_steps,reviewed_at,reviewed_by)
SELECT gen_random_uuid(),p.user_id,p.id,1,p.personal_details,p.status,p.rejection_reason,p.required_steps,p.submitted_at,p.updated_at,
  CASE WHEN a.decision=p.status THEN a.decision END,
  CASE WHEN a.decision=p.status THEN COALESCE(a.reason,CASE WHEN p.status='rejected' THEN p.rejection_reason END) END,
  CASE WHEN a.decision=p.status THEN a.required_steps ELSE '{}'::text[] END,
  CASE WHEN a.decision=p.status THEN a.created_at END,
  CASE WHEN a.decision=p.status THEN a.reviewed_by END
FROM kyc_profiles p
LEFT JOIN LATERAL (
  SELECT * FROM kyc_reviews r WHERE r.user_id=p.user_id
    AND (p.submitted_at IS NULL OR r.created_at>=p.submitted_at)
  ORDER BY r.created_at DESC,r.id DESC LIMIT 1
) a ON p.status IN ('verified','rejected')
WHERE p.status IN ('pending_review','verified','rejected');

INSERT INTO kyc_submission_media(submission_id,kind,media_id,document_type,mime_type,size,storage_key,client_capture_id)
SELECT s.id,m.kind,m.id,m.document_type,m.mime_type,m.size,m.storage_key,m.client_capture_id
FROM kyc_submissions s JOIN kyc_media m ON m.user_id=s.user_id;

UPDATE kyc_profiles p SET current_submission_id=s.id FROM kyc_submissions s WHERE s.user_id=p.user_id;
