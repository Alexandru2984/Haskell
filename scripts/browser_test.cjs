'use strict';
const {chromium} = require('playwright');
const AxeBuilder = require('@axe-core/playwright').default;
const assert = require('node:assert/strict');
const fs = require('node:fs');
const base = process.env.TEST_BASE_URL || 'http://127.0.0.1:19060';
assert(['127.0.0.1','localhost','[::1]'].includes(new URL(base).hostname) && new URL(base).port !== '3060', 'Use an isolated loopback test instance');
assert(process.env.TEST_USERNAME && process.env.TEST_PASSWORD, 'Set test credentials');
(async () => {
  fs.mkdirSync('artifacts',{recursive:true});
  const browser = await chromium.launch({headless:true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? {executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE} : {})});
  let checks = 0;
  try {
    const context = await browser.newContext({httpCredentials:{username:process.env.TEST_USERNAME,password:process.env.TEST_PASSWORD}, reducedMotion:'reduce'});
    await context.addInitScript(() => localStorage.setItem('pulse-theme','light'));
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('console',message=>{if(message.type()==='error') errors.push(message.text());});
    const endpoints = await (await context.request.get(base + '/api/endpoints')).json();
    const detail = endpoints.length ? '/endpoints/' + endpoints[0].endpointId : '/endpoints/new';
    for (const width of [320,375,768,1440]) {
      await page.setViewportSize({width,height:1000});
      for (const route of ['/', '/endpoints', '/endpoints/new', '/incidents', '/playground', detail]) {
        const response = await page.goto(base + route);
        assert.equal(response.status(),200, route);
        await page.waitForLoadState('networkidle');
        assert(await page.evaluate(()=>document.documentElement.scrollWidth <= innerWidth + 1), `Horizontal page overflow: ${width} ${route}`);
        checks++;
      }
      await page.goto(base + '/');
      await page.screenshot({path:`artifacts/overview-${width}.png`,fullPage:true});
    }
    await page.setViewportSize({width:1440,height:1000});
    await page.goto(base + '/endpoints');
    await page.keyboard.press('/');
    assert.equal(await page.locator('#monitor-search').evaluate(el=>document.activeElement===el),true);
    await page.locator('#monitor-search').fill('this-monitor-does-not-exist');
    assert.equal(await page.locator('#filter-empty').isVisible(),true);
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#monitor-search').inputValue(),'');
    checks += 3;
    await page.goto(base + '/playground');
    await page.getByRole('button',{name:'Health endpoint',exact:true}).click();
    await page.getByRole('button',{name:'Run validation',exact:false}).click();
    await page.waitForFunction(()=>document.querySelector('#playground-result').textContent.includes('All checks passed'));
    await page.getByRole('button',{name:'Breaking change',exact:true}).click();
    await page.getByRole('button',{name:'Run validation',exact:false}).click();
    await page.waitForFunction(()=>document.querySelector('#playground-result').textContent.includes('Missing required field'));
    checks += 2;
    for (const route of ['/', '/endpoints', '/endpoints/new', '/playground', '/incidents', detail]) {
      await page.goto(base + route);
      const results = await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21a','wcag21aa']).analyze();
      assert.deepEqual(results.violations.map(v=>({id:v.id,impact:v.impact,nodes:v.nodes.map(n=>n.target)})),[], `Accessibility violations: ${route}`);
      checks++;
    }
    await page.goto(base + '/');
    await page.getByRole('button',{name:/theme/i}).click();
    assert.equal(await page.locator('html').getAttribute('data-theme'),'dark');
    await page.screenshot({path:'artifacts/overview-dark.png',fullPage:true});
    const dark = await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa']).analyze();
    assert.deepEqual(dark.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)})),[],'Dark theme accessibility');
    checks+=2;
    assert.deepEqual(errors, [], 'Browser errors');
    console.log(`${checks} browser assertions passed; screenshots in artifacts/`);
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
