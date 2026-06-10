-- contact:edit is a UI alias for contact:update; add so matrix can store it and sync push accepts it.
INSERT INTO permission_actions (name, resource) VALUES
    ('contact:edit', 'contact')
ON CONFLICT (name) DO NOTHING;
