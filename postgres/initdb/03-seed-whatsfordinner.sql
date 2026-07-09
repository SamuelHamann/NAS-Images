-- ============================================================================
-- 03-seed-whatsfordinner.sql
-- ----------------------------------------------------------------------------
-- App: WhatsForDinner — development / test seed data.
--
-- Populates every table with a realistic set of bogus rows so the app can
-- be exercised right after first boot without manual data entry.
--
-- Safe-to-rerun guarantees
-- ────────────────────────
--   • Tables keyed on a natural UNIQUE column use ON CONFLICT DO NOTHING.
--   • Tables with no natural unique key (recipes, users, pantry) guard
--     inserts with WHERE NOT EXISTS on the name / username column.
--   • user_pantry has no UNIQUE(id_user, id_pantry) constraint; it is
--     likewise guarded with WHERE NOT EXISTS.
--
-- Dependency order
-- ────────────────
-- Reference tables first (units, ingredients, tags, food_locations),
-- then core entities (users, pantry, recipes), then every junction /
-- relation table that points back to those.
--
-- Maintenance
-- ───────────
-- Update this file whenever a table is added to or structurally changed
-- in 02-init-whatsfordinner.sql.  Column additions → add the column to
-- the relevant VALUES block.  New table → add a new dated section at the
-- bottom following the same idempotency pattern.
-- ============================================================================

\connect whatsfordinner

-- ============================================================================
-- 1.  Reference / lookup tables  (no FK dependencies)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- units
-- ----------------------------------------------------------------------------
INSERT INTO units (name) VALUES
    ('g'),
    ('kg'),
    ('ml'),
    ('L'),
    ('tsp'),
    ('tbsp'),
    ('cup'),
    ('oz'),
    ('lb'),
    ('piece'),
    ('pinch'),
    ('clove'),
    ('slice'),
    ('bunch'),
    ('can')
ON CONFLICT (name) DO NOTHING;


-- ----------------------------------------------------------------------------
-- ingredients  (canonical list — all names used across recipes and pantry)
-- ----------------------------------------------------------------------------
INSERT INTO ingredients (name) VALUES
    ('Spaghetti'),
    ('Ground Beef'),
    ('Tomato Sauce'),
    ('Garlic'),
    ('Onion'),
    ('Olive Oil'),
    ('Salt'),
    ('Black Pepper'),
    ('Chicken Breast'),
    ('Broccoli'),
    ('Soy Sauce'),
    ('Ginger'),
    ('Sesame Oil'),
    ('Cornstarch'),
    ('Avocado'),
    ('Sourdough Bread'),
    ('Lemon Juice'),
    ('Red Pepper Flakes'),
    ('Banana'),
    ('Egg'),
    ('All-Purpose Flour'),
    ('Milk'),
    ('Butter'),
    ('Baking Powder'),
    ('Sugar'),
    ('Vanilla Extract'),
    ('Cucumber'),
    ('Cherry Tomatoes'),
    ('Kalamata Olives'),
    ('Feta Cheese'),
    ('Red Onion'),
    ('Dried Oregano'),
    ('Red Wine Vinegar'),
    ('Taco Shells'),
    ('Cheddar Cheese'),
    ('Salsa'),
    ('Sour Cream'),
    ('Romaine Lettuce'),
    ('Lime'),
    ('Chickpeas'),
    ('Coconut Milk'),
    ('Curry Powder'),
    ('Turmeric'),
    ('Basmati Rice'),
    ('Chocolate Chips'),
    ('Brown Sugar'),
    ('Baking Soda'),
    ('Paprika'),
    ('Cumin')
ON CONFLICT (name) DO NOTHING;


-- ----------------------------------------------------------------------------
-- tags
-- ----------------------------------------------------------------------------
INSERT INTO tags (name) VALUES
    ('Italian'),
    ('Quick'),
    ('Vegetarian'),
    ('Vegan'),
    ('Breakfast'),
    ('Lunch'),
    ('Dinner'),
    ('Dessert'),
    ('Gluten-Free'),
    ('Dairy-Free'),
    ('Kid-Friendly'),
    ('Healthy'),
    ('Asian'),
    ('Mexican'),
    ('Mediterranean'),
    ('Comfort Food'),
    ('Meal Prep'),
    ('Budget-Friendly')
