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
    id                  bigserial          PRIMARY KEY,
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

-- "Show me quick recipes" — index on the computed total time so the
-- planner can satisfy ORDER BY / WHERE (prep + cook) <= N without
-- reading every row. A functional index stores the expression result.
CREATE INDEX IF NOT EXISTS recipes_total_time_idx
    ON recipes ((prep_time_minutes + cook_time_minutes));

-- Separate indexes on each time column (partial, NULLs excluded) so the
-- planner can satisfy filters like "prep time under 15 min" or
-- "cook time under 30 min" independently, and can also combine both via
-- a bitmap-AND without needing the total-time expression index.
CREATE INDEX IF NOT EXISTS recipes_prep_time_idx
    ON recipes (prep_time_minutes)
    WHERE prep_time_minutes IS NOT NULL;

CREATE INDEX IF NOT EXISTS recipes_cook_time_idx
    ON recipes (cook_time_minutes)
    WHERE cook_time_minutes IS NOT NULL;


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
    recipe_id       bigint          NOT NULL REFERENCES recipes(id)     ON DELETE CASCADE,
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
    recipe_id   bigint    NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    tag_id      bigint  NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
    PRIMARY KEY (recipe_id, tag_id)
);

CREATE INDEX IF NOT EXISTS recipe_tags_tag_idx ON recipe_tags (tag_id);


-- ----------------------------------------------------------------------------
-- Ingredient ⇆ Tag (junction — reuses the shared `tags` table)
-- ----------------------------------------------------------------------------
-- Lets ingredients carry the same kind of labels recipes do — e.g.
-- 'vegan', 'gluten-free', 'dairy', 'nut' — so the app can answer
-- "does this recipe contain any dairy ingredients?" by joining through
-- recipe_ingredients → ingredient_tags → tags, without a second tags
-- table to keep in sync.
-- ON DELETE CASCADE on both sides: removing an ingredient or a tag
-- simply drops the association; neither side is reference data that
-- needs protecting the way food_locations/units are.
CREATE TABLE IF NOT EXISTS ingredient_tags (
    ingredient_id   bigint    NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
    tag_id          bigint    NOT NULL REFERENCES tags(id)        ON DELETE CASCADE,
    PRIMARY KEY (ingredient_id, tag_id)
);

-- Reverse lookup: "which ingredients have this tag?" (e.g. all 'dairy').
CREATE INDEX IF NOT EXISTS ingredient_tags_tag_idx ON ingredient_tags (tag_id);


