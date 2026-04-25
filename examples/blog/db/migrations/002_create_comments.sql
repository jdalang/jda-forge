CREATE TABLE IF NOT EXISTS comments (
    id         SERIAL PRIMARY KEY,
    post_id    INTEGER      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author     VARCHAR(128) NOT NULL,
    body       TEXT         NOT NULL,
    created_at TIMESTAMP    NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP
);

CREATE INDEX idx_comments_post_id ON comments (post_id);
