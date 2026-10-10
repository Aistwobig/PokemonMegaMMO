-- Story progress: which one-time events a trainer has seen, e.g. { "intro": true } after
-- Professor Sycamore's welcome and waking up at home. Only the server sets these.
ALTER TABLE trainers ADD COLUMN flags JSONB NOT NULL DEFAULT '{}';
