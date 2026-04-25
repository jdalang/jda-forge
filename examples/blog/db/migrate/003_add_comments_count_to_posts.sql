-- migrate:up
ALTER TABLE posts ADD COLUMN comments_count INTEGER NOT NULL DEFAULT 0;

-- migrate:down
ALTER TABLE posts DROP COLUMN comments_count;