ON CONFLICT (name) DO NOTHING;


-- ----------------------------------------------------------------------------
-- food_locations
-- ----------------------------------------------------------------------------
INSERT INTO food_locations (name) VALUES
    ('Fridge'),
    ('Freezer'),
    ('Pantry'),
    ('Spice Rack'),
    ('Counter'),
    ('Bread Box'),
    ('Vegetable Drawer')
ON CONFLICT (name) DO NOTHING;


-- ============================================================================
-- 2.  Core entity tables
-- ============================================================================

-- ----------------------------------------------------------------------------
-- users
-- No UNIQUE constraint on username in the schema — WHERE NOT EXISTS
-- prevents inserting duplicates on re-runs.
-- ----------------------------------------------------------------------------
INSERT INTO users (username)
SELECT v.username
FROM (VALUES
    ('alice_foodie'::text),
    ('bob_chef'),
    ('charlie_eats')
) AS v(username)
WHERE NOT EXISTS (SELECT 1 FROM users WHERE username = v.username);


-- ----------------------------------------------------------------------------
-- pantry
-- No UNIQUE constraint on name — WHERE NOT EXISTS prevents duplicates.
-- ----------------------------------------------------------------------------
INSERT INTO pantry (name)
SELECT v.name
FROM (VALUES
    ('Alice''s Pantry'::text),
    ('Bob''s Kitchen')
) AS v(name)
WHERE NOT EXISTS (SELECT 1 FROM pantry WHERE name = v.name);


-- ----------------------------------------------------------------------------
-- recipes  — 8 sample recipes spanning diverse cuisines and meal types.
-- No UNIQUE constraint on name — WHERE NOT EXISTS prevents duplicates.
-- ----------------------------------------------------------------------------
INSERT INTO recipes
    (name, description, instructions, source_url,
     servings, prep_time_minutes, cook_time_minutes)
SELECT
    v.name, v.description, v.instructions, v.source_url,
    v.servings::int, v.prep::int, v.cook::int
FROM (VALUES
    (
        'Classic Spaghetti Bolognese'::text,
        'A hearty Italian meat sauce slow-cooked with tomato, onion, and garlic.'::text,
        E'1. Sauté onion and garlic in olive oil until soft.\n2. Brown the ground beef; season with salt and pepper.\n3. Pour in tomato sauce and simmer for 20 min.\n4. Cook spaghetti al dente; serve topped with sauce.'::text,
        'https://example.com/recipes/bolognese'::text,
        '4'::text, '15'::text, '30'::text
    ),
    (
        'Chicken Stir Fry',
        'Quick Asian-style stir fry with tender chicken and crisp broccoli.',
        E'1. Marinate chicken strips in soy sauce and cornstarch for 10 min.\n2. Stir-fry chicken in sesame oil for 5 min; set aside.\n3. Stir-fry broccoli and garlic for 3 min.\n4. Combine everything with fresh ginger.',
        'https://example.com/recipes/chicken-stir-fry',
        '2', '10', '15'
    ),
    (
        'Avocado Toast',
        'Simple and nutritious avocado toast — a perfect fast breakfast or light lunch.',
        E'1. Toast sourdough bread until golden.\n2. Mash avocado with lemon juice, salt, and pepper.\n3. Spread onto toast and finish with red pepper flakes.',
        NULL,
        '1', '5', '3'
    ),
    (
        'Banana Pancakes',
        'Fluffy, naturally sweetened pancakes made with ripe bananas.',
        E'1. Mash bananas; whisk in egg, flour, milk, baking powder, and vanilla.\n2. Cook on a buttered skillet over medium heat until golden.\n3. Serve warm with maple syrup.',
        'https://example.com/recipes/banana-pancakes',
        '2', '10', '15'
    ),
    (
        'Greek Salad',
        'A refreshing Mediterranean salad with crisp vegetables, olives, and feta.',
        E'1. Chop cucumber, cherry tomatoes, and red onion into bite-size pieces.\n2. Combine with kalamata olives and crumbled feta.\n3. Dress with olive oil, red wine vinegar, and dried oregano.',
        NULL,
        '3', '10', '0'
    ),
    (
        'Beef Tacos',
        'Classic Mexican-style beef tacos loaded with all the fixings.',
        E'1. Season ground beef with cumin and paprika; brown in a skillet.\n2. Warm taco shells in oven at 180 °C for 5 min.\n3. Fill shells with beef, cheddar, salsa, sour cream, and lettuce.\n4. Squeeze lime over the top before serving.',
        'https://example.com/recipes/beef-tacos',
        '4', '10', '20'
    ),
    (
        'Vegetable Curry',
        'A warming, aromatic chickpea and coconut curry served over basmati rice.',
        E'1. Sauté onion and garlic in olive oil until golden.\n2. Add curry powder and turmeric; toast for 1 min.\n3. Stir in chickpeas and coconut milk; simmer for 20 min.\n4. Serve over steamed basmati rice.',
        NULL,
        '4', '10', '25'
    ),
    (
        'Chocolate Chip Cookies',
        'Classic chewy bakery-style chocolate chip cookies.',
        E'1. Cream softened butter with brown and white sugar until light.\n2. Beat in eggs and vanilla extract.\n3. Fold in flour, baking soda, salt, and chocolate chips.\n4. Bake at 180 °C for 12 min until golden at the edges.',
        'https://example.com/recipes/choc-chip-cookies',
        '24', '15', '12'
    )
) AS v(name, description, instructions, source_url, servings, prep, cook)
WHERE NOT EXISTS (SELECT 1 FROM recipes WHERE name = v.name);


