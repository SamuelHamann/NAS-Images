-- ============================================================================
-- 02-init-whatsfordinner.sql
-- ----------------------------------------------------------------------------
-- App: WhatsForDinner — meal-planning / recipe management.
--
-- Runs ONCE on first boot, AFTER 01-create-databases.sh has created the
-- `whatsfordinner` database and its owning login role. The official
-- postgres entrypoint executes every file in /docker-entrypoint-initdb.d/
-- in alphabetical order, so any future app gets its own file numbered
-- 03-, 04-, … to keep schemas isolated and easy to review.
--
-- Conventions for per-app init files:
--   * ONE file per app — never mix tables from different apps here.
--   * Always `\connect <app-db>` before creating objects so they land in
--     the right database (extensions in postgres are per-database, too).
--   * Transfer ownership of every table AND sequence to the app role so
--     the app can run its own migrations later without superuser rights.
--   * Keep statements idempotent (`IF NOT EXISTS`) — makes it safe to
--     replay the file by hand on an existing cluster.
-- ============================================================================

\connect whatsfordinner

-- ----------------------------------------------------------------------------
-- Extensions
-- ----------------------------------------------------------------------------
-- pgcrypto : gen_random_uuid() for surrogate primary keys.
-- citext   : case-insensitive text — handy for ingredient / tag names where
--            "Olive Oil" and "olive oil" should collide on UNIQUE.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;


-- ----------------------------------------------------------------------------
-- Recipes
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recipes (
    id                  uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    name                text          NOT NULL,
    description         text,
    instructions        text,
    source_url          text,
    servings            int           CHECK (servings          IS NULL OR servings          > 0),
    prep_time_minutes   int           CHECK (prep_time_minutes IS NULL OR prep_time_minutes >= 0),
    cook_time_minutes   int           CHECK (cook_time_minutes IS NULL OR cook_time_minutes >= 0),
    created_at          timestamptz   NOT NULL DEFAULT now(),
    updated_at          timestamptz   NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- Ingredients (canonical list, reused across recipes)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ingredients (
    id          bigserial   PRIMARY KEY,
    name        citext      NOT NULL UNIQUE,
    created_at  timestamptz NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- Units (canonical measurement units, reused across recipes & pantry)
-- ----------------------------------------------------------------------------
-- Kept in a dedicated table — rather than free-text on recipe_ingredients
-- — so that:
--   * the same unit is spelled the same way everywhere ("tbsp", not
--     "TBSP" / "Tbsp" / "tablespoon");
--   * a unit can be referenced from multiple places (recipes AND pantry
--     stock) without duplication;
--   * conversion / display logic the app may add later has a single
--     source of truth to attach to.
-- Names are `citext` + UNIQUE so "G" and "g" collide on insert.
CREATE TABLE IF NOT EXISTS units (
    id          bigserial   PRIMARY KEY,
    name        citext      NOT NULL UNIQUE,    -- 'g', 'ml', 'tbsp', 'piece', 'cup'…
    created_at  timestamptz NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- Recipe ⇆ Ingredient (junction with quantity + unit)
-- ----------------------------------------------------------------------------
-- ON DELETE CASCADE on the recipe side: deleting a recipe removes its
-- ingredient lines. ON DELETE RESTRICT on the ingredient & unit sides:
-- refuse to drop reference data that's still in use somewhere.
-- `unit_id` is nullable so recipes can legitimately have unit-less
-- entries (e.g. "a dash of salt").
CREATE TABLE IF NOT EXISTS recipe_ingredients (
    recipe_id       uuid          NOT NULL REFERENCES recipes(id)     ON DELETE CASCADE,
    ingredient_id   bigint        NOT NULL REFERENCES ingredients(id) ON DELETE RESTRICT,
    quantity        numeric(10,3) CHECK (quantity IS NULL OR quantity >= 0),
    unit_id         bigint        REFERENCES units(id)                ON DELETE RESTRICT,
    note            text,                       -- e.g. 'finely chopped'
    PRIMARY KEY (recipe_id, ingredient_id)
);

-- Reverse lookup: "which recipes use this ingredient?"
CREATE INDEX IF NOT EXISTS recipe_ingredients_ingredient_idx
    ON recipe_ingredients (ingredient_id);


-- ----------------------------------------------------------------------------
-- Tags  (vegan, quick, gluten-free, kid-friendly…)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tags (
    id    bigserial PRIMARY KEY,
    name  citext    NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS recipe_tags (
    recipe_id   uuid    NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    tag_id      bigint  NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
    PRIMARY KEY (recipe_id, tag_id)
);

CREATE INDEX IF NOT EXISTS recipe_tags_tag_idx ON recipe_tags (tag_id);


-- ----------------------------------------------------------------------------
-- Pantry ingredients  (what we currently have in stock at home)
-- ----------------------------------------------------------------------------
-- One row per ingredient — UNIQUE(ingredient_id) — with the remaining
-- quantity and the unit that quantity is expressed in. Modelling it
-- this way (rather than one row per package / stock item) matches the
-- common "do I have flour?" → "yes, 750 g" lookup. If we ever want to
-- track individual packages with their own expiry dates, drop the
-- UNIQUE constraint and add `label` / `expires_on` columns.
--
-- `quantity` is NOT NULL because a row existing in this table means
-- "we have some" — set it to 0 (or DELETE the row) when running out.
-- ON DELETE CASCADE on ingredient_id so removing an ingredient from
-- the master list also clears it from the pantry; RESTRICT on unit_id
-- so we never silently lose the meaning of a stocked quantity.
CREATE TABLE IF NOT EXISTS pantry_ingredients (
    id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    ingredient_id   bigint        NOT NULL UNIQUE REFERENCES ingredients(id) ON DELETE CASCADE,
    quantity        numeric(10,3) NOT NULL CHECK (quantity >= 0),
    unit_id         bigint        NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
    note            text,
    is_quantified   boolean       NOT NULL DEFAULT true,
    updated_at      timestamptz   NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- Hand ownership over to the app role
-- ----------------------------------------------------------------------------
-- After this, the `whatsfordinner` role can ALTER / DROP / migrate any
-- object in its database without needing the postgres superuser.
ALTER TABLE recipes              OWNER TO whatsfordinner;
ALTER TABLE ingredients          OWNER TO whatsfordinner;
ALTER TABLE units                OWNER TO whatsfordinner;
ALTER TABLE recipe_ingredients   OWNER TO whatsfordinner;
ALTER TABLE tags                 OWNER TO whatsfordinner;
ALTER TABLE recipe_tags          OWNER TO whatsfordinner;
ALTER TABLE pantry_ingredients   OWNER TO whatsfordinner;

-- Sequences backing the bigserial PKs are separate objects and must be
-- transferred too — otherwise INSERTs fail with "permission denied for
-- sequence …_id_seq".
ALTER SEQUENCE ingredients_id_seq OWNER TO whatsfordinner;
ALTER SEQUENCE units_id_seq       OWNER TO whatsfordinner;
ALTER SEQUENCE tags_id_seq        OWNER TO whatsfordinner;
