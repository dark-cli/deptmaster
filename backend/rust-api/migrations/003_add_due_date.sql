-- Add due_date column to transactions_projection
ALTER TABLE transactions_projection 
ADD COLUMN IF NOT EXISTS due_date DATE;

CREATE INDEX IF NOT EXISTS idx_transactions_due_date 
ON transactions_projection(due_date) 
WHERE is_deleted = false AND due_date IS NOT NULL;
