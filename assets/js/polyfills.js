// Node built-in shims for the browser bundle. Web3Auth + its transitive
// deps (@toruslabs/eccrypto, @solana/spl-token, etc.) reference Buffer,
// process, and global as true globals the way Webpack would auto-polyfill.
// Esbuild doesn't — so we attach them to globalThis at module init time,
// BEFORE any downstream import chains try to evaluate module-level code
// that touches them.
//
// MUST stay import-only (no exports). The side-effect assignments here
// are the whole point. This file must be imported as the very first
// `import` in app.js so its init runs ahead of every other module.

import { Buffer } from "buffer"
import process from "process"

const g = typeof globalThis !== "undefined" ? globalThis : window

if (typeof g.Buffer === "undefined") g.Buffer = Buffer
if (typeof g.process === "undefined") g.process = process
if (typeof g.global === "undefined") g.global = g
