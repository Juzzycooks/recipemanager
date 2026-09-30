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
