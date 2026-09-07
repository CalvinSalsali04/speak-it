/* What the page may claim about money.
 *
 * These are not style checks. Every one of them is a defect the site has
 * actually shipped or was about to: a struck-through monthly "regular" price
 * the app never implemented, an annual plan that cost more than paying monthly
 * while being called the better value, and a free-tier count that drifted away
 * from the app's own allowance. A page that disagrees with the App Store sheet
 * is a refund. */
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');

const root=path.join(__dirname,'..','..');
const page=fs.readFileSync(path.join(root,'Website','index.html'),'utf8');
const conversion=fs.readFileSync(path.join(root,'Website','assets','conversion.js'),'utf8');
const allowance=fs.readFileSync(
  path.join(root,'SpeakIt','Features','Setup','SubscriptionStore.swift'),'utf8');

/* The <p> inside .price-options whose period text ends with `unit`. */
function planParagraph(unit){
  const match=page.match(new RegExp('<p>(?:(?!</p>).)*?/ '+unit+'</span></p>','s'));
  assert.ok(match,`no ${unit} plan paragraph on the page`);
  return match[0];
}
function amount(markup){
  const match=markup.match(/\$(\d+(?:\.\d{2})?)/);
  assert.ok(match,`no price in ${markup}`);
  return Number(match[1]);
}

const monthly=planParagraph('month');
const annual=planParagraph('year');

test('both Pro plans are priced on the page',()=>{
  assert.ok(amount(monthly)>0);
  assert.ok(amount(annual)>0);
});

test('annual costs less than twelve monthly payments',()=>{
  // The reason monthly moved to $2.99. Whichever plan the page presents as the
  // better value has to actually be cheaper, or the claim is unsupportable.
  assert.ok(
    amount(annual)<amount(monthly)*12,
    `annual $${amount(annual)} must beat twelve months at $${amount(monthly)} ($${(amount(monthly)*12).toFixed(2)})`
  );
});

test('monthly claims no discount it does not have',()=>{
  // SpeakItProView's priceColumn strikes a regular price through for the annual
  // plan only. The page printed a struck-through $3.99 monthly for weeks that
  // the app never implemented.
  assert.doesNotMatch(monthly,/<s[\s>]/,'monthly must not strike a regular price through');
  assert.doesNotMatch(monthly,/regularly/i);
  assert.doesNotMatch(monthly,/data-annual/,'the annual sale hooks must not reach monthly');
});

test('the launch offer is annual-only and reversible from one place',()=>{
  const flag=conversion.match(/var LAUNCH_ANNUAL_PRICE\s*=\s*'([^']*)'/);
  assert.ok(flag,'conversion.js must own the launch price in one constant');
  if(flag[1]!==''){
    assert.match(flag[1],/^\$\d+(\.\d{2})?$/,'a set launch price must be a plain US amount');
    const sale=Number(flag[1].slice(1));
    assert.ok(sale<amount(annual),'a launch price that is not lower is not an offer');
    assert.ok(sale<amount(monthly)*12,'the launch price must still beat twelve monthly payments');
  }
  // Nothing in the mechanism may reach the monthly plan.
  assert.doesNotMatch(conversion,/data-monthly-(was|price)/);
});

test('no end date is published for the offer',()=>{
  // Deliberate: the site states the discount, not a deadline, so the offer can
  // be ended or extended without the page having lied. The app's own caption
  // carries the date, because App Store Connect is what enforces it.
  const note=page.match(/data-launch-note[^>]*>([^<]*)</);
  assert.ok(note,'the launch note must exist, hidden, ready for the flag');
  assert.doesNotMatch(note[1],/\b20\d\d\b/,'no year belongs in the page-side offer note');
});

test('the free tier matches the app allowance',()=>{
  const limit=allowance.match(/lifetimeCaptureLimit\s*=\s*(\d+)/);
  assert.ok(limit,'FreePlanAllowance.lifetimeCaptureLimit not found');
  assert.match(
    page,
    new RegExp('first '+limit[1]+' captures'),
    `the page must offer the same ${limit[1]} captures the app grants`
  );
});

test('the page prices nothing the app does not sell',()=>{
  // Speak It sells one subscription in two periods. A third price on the page
  // would be advertising something the paywall cannot deliver.
  const prices=new Set((page.match(/\$\d+(?:\.\d{2})?/g)||[]));
  prices.delete('$0');
  assert.equal(prices.size,2,`unexpected prices on the page: ${[...prices].join(', ')}`);
});
