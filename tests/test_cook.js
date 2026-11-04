// Run with: node tests/test_cook.js   (no dependencies)
const assert = require('assert');
const { findDurations, fmtMinutes, ingredientKeys, matchIngredients } = require('../static/js/cook.js');

const mins = (t) => findDurations(t).map((d) => d.minutes);
assert.deepStrictEqual(mins('Simmer for 10 minutes until thick.'), [10]);
assert.deepStrictEqual(mins('Rest the dough 30 mins, then bake 1 hour.'), [30, 60]);
assert.deepStrictEqual(mins('Marinate the meat for 3-4 hrs'), [180]);
assert.strictEqual(findDurations('Marinate the meat for 3-4 hrs')[0].maxMinutes, 240);
assert.deepStrictEqual(mins('Bake 1 hour 30 minutes.'), [90]);
assert.deepStrictEqual(mins('Bake for 1½ hours'), [90]);
assert.deepStrictEqual(mins('Bake for 1 1/2 hours'), [90]);
assert.deepStrictEqual(mins('Cook in 30-second bursts'), [0.5]);
assert.deepStrictEqual(mins('Leave for an hour.'), [60]);
assert.deepStrictEqual(mins('Stir well and serve.'), []);
assert.deepStrictEqual(mins('Preheat to 200C and add 2 cups flour'), []);
assert.deepStrictEqual(mins('Flip every 30 seconds'), [0.5]);

assert.strictEqual(fmtMinutes(10), '10 min');
assert.strictEqual(fmtMinutes(90), '1 hr 30 min');
assert.strictEqual(fmtMinutes(0.5), '30 sec');
assert.strictEqual(fmtMinutes(180), '3 hr');

assert.strictEqual(ingredientKeys('250 g bread flour, sifted').head, 'flour');
assert.strictEqual(ingredientKeys('3 cloves garlic, minced').head, 'garlic');
assert.strictEqual(ingredientKeys('Juice of 1 lime').head, 'lime');
assert.strictEqual(ingredientKeys('2 tbsp olive oil (extra virgin)').head, 'oil');
assert.strictEqual(ingredientKeys('6 egg yolks').head, 'yolk');

const ings = [
  { text: '250 g bread flour', section: 'Pastry' },
  { text: '1 tsp salt', section: 'Pastry' },
  { text: '200 g butter, cold', section: 'Pastry' },
  { text: '500 ml whole milk', section: 'Custard' },
  { text: '6 egg yolks', section: 'Custard' },
  { text: '1 cinnamon stick', section: 'Custard' },
  { text: '1 tsp salt', section: 'Custard' },
];
const names = (r) => r.map((i) => i.text);
assert.deepStrictEqual(names(matchIngredients('Mix flour, salt and water into a smooth dough.', ings, 'Pastry')), ['250 g bread flour', '1 tsp salt']);
assert.deepStrictEqual(names(matchIngredients('Heat the milk with the cinnamon, then whisk in the yolks.', ings, 'Custard')), ['500 ml whole milk', '6 egg yolks', '1 cinnamon stick']);
// A step that only mentions an ingredient from another section still finds it
assert.deepStrictEqual(names(matchIngredients('Fold in the butter.', ings, 'Custard')), ['200 g butter, cold']);
// Plural/singular
assert.deepStrictEqual(names(matchIngredients('Beat the egg yolk.', ings, '')), ['6 egg yolks']);
assert.deepStrictEqual(names(matchIngredients('Let it rest.', ings, '')), []);
console.log('cook.js: all checks passed');

// Rough waits: "overnight" and "until doubled"
const dur = (t) => findDurations(t).map((d) => ({ minutes: d.minutes, maxMinutes: d.maxMinutes, approx: d.approx }));
assert.deepStrictEqual(dur('Cover and refrigerate overnight.'), [{ minutes: 480, maxMinutes: 720, approx: true }]);
assert.strictEqual(findDurations('Cover and refrigerate overnight.')[0].text, 'overnight');
assert.deepStrictEqual(dur('Leave to rise until doubled in size.'), [{ minutes: 60, maxMinutes: 90, approx: true }]);
assert.strictEqual(findDurations('Leave to rise until doubled in size.')[0].text, 'until doubled in size');
assert.deepStrictEqual(dur('Leave for 1-2 hours until doubled.'), [{ minutes: 60, maxMinutes: 120, approx: false }]);
assert.deepStrictEqual(dur('Simmer 2–3 hours, then rest 10 minutes.'),
  [{ minutes: 120, maxMinutes: 180, approx: false }, { minutes: 10, maxMinutes: 10, approx: false }]);
