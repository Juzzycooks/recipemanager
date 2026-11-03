// Run with: node tests/test_units.js   (no dependencies). Mirrors IngredientScalingTests in IOS/RecipeManagerTests.
// units.js only attaches itself to `window`, so it is loaded into a sandbox with a bare one.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const sandbox = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../static/units.js'), 'utf8'), sandbox);
const { scaleLine } = sandbox.window.RecipeUnits;

// Mixed numbers, fractions, glyphs and decimals.
assert.strictEqual(scaleLine('1 1/2 cups flour', 2), '3 cups flour');
assert.strictEqual(scaleLine('½ cup oil', 2), '1 cup oil');
assert.strictEqual(scaleLine('1½ tbsp honey', 2), '3 tbsp honey');
assert.strictEqual(scaleLine('1 ½ tbsp honey', 2), '3 tbsp honey');
assert.strictEqual(scaleLine('1/2 tsp salt', 3), '1 ½ tsp salt');
assert.strictEqual(scaleLine('0.5 kg beef', 3), '1 ½ kg beef');
assert.strictEqual(scaleLine('1,5 l stock', 2), '3 l stock');
assert.strictEqual(scaleLine('.5 cup milk', 3), '1 ½ cup milk');
assert.strictEqual(scaleLine('⅛ tsp chilli', 2), '¼ tsp chilli');

// Results come out as ¼ ⅓ ½ ⅔ ¾ when within 0.05, otherwise rounded to two places.
assert.strictEqual(scaleLine('3 eggs', 0.5), '1 ½ eggs');
assert.strictEqual(scaleLine('1/3 cup sugar', 2), '⅔ cup sugar');
assert.strictEqual(scaleLine('2/3 cup sugar', 0.5), '⅓ cup sugar');
assert.strictEqual(scaleLine('3/4 cup milk', 3), '2 ¼ cup milk');
assert.strictEqual(scaleLine('1 1/4 cups milk', 0.5), '⅔ cups milk');
assert.strictEqual(scaleLine('2 1/3 cups', 3), '7 cups');
assert.strictEqual(scaleLine('1/8 tsp salt', 0.5), '0.06 tsp salt');
assert.strictEqual(scaleLine('10 g yeast', 0.33), '3 ⅓ g yeast');
assert.strictEqual(scaleLine('250 g butter', 3), '750 g butter');
assert.strictEqual(scaleLine('0 g', 2), '0 g');
assert.strictEqual(scaleLine('2', 2), '4');

// Only the leading amount changes; a unit glued to it is split off.
assert.strictEqual(scaleLine('2 x 400g tins tomatoes', 2), '4 x 400g tins tomatoes');
assert.strictEqual(scaleLine('400g flour', 0.5), '200 g flour');
assert.strictEqual(scaleLine('1 egg', 3), '3 egg');
assert.strictEqual(scaleLine('  2 eggs', 2), '  4 eggs');

// Left alone: no leading amount, 1x, an amount that isn't a number.
assert.strictEqual(scaleLine('Salt and pepper', 2), 'Salt and pepper');
assert.strictEqual(scaleLine('a pinch of salt', 2), 'a pinch of salt');
assert.strictEqual(scaleLine('Serves 4', 2), 'Serves 4');
assert.strictEqual(scaleLine('100g', 1), '100g');
assert.strictEqual(scaleLine('1/0 cup water', 2), '1/0 cup water');

// Ranges scale both ends and keep their separator; a broken end leaves the line alone.
assert.strictEqual(scaleLine('1-2 cloves garlic', 2), '2-4 cloves garlic');
assert.strictEqual(scaleLine('1–2 cloves garlic', 2), '2–4 cloves garlic');
assert.strictEqual(scaleLine('1 - 2 tbsp oil', 3), '3 - 6 tbsp oil');
assert.strictEqual(scaleLine('1 to 2 cups stock', 2), '2 to 4 cups stock');
assert.strictEqual(scaleLine('½-1 cup milk', 2), '1-2 cup milk');
assert.strictEqual(scaleLine('1 1/2-2 cups flour', 0.5), '¾-1 cups flour');
assert.strictEqual(scaleLine('2-3 x 400g tins', 2), '4-6 x 400g tins');
assert.strictEqual(scaleLine('2-1/0 cup water', 2), '2-1/0 cup water');
assert.strictEqual(scaleLine('2 tomatoes', 2), '4 tomatoes');
assert.strictEqual(scaleLine('3 to taste', 2), '6 to taste');

// Thousands commas (groups of exactly three) vs decimal commas; results print without a separator.
assert.strictEqual(scaleLine('1,000 g flour', 2), '2000 g flour');
assert.strictEqual(scaleLine('1,500 ml water', 0.5), '750 ml water');
assert.strictEqual(scaleLine('1,000.5 g', 2), '2001 g');
assert.strictEqual(scaleLine('1,000-2,000 g', 0.5), '500-1000 g');
assert.strictEqual(scaleLine('1,25 l milk', 2), '2 ½ l milk');

// Known quirks, pinned so the iPhone port stays in step: a hyphenated word after the amount is split off,
// and a leading temperature is scaled like any other amount.
assert.strictEqual(scaleLine('1-inch piece ginger', 2), '2 -inch piece ginger');
assert.strictEqual(scaleLine('180°C oven', 2), '360 °C oven');

console.log('units.js scaling: all tests passed');
