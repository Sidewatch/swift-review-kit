-- One-off cleanup the agent proposed. Two of these are fine; three are not.

DELETE FROM sessions WHERE expires_at < NOW();

DELETE FROM sessions
 WHERE user_id IS NULL;

DELETE FROM login_attempts;

UPDATE users SET plan = 'free';

DELETE FROM carts WHERE 1=1;

UPDATE users
   SET last_seen = NOW()
 WHERE id = 42;

TRUNCATE TABLE analytics_events;

/* Block comments do not count either:
   DELETE FROM users;
*/
