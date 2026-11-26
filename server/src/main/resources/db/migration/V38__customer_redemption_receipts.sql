-- V37 never stored the original counters. Do not fabricate receipts for existing data.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM customer_benefit_redemptions) THEN
        RAISE EXCEPTION 'V38 cannot recover exact receipt counters for existing V37 redemptions; preserve the ledger and confirm a migration policy before retrying';
    END IF;
END $$;

ALTER TABLE customer_benefits
    ADD CONSTRAINT customer_benefits_owner_key UNIQUE (company_id, customer_id, id);

ALTER TABLE customer_benefit_redemptions
    ADD CONSTRAINT customer_redemptions_benefit_owner_fk
        FOREIGN KEY (company_id, customer_id, benefit_id)
        REFERENCES customer_benefits(company_id, customer_id, id),
    ADD COLUMN used_at_redemption bigint NOT NULL CHECK (used_at_redemption > 0),
    ADD COLUMN remaining_at_redemption bigint CHECK (remaining_at_redemption >= 0);
