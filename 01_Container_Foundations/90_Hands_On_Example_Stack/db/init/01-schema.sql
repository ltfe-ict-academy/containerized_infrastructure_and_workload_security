CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS app_users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL
);

INSERT INTO products (name, description, price)
VALUES
    ('Red Mug', 'Ceramic coffee mug used by the frontend demo.', 12.50),
    ('Blue Hoodie', 'Lightweight hoodie for conference labs.', 39.00),
    ('Sticker Pack', 'Security-themed stickers for laptops.', 7.00),
    ('Notebook', 'Paper notebook for architecture sketches.', 9.50)
ON CONFLICT DO NOTHING;

INSERT INTO app_users (username, password_hash, role)
VALUES
    ('admin', '$2b$12$trainingonlyplaceholderhashforadminuser0000000000', 'admin'),
    ('analyst', '$2b$12$trainingonlyplaceholderhashforanalyst000000000', 'analyst')
ON CONFLICT (username) DO NOTHING;