-- ----------------------------------------------------------------------------
-- Combined ingredients  (a named bundle of ingredients with its own quantity)
-- ----------------------------------------------------------------------------
-- Models things like "Taco Seasoning Mix" or "Basic Tomato Sauce Base" —
-- a reusable, pre-made combination of several ingredients (each with its
-- own quantity/unit) that itself behaves like a single ingredient with a
-- total quantity/unit (e.g. "makes 250 g of mix").
--
-- Kept as its own table (rather than overloading `ingredients`) because a
-- combined ingredient always has a recipe-like breakdown of parts, while
-- a plain ingredient never does — mixing the two concepts in one table
-- would make `ingredients` nullable in confusing ways.
--
-- `quantity`/`unit_id` describe the *yield* of the whole bundle (e.g. "1
-- batch = 100 g"), independent of how much of each component went in —
-- those live on combined_ingredient_items instead.
CREATE TABLE IF NOT EXISTS combined_ingredients (
    id          bigserial     PRIMARY KEY,
    name        citext        NOT NULL UNIQUE,
    quantity    numeric(10,3) NOT NULL CHECK (quantity >= 0),
    unit_id     bigint        REFERENCES units(id) ON DELETE RESTRICT,
    note        text,
    created_at  timestamptz   NOT NULL DEFAULT now(),
    updated_at  timestamptz   NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- Combined ingredient ⇆ Ingredient (junction with quantity + unit)
-- ----------------------------------------------------------------------------
-- One row per component ingredient in the bundle, each with its own
-- quantity/unit (e.g. "2 tbsp Paprika" as part of "Taco Seasoning Mix").
-- ON DELETE CASCADE on the combined-ingredient side: deleting the bundle
-- removes its component lines. ON DELETE RESTRICT on the ingredient &
-- unit sides: refuse to drop reference data that's still in use.
-- Mirrors recipe_ingredients' shape/semantics for consistency.
CREATE TABLE IF NOT EXISTS combined_ingredient_items (
    combined_ingredient_id  bigint        NOT NULL REFERENCES combined_ingredients(id) ON DELETE CASCADE,
    ingredient_id           bigint        NOT NULL REFERENCES ingredients(id)           ON DELETE RESTRICT,
    quantity                numeric(10,3) CHECK (quantity IS NULL OR quantity >= 0),
    unit_id                 bigint        REFERENCES units(id)                          ON DELETE RESTRICT,
    note                    text,                    -- e.g. 'finely chopped'
    PRIMARY KEY (combined_ingredient_id, ingredient_id)
);

-- Reverse lookup: "which combined ingredients use this ingredient?"
CREATE INDEX IF NOT EXISTS combined_ingredient_items_ingredient_idx
    ON combined_ingredient_items (ingredient_id);


-- ----------------------------------------------------------------------------
-- Food locations  (where an ingredient is physically stored)
-- ----------------------------------------------------------------------------
-- A small reference table — fridge, freezer, pantry, spice rack, etc. —
-- kept separate so location names are consistent and can be extended
-- without touching pantry_ingredients. `name` is citext + UNIQUE so
-- "Fridge" and "fridge" are treated as the same location.
-- ON DELETE RESTRICT on the FK in pantry_ingredients prevents removing
-- a location that still has stock assigned to it.
CREATE TABLE IF NOT EXISTS food_locations (
    id          bigserial   PRIMARY KEY,
    name        citext      NOT NULL UNIQUE,   -- 'fridge', 'freezer', 'pantry', …
    created_at  timestamptz NOT NULL DEFAULT now()
);


-- ----------------------------------------------------------------------------
-- Pantry  (a named collection of ingredients, owned by one or more users)
-- ----------------------------------------------------------------------------
-- Defined here — before pantry_ingredients — so the FK reference in that
-- table resolves correctly when Postgres processes the DDL in order.
CREATE TABLE IF NOT EXISTS pantry (
    id         bigserial    PRIMARY KEY,
    name       text         NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NOT NULL DEFAULT now()
);


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
-- and location_id so we never silently lose the meaning of a stocked
-- quantity or its storage location.
CREATE TABLE IF NOT EXISTS pantry_ingredients (
    id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    ingredient_id   bigint        NOT NULL UNIQUE REFERENCES ingredients(id)  ON DELETE CASCADE,
    pantry_id       bigint        NOT NULL REFERENCES pantry(id) ON DELETE CASCADE,
    quantity        numeric(10,3) NOT NULL CHECK (quantity >= 0),
    unit_id         bigint        NOT NULL REFERENCES units(id)               ON DELETE RESTRICT,
    location_id     bigint        REFERENCES food_locations(id)               ON DELETE RESTRICT,
    note            text,
    is_quantified   boolean       NOT NULL DEFAULT true,
    expiration_date date,         
    updated_at      timestamptz   NOT NULL DEFAULT now()
);

-- "What do we currently have in stock?" — skips zero-quantity rows so
-- the planner only scans rows where something is actually available.
CREATE INDEX IF NOT EXISTS pantry_stocked_idx
    ON pantry_ingredients (ingredient_id)
    WHERE quantity > 0;


-- ----------------------------------------------------------------------------
-- Past cooked recipes  (rolling "how often / when last cooked" counter)
-- ----------------------------------------------------------------------------
-- One row per recipe — UNIQUE(recipe_id) — modelled as a rolling counter
-- rather than an event log because the questions we actually ask are
-- "how many times have I cooked this?" and "when did I last make it?".
-- A row only exists once a recipe has been cooked at least once, so
-- `times_cooked` is NOT NULL with CHECK (>= 1).
--
-- Typical write path from the app:
--   INSERT INTO past_cooked_recipes (recipe_id, last_cooked_at)
--   VALUES ($1, now())
--   ON CONFLICT (recipe_id) DO UPDATE
--     SET times_cooked   = past_cooked_recipes.times_cooked + 1,
--         last_cooked_at = EXCLUDED.last_cooked_at;
--
-- If we ever want per-cook history (notes, who cooked, rating per cook),
-- add a sibling `cooked_recipe_events` table; this aggregate stays.
--
-- ON DELETE CASCADE on recipe_id: cook stats are meaningless without
-- the recipe they refer to.
CREATE TABLE IF NOT EXISTS past_cooked_recipes (
    id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id       bigint       NOT NULL UNIQUE REFERENCES recipes(id) ON DELETE CASCADE,
    times_cooked    int          NOT NULL DEFAULT 1 CHECK (times_cooked >= 1),
    last_cooked_at  timestamptz  NOT NULL DEFAULT now()
);

-- Fast "what have I cooked recently?" lookups (most recent first).
CREATE INDEX IF NOT EXISTS past_cooked_recipes_last_cooked_idx
    ON past_cooked_recipes (last_cooked_at DESC);


-- ----------------------------------------------------------------------------
-- API keys
-- ----------------------------------------------------------------------------
-- A minimal credential store — each row represents one active API key.
-- The key itself is a UUID generated server-side by gen_random_uuid().
-- Clients present it as a Bearer token (or equivalent header value).
-- Because the UUID is generated opaquely by the database there is no need
-- to hash it for storage at this layer; if you later want read-once /
-- write-hashed semantics, migrate the column to store a pgcrypto digest
-- and compare hashes in the application instead.
--
-- `created_at` lets you audit when a key was issued and sort/prune old ones.
-- Revoking a key is a plain DELETE; the application treats a missing row
-- as an unauthenticated request.
CREATE TABLE IF NOT EXISTS api_keys (
    key         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Seed the default API key. ON CONFLICT DO NOTHING makes this idempotent:
-- re-running the file leaves the existing row (and its created_at) untouched.
INSERT INTO api_keys (key)
VALUES ('7e9f3c1a-4b82-4d56-a0e7-5f2c8d3b1a9e')
ON CONFLICT (key) DO NOTHING;

-- User table

CREATE TABLE IF NOT EXISTS users (
    id         bigserial        PRIMARY KEY,
    username   text      NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- User pantry

CREATE TABLE IF NOT EXISTS user_pantry (
    id              bigserial          PRIMARY KEY,
    id_pantry   bigint      NOT NULL REFERENCES pantry(id) ON DELETE CASCADE,
    id_user bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- Pending pantry items  (scanned/queued items awaiting review before they
-- join pantry_ingredients)
-- ----------------------------------------------------------------------------
-- Models the intake queue for e.g. a barcode-scanning flow: a row is
-- created as soon as an item is scanned, then reviewed and either merged
-- into pantry_ingredients ('approved') or discarded ('rejected').
-- `name` is free text (not a FK to ingredients) because the UPC lookup may
-- return a name that hasn't been matched to a canonical ingredient yet —
-- that resolution happens when the item is approved.
-- `upc` is intentionally NOT unique: the same barcode can be scanned more
-- than once before either scan has been processed, and each scan gets its
-- own row.
-- `pantry_id` records which pantry the item will join once approved.
-- ON DELETE CASCADE mirrors pantry_ingredients.pantry_id: a pending item
-- has no meaning once its destination pantry is gone.
CREATE TABLE IF NOT EXISTS pending_pantry_items (
    id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    pantry_id   bigint        NOT NULL REFERENCES pantry(id) ON DELETE CASCADE,
    upc         text          NOT NULL,
    name        text          NOT NULL,
    quantity    numeric(10,3) NOT NULL CHECK (quantity >= 0),
    unit_id     bigint        REFERENCES units(id) ON DELETE RESTRICT,
    price       numeric(10,2) CHECK (price IS NULL OR price >= 0),
    status      text          NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'processing', 'approved', 'rejected')),
    created_at  timestamptz   NOT NULL DEFAULT now(),
    updated_at  timestamptz   NOT NULL DEFAULT now()
);

-- "What's still waiting on review?" — the common queue-processing query,
-- typically scoped to one pantry at a time.
CREATE INDEX IF NOT EXISTS pending_pantry_items_pantry_status_idx
    ON pending_pantry_items (pantry_id, status)
    WHERE status IN ('pending', 'processing');

-- Look up all pending scans for a given barcode.
CREATE INDEX IF NOT EXISTS pending_pantry_items_upc_idx
    ON pending_pantry_items (upc);


-- ----------------------------------------------------------------------------
-- User recipes  (marks a recipe as authored by a user, rather than seed data)
-- ----------------------------------------------------------------------------
-- `recipes` holds both built-in seed recipes and user-created ones; a row
-- here means "this recipe was created by this user" — seed recipes simply
-- have no row. `recipe_id` is the PRIMARY KEY (not part of a composite
-- key) because a recipe has exactly one author, so the relationship is
-- one-user-to-many-recipes rather than many-to-many.
-- ON DELETE CASCADE both ways: deleting the recipe drops the authorship
-- record, and deleting the user drops authorship of their recipes (the
-- recipes themselves are untouched, they just become unauthored).
CREATE TABLE IF NOT EXISTS user_recipes (
    recipe_id   bigint      PRIMARY KEY REFERENCES recipes(id) ON DELETE CASCADE,
    user_id     bigint      NOT NULL REFERENCES users(id)      ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- "Which recipes has this user created?"
CREATE INDEX IF NOT EXISTS user_recipes_user_idx
    ON user_recipes (user_id);


-- ----------------------------------------------------------------------------
-- Collections  (user-curated, named lists of recipes — e.g. "Weeknight
-- Dinners", "Meal Prep Sunday")
-- ----------------------------------------------------------------------------
-- Each collection is owned by exactly one user. UNIQUE(user_id, name)
-- stops the same user creating two collections with the same name while
-- still letting different users each have e.g. a "Favorites" collection.
-- ON DELETE CASCADE: a collection has no meaning once its owner is gone.
CREATE TABLE IF NOT EXISTS collections (
    id          bigserial   PRIMARY KEY,
    user_id     bigint      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, name)
);

-- "Which collections does this user have?"
CREATE INDEX IF NOT EXISTS collections_user_idx
    ON collections (user_id);


-- ----------------------------------------------------------------------------
-- Collection ⇆ Recipe (junction — recipes added to a collection)
-- ----------------------------------------------------------------------------
-- True many-to-many: a recipe can sit in many collections (including
-- collections owned by different users) and a collection can hold many
-- recipes. ON DELETE CASCADE on both sides: the entry is meaningless once
-- either the collection or the recipe is gone.
CREATE TABLE IF NOT EXISTS collection_recipes (
    collection_id  bigint      NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    recipe_id      bigint      NOT NULL REFERENCES recipes(id)     ON DELETE CASCADE,
    created_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (collection_id, recipe_id)
);

-- Reverse lookup: "which collections include this recipe?"
CREATE INDEX IF NOT EXISTS collection_recipes_recipe_idx
    ON collection_recipes (recipe_id);


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
ALTER TABLE ingredient_tags       OWNER TO whatsfordinner;
ALTER TABLE combined_ingredients      OWNER TO whatsfordinner;
ALTER TABLE combined_ingredient_items OWNER TO whatsfordinner;
ALTER TABLE food_locations       OWNER TO whatsfordinner;
ALTER TABLE pantry_ingredients   OWNER TO whatsfordinner;
ALTER TABLE pending_pantry_items OWNER TO whatsfordinner;
ALTER TABLE past_cooked_recipes  OWNER TO whatsfordinner;
ALTER TABLE api_keys             OWNER TO whatsfordinner;
ALTER TABLE users                OWNER TO whatsfordinner;
ALTER TABLE pantry               OWNER TO whatsfordinner;
ALTER TABLE user_pantry          OWNER TO whatsfordinner;
ALTER TABLE user_recipes         OWNER TO whatsfordinner;
ALTER TABLE collections          OWNER TO whatsfordinner;
ALTER TABLE collection_recipes   OWNER TO whatsfordinner;

-- Sequences backing the bigserial PKs are separate objects and must be
-- transferred too — otherwise INSERTs fail with "permission denied for
-- sequence …_id_seq".
ALTER SEQUENCE recipes_id_seq        OWNER TO whatsfordinner;
ALTER SEQUENCE ingredients_id_seq    OWNER TO whatsfordinner;
ALTER SEQUENCE units_id_seq          OWNER TO whatsfordinner;
ALTER SEQUENCE tags_id_seq           OWNER TO whatsfordinner;
ALTER SEQUENCE combined_ingredients_id_seq OWNER TO whatsfordinner;
ALTER SEQUENCE food_locations_id_seq OWNER TO whatsfordinner;
ALTER SEQUENCE users_id_seq          OWNER TO whatsfordinner;
ALTER SEQUENCE pantry_id_seq         OWNER TO whatsfordinner;
ALTER SEQUENCE user_pantry_id_seq    OWNER TO whatsfordinner;
ALTER SEQUENCE collections_id_seq    OWNER TO whatsfordinner;
