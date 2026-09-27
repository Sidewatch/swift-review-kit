-- Prisma migration: the agent "cleaned up" the legacy profile columns.
-- DROP TABLE audit_log;            -- a commented-out statement is not one

ALTER TABLE "User" DROP COLUMN "legacyId";
ALTER TABLE "User" ALTER COLUMN "email" TYPE VARCHAR(120);
ALTER TABLE "User" DROP CONSTRAINT "User_legacyId_key";   -- a constraint, not data

INSERT INTO "Note" ("body") VALUES ('run DROP TABLE later');   -- text in a value is data

DROP TABLE IF EXISTS "LegacyProfile";
