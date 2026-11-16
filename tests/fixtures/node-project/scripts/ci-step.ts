// Stands in for a project's script and fails when node-ci.yml or the setup action set the job up
// wrong: the Node.js and pnpm versions, the working directory, the installed dependencies and,
// for the browser script, the Playwright image.
import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { basename } from 'node:path'

const step = process.argv[2]
assert.ok(step, 'usage: node scripts/ci-step.ts <step>')

const nodeMajor = Number(process.versions.node.split('.')[0])
assert.equal(nodeMajor, 24, `expected Node.js 24, got ${process.versions.node}`)

const userAgent = process.env.npm_config_user_agent ?? ''
assert.match(userAgent, /^pnpm\/12\./, `expected pnpm 12, got "${userAgent}"`)

assert.equal(basename(process.cwd()), 'node-project', `ran in ${process.cwd()}`)
assert.ok(existsSync('node_modules/typescript'), 'the dependencies are not installed')

if (step === 'test:browser') {
  const browsers = process.env.PLAYWRIGHT_BROWSERS_PATH
  assert.ok(browsers && existsSync(browsers), 'not running in the Playwright image')
}

console.log(`${step}: Node.js ${process.versions.node}, ${userAgent.split(' ')[0]}`)