-- ============================================================================
-- 3.  Junction / relation tables  (depend on tables above)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- user_pantry
-- No UNIQUE(id_user, id_pantry) constraint in the schema — WHERE NOT EXISTS
-- prevents duplicate links on re-runs.
-- charlie_eats shares Alice's pantry to demonstrate multi-user ownership.
-- ----------------------------------------------------------------------------
INSERT INTO user_pantry (id_user, id_pantry)
SELECT u.id, p.id
FROM   users  u
JOIN   pantry p ON p.name = 'Alice''s Pantry'
WHERE  u.username = 'alice_foodie'
  AND  NOT EXISTS (
           SELECT 1 FROM user_pantry up
           WHERE  up.id_user = u.id AND up.id_pantry = p.id
       );

INSERT INTO user_pantry (id_user, id_pantry)
SELECT u.id, p.id
FROM   users  u
JOIN   pantry p ON p.name = 'Bob''s Kitchen'
WHERE  u.username = 'bob_chef'
  AND  NOT EXISTS (
           SELECT 1 FROM user_pantry up
           WHERE  up.id_user = u.id AND up.id_pantry = p.id
       );

INSERT INTO user_pantry (id_user, id_pantry)
SELECT u.id, p.id
FROM   users  u
JOIN   pantry p ON p.name = 'Alice''s Pantry'
WHERE  u.username = 'charlie_eats'
  AND  NOT EXISTS (
           SELECT 1 FROM user_pantry up
           WHERE  up.id_user = u.id AND up.id_pantry = p.id
       );


