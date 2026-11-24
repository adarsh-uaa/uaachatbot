-- Migration 022: Add 'developer' to app_role enum
-- In PostgreSQL, adding an enum value must be committed before it can be used in subsequent queries.
-- Run this single statement first and click "Run".

ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'developer';
