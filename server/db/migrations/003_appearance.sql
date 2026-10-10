-- The trainer's look from character creation: gender plus a part and color per slot, validated
-- against data/appearance.json. NULL until the player has created their character.
ALTER TABLE trainers ADD COLUMN appearance JSONB;