-- ----------------------------------------------------------------------------
-- recipe_ingredients
-- Rows are resolved to IDs via name-joins so the seed is resilient to
-- serial gaps between re-runs.  ON CONFLICT DO NOTHING guards re-runs.
-- Note: the same ingredient (Garlic, Olive Oil…) can appear across
-- multiple recipes — the PK is (recipe_id, ingredient_id) so that is fine.
-- ----------------------------------------------------------------------------
INSERT INTO recipe_ingredients (recipe_id, ingredient_id, quantity, unit_id, note)
SELECT r.id, i.id, q.qty, u.id, q.note
FROM (VALUES
    -- Classic Spaghetti Bolognese
    ('Classic Spaghetti Bolognese'::text, 'Spaghetti'::text,      400::numeric, 'g'::text,     NULL::text),
    ('Classic Spaghetti Bolognese',       'Ground Beef',           500,          'g',           'lean'),
    ('Classic Spaghetti Bolognese',       'Tomato Sauce',          400,          'ml',          'passata or canned crushed'),
    ('Classic Spaghetti Bolognese',       'Onion',                 1,            'piece',       'finely diced'),
    ('Classic Spaghetti Bolognese',       'Garlic',                3,            'clove',       'minced'),
    ('Classic Spaghetti Bolognese',       'Olive Oil',             2,            'tbsp',        NULL),
    ('Classic Spaghetti Bolognese',       'Salt',                  1,            'tsp',         NULL),
    ('Classic Spaghetti Bolognese',       'Black Pepper',          NULL,         'pinch',       'to taste'),
    -- Chicken Stir Fry
    ('Chicken Stir Fry',                  'Chicken Breast',        300,          'g',           'cut into strips'),
    ('Chicken Stir Fry',                  'Broccoli',              200,          'g',           'cut into florets'),
    ('Chicken Stir Fry',                  'Soy Sauce',             3,            'tbsp',        NULL),
    ('Chicken Stir Fry',                  'Ginger',                1,            'tsp',         'freshly grated'),
    ('Chicken Stir Fry',                  'Sesame Oil',            1,            'tbsp',        NULL),
    ('Chicken Stir Fry',                  'Cornstarch',            1,            'tbsp',        'for marinade'),
    ('Chicken Stir Fry',                  'Garlic',                2,            'clove',       'minced'),
    -- Avocado Toast
    ('Avocado Toast',                     'Avocado',               1,            'piece',       'ripe'),
    ('Avocado Toast',                     'Sourdough Bread',       2,            'slice',       NULL),
    ('Avocado Toast',                     'Lemon Juice',           1,            'tsp',         NULL),
    ('Avocado Toast',                     'Salt',                  1,            'pinch',       NULL),
    ('Avocado Toast',                     'Red Pepper Flakes',     NULL,         'pinch',       'optional'),
    -- Banana Pancakes
    ('Banana Pancakes',                   'Banana',                2,            'piece',       'very ripe'),
    ('Banana Pancakes',                   'Egg',                   1,            'piece',       NULL),
    ('Banana Pancakes',                   'All-Purpose Flour',     100,          'g',           NULL),
    ('Banana Pancakes',                   'Milk',                  120,          'ml',          NULL),
    ('Banana Pancakes',                   'Butter',                1,            'tbsp',        'for the pan'),
    ('Banana Pancakes',                   'Baking Powder',         1,            'tsp',         NULL),
    ('Banana Pancakes',                   'Vanilla Extract',       0.5,          'tsp',         NULL),
    -- Greek Salad
    ('Greek Salad',                       'Cucumber',              1,            'piece',       'halved and sliced'),
    ('Greek Salad',                       'Cherry Tomatoes',       200,          'g',           'halved'),
    ('Greek Salad',                       'Kalamata Olives',       80,           'g',           'pitted'),
    ('Greek Salad',                       'Feta Cheese',           100,          'g',           'crumbled'),
    ('Greek Salad',                       'Red Onion',             0.5,          'piece',       'thinly sliced'),
    ('Greek Salad',                       'Olive Oil',             3,            'tbsp',        NULL),
    ('Greek Salad',                       'Red Wine Vinegar',      1,            'tbsp',        NULL),
    ('Greek Salad',                       'Dried Oregano',         1,            'tsp',         NULL),
    -- Beef Tacos
    ('Beef Tacos',                        'Ground Beef',           500,          'g',           NULL),
    ('Beef Tacos',                        'Taco Shells',           8,            'piece',       NULL),
    ('Beef Tacos',                        'Cheddar Cheese',        100,          'g',           'shredded'),
    ('Beef Tacos',                        'Salsa',                 4,            'tbsp',        NULL),
    ('Beef Tacos',                        'Sour Cream',            4,            'tbsp',        NULL),
    ('Beef Tacos',                        'Romaine Lettuce',       1,            'bunch',       'shredded'),
    ('Beef Tacos',                        'Lime',                  1,            'piece',       'cut into wedges'),
    ('Beef Tacos',                        'Cumin',                 1,            'tsp',         NULL),
    ('Beef Tacos',                        'Paprika',               1,            'tsp',         NULL),
    -- Vegetable Curry
    ('Vegetable Curry',                   'Chickpeas',             400,          'g',           'canned, drained'),
    ('Vegetable Curry',                   'Coconut Milk',          400,          'ml',          'full fat'),
    ('Vegetable Curry',                   'Onion',                 1,            'piece',       'diced'),
    ('Vegetable Curry',                   'Garlic',                3,            'clove',       'minced'),
    ('Vegetable Curry',                   'Curry Powder',          2,            'tbsp',        NULL),
    ('Vegetable Curry',                   'Turmeric',              1,            'tsp',         NULL),
    ('Vegetable Curry',                   'Olive Oil',             2,            'tbsp',        NULL),
    ('Vegetable Curry',                   'Basmati Rice',          300,          'g',           'to serve'),
    -- Chocolate Chip Cookies
    ('Chocolate Chip Cookies',            'Chocolate Chips',       200,          'g',           NULL),
    ('Chocolate Chip Cookies',            'Butter',                225,          'g',           'softened'),
    ('Chocolate Chip Cookies',            'Brown Sugar',           200,          'g',           'packed'),
    ('Chocolate Chip Cookies',            'Sugar',                 100,          'g',           'white'),
    ('Chocolate Chip Cookies',            'Egg',                   2,            'piece',       NULL),
    ('Chocolate Chip Cookies',            'Vanilla Extract',       2,            'tsp',         NULL),
    ('Chocolate Chip Cookies',            'All-Purpose Flour',     280,          'g',           NULL),
    ('Chocolate Chip Cookies',            'Baking Soda',           1,            'tsp',         NULL),
    ('Chocolate Chip Cookies',            'Salt',                  0.5,          'tsp',         NULL)
) AS q(rname, iname, qty, uname, note)
JOIN recipes     r ON r.name = q.rname
JOIN ingredients i ON i.name = q.iname
JOIN units       u ON u.name = q.uname
ON CONFLICT (recipe_id, ingredient_id) DO NOTHING;


