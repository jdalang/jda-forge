-- Migration: 002_create_posts
-- Creates the posts table with a foreign key to users.

CREATE TABLE IF NOT EXISTS posts (
    id          BIGSERIAL    PRIMARY KEY,
    user_id     BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       VARCHAR(512) NOT NULL,
    body        TEXT         NOT NULL DEFAULT '',
    slug        VARCHAR(512) UNIQUE,
    published   BOOLEAN      NOT NULL DEFAULT false,
    deleted_at  TIMESTAMP,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_posts_user_id    ON posts (user_id);
CREATE INDEX IF NOT EXISTS idx_posts_slug       ON posts (slug);
CREATE INDEX IF NOT EXISTS idx_posts_published  ON posts (published);
CREATE INDEX IF NOT EXISTS idx_posts_deleted_at ON posts (deleted_at);
