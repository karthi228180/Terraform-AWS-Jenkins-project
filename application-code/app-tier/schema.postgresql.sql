-- PostgreSQL schema equivalent of the original MySQL "webappdb" schema.
CREATE TABLE IF NOT EXISTS transactions (
    id          SERIAL PRIMARY KEY,
    amount      NUMERIC(12, 2) NOT NULL,
    description VARCHAR(255) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