-- ----------------------------------------------------------------------------
-- recipe_tags
-- ----------------------------------------------------------------------------
INSERT INTO recipe_tags (recipe_id, tag_id)
SELECT r.id, t.id
FROM (VALUES
    ('Classic Spaghetti Bolognese'::text, 'Italian'::text),
    ('Classic Spaghetti Bolognese',       'Dinner'),
    ('Classic Spaghetti Bolognese',       'Comfort Food'),
    ('Classic Spaghetti Bolognese',       'Kid-Friendly'),
    ('Chicken Stir Fry',                  'Asian'),
    ('Chicken Stir Fry',                  'Quick'),
    ('Chicken Stir Fry',                  'Healthy'),
    ('Chicken Stir Fry',                  'Dinner'),
    ('Avocado Toast',                     'Breakfast'),
    ('Avocado Toast',                     'Lunch'),
    ('Avocado Toast',                     'Vegetarian'),
    ('Avocado Toast',                     'Quick'),
    ('Avocado Toast',                     'Healthy'),
    ('Banana Pancakes',                   'Breakfast'),
    ('Banana Pancakes',                   'Kid-Friendly'),
    ('Banana Pancakes',                   'Vegetarian'),
    ('Greek Salad',                       'Mediterranean'),
    ('Greek Salad',                       'Vegetarian'),
    ('Greek Salad',                       'Lunch'),
    ('Greek Salad',                       'Healthy'),
    ('Greek Salad',                       'Quick'),
    ('Beef Tacos',                        'Mexican'),
    ('Beef Tacos',                        'Dinner'),
    ('Beef Tacos',                        'Kid-Friendly'),
    ('Vegetable Curry',                   'Vegetarian'),
    ('Vegetable Curry',                   'Dairy-Free'),
    ('Vegetable Curry',                   'Dinner'),
    ('Vegetable Curry',                   'Meal Prep'),
    ('Vegetable Curry',                   'Budget-Friendly'),
    ('Chocolate Chip Cookies',            'Dessert'),
    ('Chocolate Chip Cookies',            'Kid-Friendly'),
    ('Chocolate Chip Cookies',            'Vegetarian')
) AS q(rname, tname)
JOIN recipes r ON r.name = q.rname
JOIN tags    t ON t.name = q.tname
ON CONFLICT (recipe_id, tag_id) DO NOTHING;


-- ----------------------------------------------------------------------------
-- pantry_ingredients
-- Note: ingredient_id carries a global UNIQUE constraint — each ingredient
-- can live in exactly one pantry at a time.  Ingredients are therefore
-- split between Alice's and Bob's pantry with no overlap.
--
-- Spices and staples stored without quantity tracking use quantity = 1
-- + is_quantified = false.  The app should display these as "in stock"
-- without showing the meaningless number 1.
-- ----------------------------------------------------------------------------

