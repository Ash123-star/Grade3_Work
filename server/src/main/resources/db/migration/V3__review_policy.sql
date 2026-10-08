ALTER TABLE companies ADD COLUMN version integer NOT NULL DEFAULT 1;
ALTER TABLE companies ADD COLUMN review_policy jsonb NOT NULL DEFAULT '{"taskTeamReview":true,"taskDepartmentReview":true}';
ALTER TABLE companies ADD CHECK (jsonb_typeof(review_policy->'taskTeamReview')='boolean' AND jsonb_typeof(review_policy->'taskDepartmentReview')='boolean');
