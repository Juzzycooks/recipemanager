// Run with: node tests/test_unitconv.js   (no dependencies). Mirrors UnitConversionTests in IOS/RecipeManagerTests.
const assert = require('assert');
const { convert, use } = require('../static/unitconv.js');
use(require('../static/unit-ingredients.json'));
const metric = (s) => convert(s, 'metric'), us = (s) => convert(s, 'imperial');

assert.strictEqual(metric('1 lb chicken thighs'), '450 g chicken thighs');
assert.strictEqual(metric('2 lb potatoes'), '910 g potatoes');
assert.strictEqual(metric('4 oz cheddar, grated'), '110 g cheddar, grated');
assert.strictEqual(metric('5 lb beef'), '2.25 kg beef');
assert.strictEqual(metric('1 1/2 tbsp honey'), '1 1/2 tbsp honey');   // spoons stay spoons
assert.strictEqual(metric('1/2 tsp salt'), '1/2 tsp salt');
assert.strictEqual(us('15 ml soy sauce'), '1 tbsp soy sauce');
assert.strictEqual(metric('8 fl oz milk'), '240 ml milk');
assert.strictEqual(metric('8 oz milk'), '240 ml milk');
assert.strictEqual(us('500 g flour'), '4 ¼ cups flour');   // US bakers measure flour in cups
assert.strictEqual(us('250 ml cream'), '1 cup cream');
assert.strictEqual(us('1 kg onions'), '2 ¼ lb onions');
assert.strictEqual(metric('2-3 lb brisket'), '0.9–1.35 kg brisket');
assert.strictEqual(metric('½ cup oil'), '120 ml oil');
assert.strictEqual(metric('1 lb (450 g) flour'), '450 g flour');
assert.strictEqual(us('450 g (1 lb) flour'), '1 lb flour');
assert.strictEqual(metric('Bake at 350°F for 20 minutes.'), 'Bake at 175°C for 20 minutes.');
assert.strictEqual(metric('Heat the oven to 400 degrees F'), 'Heat the oven to 205°C');
assert.strictEqual(metric('preheat to 350°F (180°C)'), 'preheat to 180°C');
assert.strictEqual(us('Bake at 180°C'), 'Bake at 355°F');
// Cups depend on the ingredient: dry goods are weighed, liquids poured, anything unknown stays a cup.
assert.strictEqual(metric('½ cup nuts'), '65 g nuts');
assert.strictEqual(metric('1/2 cup chopped walnuts'), '60 g chopped walnuts');
assert.strictEqual(metric('1 cup rice'), '190 g rice');
assert.strictEqual(metric('2 cups plain flour'), '240 g plain flour');
assert.strictEqual(metric('1 cup light brown sugar'), '210 g light brown sugar');
assert.strictEqual(metric('½ cup peanut butter'), '140 g peanut butter');
assert.strictEqual(metric('1 cup buttermilk'), '240 ml buttermilk');
assert.strictEqual(metric('1 cup milk chocolate chips'), '170 g milk chocolate chips');
assert.strictEqual(metric('1 cup water, plus flour for dusting'), '240 ml water, plus flour for dusting');
assert.strictEqual(metric('1 cup frozen peas'), '1 cup frozen peas');
assert.strictEqual(metric('1 cup (150 g) frozen peas'), '150 g frozen peas');
assert.strictEqual(metric('Stir in 1 cup sugar, then 1 cup stock.'), 'Stir in 200 g sugar, then 240 ml stock.');
assert.strictEqual(us('100 g walnuts'), '¾ cup walnuts');
assert.strictEqual(us('1 kg flour'), '8 ¼ cups flour');
assert.strictEqual(us('250 g butter'), '9 oz butter');   // butter stays a weight
assert.strictEqual(metric('8 oz boiling water'), '240 ml boiling water');
assert.strictEqual(metric('3 eggs'), '3 eggs');
assert.strictEqual(metric('a pinch of salt'), 'a pinch of salt');
assert.strictEqual(metric('250 g flour'), '250 g flour');
assert.strictEqual(metric('2 garlic cloves'), '2 garlic cloves');
assert.strictEqual(convert('1 lb beef', 'original'), '1 lb beef');
console.log('unitconv ok');