-- Alice's Pantry — dry goods, pantry staples, spices, condiments
INSERT INTO pantry_ingredients
    (ingredient_id, pantry_id, quantity, unit_id, location_id,
     note, is_quantified, expiration_date)
SELECT i.id, p.id, q.qty, u.id, l.id, q.note, q.is_q, q.exp::date
FROM (VALUES
    -- iname                    qty           uname      lname               note                 is_q   exp
    ('Spaghetti'::text,    500::numeric, 'g'::text,  'Pantry'::text,      NULL::text,           true::boolean, NULL::text),
    ('Tomato Sauce',       800,          'ml',        'Pantry',            'two cans',           true,          '2027-03-15'),
    ('Garlic',             1,            'piece',     'Counter',           'whole bulb',         true,          NULL),
    ('Onion',              3,            'piece',     'Vegetable Drawer',  NULL,                 true,          NULL),
    ('Olive Oil',          500,          'ml',        'Counter',           NULL,                 true,          NULL),
    -- Spices: quantity = 1 + is_quantified = false means "in stock, amount not tracked"
    ('Salt',               1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Black Pepper',       1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Curry Powder',       1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Turmeric',           1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Red Pepper Flakes',  1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Paprika',            1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Cumin',              1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    ('Dried Oregano',      1,            'g',         'Spice Rack',        NULL,                 false,         NULL),
    -- Baking staples
    ('All-Purpose Flour',  750,          'g',         'Pantry',            NULL,                 true,          '2027-01-01'),
    ('Sugar',              500,          'g',         'Pantry',            NULL,                 true,          NULL),
    ('Brown Sugar',        300,          'g',         'Pantry',            NULL,                 true,          NULL),
    ('Baking Soda',        200,          'g',         'Pantry',            NULL,                 true,          '2027-06-01'),
    ('Baking Powder',      100,          'g',         'Pantry',            NULL,                 true,          '2027-03-01'),
    ('Vanilla Extract',    100,          'ml',        'Pantry',            NULL,                 true,          '2027-08-01'),
    ('Chocolate Chips',    200,          'g',         'Pantry',            NULL,                 true,          '2027-02-01'),
    -- Canned / packaged goods
    ('Chickpeas',          400,          'g',         'Pantry',            'canned',             true,          '2027-12-01'),
    ('Coconut Milk',       400,          'ml',        'Pantry',            'one can',            true,          '2027-10-01'),
    ('Basmati Rice',       500,          'g',         'Pantry',            NULL,                 true,          '2027-05-01'),
    ('Taco Shells',        8,            'piece',     'Pantry',            NULL,                 true,          '2026-11-01'),
    ('Cornstarch',         200,          'g',         'Pantry',            NULL,                 true,          NULL),
    -- Condiments / liquids
    ('Soy Sauce',          150,          'ml',        'Pantry',            NULL,                 true,          NULL),
    ('Red Wine Vinegar',   250,          'ml',        'Pantry',            NULL,                 true,          NULL),
    ('Lemon Juice',        200,          'ml',        'Fridge',            'bottled',            true,          '2026-12-01'),
    ('Sourdough Bread',    1,            'piece',     'Bread Box',         'fresh loaf',         true,          '2026-07-12')
) AS q(iname, qty, uname, lname, note, is_q, exp)
JOIN ingredients    i ON i.name = q.iname
JOIN pantry         p ON p.name = 'Alice''s Pantry'
JOIN units          u ON u.name = q.uname
JOIN food_locations l ON l.name = q.lname
ON CONFLICT (ingredient_id) DO NOTHING;

-- Bob's Kitchen — proteins, fridge & freezer items, fresh produce
INSERT INTO pantry_ingredients
    (ingredient_id, pantry_id, quantity, unit_id, location_id,
     note, is_quantified, expiration_date)
SELECT i.id, p.id, q.qty, u.id, l.id, q.note, q.is_q, q.exp::date
FROM (VALUES
    -- iname                    qty           uname      lname               note                 is_q   exp
    ('Ground Beef'::text,  300::numeric, 'g'::text,  'Freezer'::text,     'from bulk buy',      true::boolean, '2026-09-01'::text),
    ('Chicken Breast',     400,          'g',         'Freezer',           'vacuum sealed',      true,          '2026-10-01'),
    ('Egg',                6,            'piece',     'Fridge',            NULL,                 true,          '2026-07-20'),
    ('Milk',               1,            'L',         'Fridge',            NULL,                 true,          '2026-07-14'),
    ('Butter',             250,          'g',         'Fridge',            NULL,                 true,          '2026-08-01'),
    ('Feta Cheese',        150,          'g',         'Fridge',            NULL,                 true,          '2026-07-25'),
    ('Cheddar Cheese',     200,          'g',         'Fridge',            'block',              true,          '2026-08-15'),
    ('Sour Cream',         200,          'ml',        'Fridge',            NULL,                 true,          '2026-07-18'),
    ('Salsa',              300,          'ml',        'Fridge',            'opened jar',         true,          '2026-07-28'),
    ('Avocado',            2,            'piece',     'Counter',           'ripening',           true,          '2026-07-11'),
    ('Banana',             4,            'piece',     'Counter',           NULL,                 true,          '2026-07-12'),
    ('Cucumber',           1,            'piece',     'Vegetable Drawer',  NULL,                 true,          '2026-07-15'),
    ('Cherry Tomatoes',    200,          'g',         'Fridge',            NULL,                 true,          '2026-07-13'),
    ('Red Onion',          2,            'piece',     'Counter',           NULL,                 true,          NULL),
    ('Romaine Lettuce',    1,            'bunch',     'Fridge',            NULL,                 true,          '2026-07-12'),
    ('Broccoli',           300,          'g',         'Fridge',            NULL,                 true,          '2026-07-13'),
    ('Ginger',             1,            'piece',     'Fridge',            'fresh root',         true,          '2026-07-30'),
    ('Kalamata Olives',    80,           'g',         'Fridge',            'opened jar',         true,          '2026-08-01'),
    ('Sesame Oil',         100,          'ml',        'Pantry',            NULL,                 true,          NULL),
    ('Lime',               3,            'piece',     'Fridge',            NULL,                 true,          '2026-07-20')
) AS q(iname, qty, uname, lname, note, is_q, exp)
JOIN ingredients    i ON i.name = q.iname
JOIN pantry         p ON p.name = 'Bob''s Kitchen'
JOIN units          u ON u.name = q.uname
JOIN food_locations l ON l.name = q.lname
ON CONFLICT (ingredient_id) DO NOTHING;


-- ----------------------------------------------------------------------------
-- past_cooked_recipes
-- One row per recipe cooked at least once.  Uses a name-join to look up
-- the bigint recipe PK — resilient to serial gaps between re-runs.
-- ON CONFLICT DO NOTHING prevents duplicate rows on re-runs.
-- ----------------------------------------------------------------------------
INSERT INTO past_cooked_recipes (recipe_id, times_cooked, last_cooked_at)
SELECT r.id, q.times_cooked, q.last_cooked_at
FROM (VALUES
    ('Classic Spaghetti Bolognese'::text,  7::int, '2026-07-01 18:30:00+00'::timestamptz),
    ('Chicken Stir Fry',                   4,      '2026-06-20 19:00:00+00'),
    ('Avocado Toast',                      12,     '2026-07-07 08:15:00+00'),
    ('Banana Pancakes',                    3,      '2026-05-18 09:00:00+00'),
    ('Vegetable Curry',                    5,      '2026-06-30 20:00:00+00'),
    ('Beef Tacos',                         2,      '2026-06-10 19:30:00+00')
) AS q(rname, times_cooked, last_cooked_at)
JOIN recipes r ON r.name = q.rname
ON CONFLICT (recipe_id) DO NOTHING;


-- ----------------------------------------------------------------------------
-- api_keys  (extra test keys beyond the default seeded in 02-init)
-- ----------------------------------------------------------------------------
INSERT INTO api_keys (key) VALUES
    ('a1b2c3d4-0000-4000-8000-111111111111'),
    ('b2c3d4e5-0000-4000-8000-222222222222')
ON CONFLICT (key) DO NOTHING;