assert.deepStrictEqual(dur('Prove until it has doubled, then bake for 25 minutes.'), [{ minutes: 25, maxMinutes: 25, approx: false }]);
assert.deepStrictEqual(dur('Bake 1 hour 30 minutes.'), [{ minutes: 90, maxMinutes: 90, approx: false }]);
// Text order holds when a rough wait comes after a plain one
assert.deepStrictEqual(findDurations('Bake 20 minutes, cool, then chill overnight.').map((d) => d.text), ['20 minutes', 'overnight']);
assert.deepStrictEqual(findDurations('Chill overnight, then bake 20 minutes.').map((d) => d.text), ['overnight', '20 minutes']);

// Group words bring in a whole section: "spread the filling" means everything under "# Filling"
const pizza = [
  { text: '500 g flour', section: 'Dough' },
  { text: '7 g yeast', section: 'Dough' },
  { text: '300 ml water', section: 'Dough' },
  { text: '200 g ricotta', section: 'Filling' },
  { text: '1 lemon, zested', section: 'Filling' },
];
assert.deepStrictEqual(names(matchIngredients('Roll out the dough and spread the filling over it', pizza, '')),
  ['500 g flour', '7 g yeast', '300 ml water', '200 g ricotta', '1 lemon, zested']);
assert.deepStrictEqual(names(matchIngredients('Knead the dough for 10 minutes', pizza, 'Dough')), []);
assert.deepStrictEqual(names(matchIngredients('Add the mixture to the pan', pizza, '')), []);
const pasta = [{ text: '400 g pasta' }, { text: '1 cup tomato sauce' }];
assert.deepStrictEqual(names(matchIngredients('Pour the sauce over the pasta', pasta, '')), ['400 g pasta', '1 cup tomato sauce']);
// Spread the filling from inside the Dough section: the Filling comes in, no repeats, ingredient order kept
assert.deepStrictEqual(names(matchIngredients('Spread the filling over the dough, then add the ricotta', pizza, 'Dough')),
  ['200 g ricotta', '1 lemon, zested']);
console.log('cook.js: rough waits and group words passed');

// Parity with StepDurations.swift (IOS/RecipeManagerTests/CookAndExportTests.swift has the same cases)
assert.deepStrictEqual(mins('Bake for 1.5 hours'), [90]);
assert.deepStrictEqual(mins('Bake for 1,5 hours'), [90]);
assert.deepStrictEqual(mins('Rest for 1/2 hour'), [30]);
assert.deepStrictEqual(mins('Rest for ½ hour'), [30]);
assert.deepStrictEqual(mins('Simmer for one hour'), [60]);
assert.deepStrictEqual(mins('Stir for a minute'), [1]);
assert.deepStrictEqual(mins('Whisk for 45 secs'), [0.75]);
assert.deepStrictEqual(mins('Bake 1 hour and 30 minutes'), [90]);
assert.deepStrictEqual(mins('Roast 1 hr, 15 min'), [75]);
assert.deepStrictEqual(mins('Microwave 2 minutes 30 seconds'), [2.5]);
assert.strictEqual(findDurations('Roast 1 hr, 15 min').map((d) => d.text)[0], '1 hr, 15 min');
assert.strictEqual(findDurations('Bake 2-3 hours and 30 minutes')[0].maxMinutes, 150);
// Only a smaller unit joins, and only across "and", "," or "&"
assert.deepStrictEqual(mins('Rest 10 minutes and 1 hour'), [10, 60]);
assert.deepStrictEqual(mins('Bake 2 hours, then 30 minutes more'), [120, 30]);
// The 72-hour cap
assert.deepStrictEqual(mins('Cure for 72 hours'), [4320]);
assert.deepStrictEqual(mins('Age for 100 hours'), []);
console.log('cook.js: decimals, fractions, words, seconds, joining and the cap passed');
