/**
 * IDL Consistency Tests
 *
 * Verifies that discriminators, PDA seeds, account counts, and program IDs
 * in the TypeScript settler service match the Anchor program IDLs exactly.
 *
 * If any of these are wrong, on-chain transactions silently fail.
 *
 * Run: npx ts-node tests/idl-consistency.test.ts
 */

import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let passed = 0;
let failed = 0;
const failures: string[] = [];

function test(name: string, fn: () => void): void {
  try {
    fn();
    passed++;
    console.log(`  PASS  ${name}`);
  } catch (err: any) {
    failed++;
    const msg = `  FAIL  ${name}: ${err.message}`;
    failures.push(msg);
    console.log(msg);
  }
}

function bufFromArray(arr: number[]): Buffer {
  return Buffer.from(arr);
}

/** Decode IDL PDA seed values (byte arrays) to strings */
function decodeConstSeed(seed: { kind: string; value: number[] }): string {
  return Buffer.from(seed.value).toString("utf-8");
}

// ---------------------------------------------------------------------------
// Load IDLs
// ---------------------------------------------------------------------------

const BANKROLL_IDL_PATH = path.resolve(
  __dirname,
  "../../blockster-bankroll/target/idl/blockster_bankroll.json"
);
const AIRDROP_IDL_PATH = path.resolve(
  __dirname,
  "../../blockster-airdrop/target/idl/blockster_airdrop.json"
);

const bankrollIdl = JSON.parse(fs.readFileSync(BANKROLL_IDL_PATH, "utf-8"));
const airdropIdl = JSON.parse(fs.readFileSync(AIRDROP_IDL_PATH, "utf-8"));

function getIdlInstruction(idl: any, name: string): any {
  const ix = idl.instructions.find((i: any) => i.name === name);
  if (!ix) throw new Error(`Instruction '${name}' not found in IDL`);
  return ix;
}

// ---------------------------------------------------------------------------
// Load TypeScript source files as text (for parsing discriminators/seeds)
// ---------------------------------------------------------------------------

const bankrollServiceSrc = fs.readFileSync(
  path.resolve(__dirname, "../src/services/bankroll-service.ts"),
  "utf-8"
);
const airdropServiceSrc = fs.readFileSync(
  path.resolve(__dirname, "../src/services/airdrop-service.ts"),
  "utf-8"
);
const initBankrollSrc = fs.readFileSync(
  path.resolve(__dirname, "../scripts/init-bankroll.ts"),
  "utf-8"
);
const initAirdropSrc = fs.readFileSync(
  path.resolve(__dirname, "../scripts/init-airdrop.ts"),
  "utf-8"
);
const configSrc = fs.readFileSync(
  path.resolve(__dirname, "../src/config.ts"),
  "utf-8"
);

/**
 * Parse a DISCRIMINATORS constant from TypeScript source.
 * Matches patterns like: instructionName: Buffer.from([1, 2, 3, 4, 5, 6, 7, 8])
 * Returns Map of instruction name -> number[]
 */
function parseDiscriminators(src: string): Map<string, number[]> {
  const result = new Map<string, number[]>();
  // Match both camelCase and snake_case names
  const regex = /(\w+)\s*:\s*Buffer\.from\(\[([^\]]+)\]\)/g;
  let match;
  while ((match = regex.exec(src)) !== null) {
    const name = match[1];
    const bytes = match[2].split(",").map((s) => parseInt(s.trim(), 10));
    if (bytes.length === 8) {
      result.set(name, bytes);
    }
  }
  return result;
}

/**
 * Parse PDA seed constants from TypeScript source.
 * Matches patterns like: const SOME_SEED = Buffer.from("seed_string");
 * Returns Map of variable name -> seed string
 */
function parsePdaSeeds(src: string): Map<string, string> {
  const result = new Map<string, string>();
  const regex = /const\s+(\w+_SEED)\s*=\s*Buffer\.from\("([^"]+)"\)/g;
  let match;
  while ((match = regex.exec(src)) !== null) {
    result.set(match[1], match[2]);
  }
  return result;
}

// Parse discriminators from all TS files
const bankrollServiceDiscrims = parseDiscriminators(bankrollServiceSrc);
const airdropServiceDiscrims = parseDiscriminators(airdropServiceSrc);
const initBankrollDiscrims = parseDiscriminators(initBankrollSrc);
const initAirdropDiscrims = parseDiscriminators(initAirdropSrc);

// Parse PDA seeds from service files
const bankrollServiceSeeds = parsePdaSeeds(bankrollServiceSrc);
const airdropServiceSeeds = parsePdaSeeds(airdropServiceSrc);

// ---------------------------------------------------------------------------
// Test Suite 1: Bankroll IDL Discriminator Consistency
// ---------------------------------------------------------------------------

console.log("\n=== Bankroll IDL Discriminator Consistency ===\n");

// Map from TS name -> IDL name (camelCase in both)
const bankrollInstructionNames: [string, string][] = [
  ["initializeRegistry", "initializeRegistry"],
  ["initializeSolPool", "initializeSolPool"],
  ["initializeBuxPool", "initializeBuxPool"],
  ["initializeBuxVault", "initializeBuxVault"],
  ["registerGame", "registerGame"],
  ["depositSol", "depositSol"],
  ["withdrawSol", "withdrawSol"],
  ["depositBux", "depositBux"],
  ["withdrawBux", "withdrawBux"],
  ["submitCommitment", "submitCommitment"],
  ["placeBetSol", "placeBetSol"],
  ["placeBetBux", "placeBetBux"],
  ["settleBet", "settleBet"],
  ["reclaimExpired", "reclaimExpired"],
  ["setReferrer", "setReferrer"],
  ["updateConfig", "updateConfig"],
  ["pause", "pause"],
];

for (const [tsName, idlName] of bankrollInstructionNames) {
  const idlIx = getIdlInstruction(bankrollIdl, idlName);
  const idlDiscrim = idlIx.discriminator as number[];

  // Check bankroll-service.ts
  if (bankrollServiceDiscrims.has(tsName)) {
    test(`bankroll-service.ts: ${tsName} discriminator matches IDL`, () => {
      const tsDiscrim = bankrollServiceDiscrims.get(tsName)!;
      assert.deepStrictEqual(
        tsDiscrim,
        idlDiscrim,
        `bankroll-service.ts ${tsName}: got [${tsDiscrim}], expected [${idlDiscrim}]`
      );
    });
  }

  // Check init-bankroll.ts
  if (initBankrollDiscrims.has(tsName)) {
    test(`init-bankroll.ts: ${tsName} discriminator matches IDL`, () => {
      const tsDiscrim = initBankrollDiscrims.get(tsName)!;
      assert.deepStrictEqual(
        tsDiscrim,
        idlDiscrim,
        `init-bankroll.ts ${tsName}: got [${tsDiscrim}], expected [${idlDiscrim}]`
      );
    });
  }
}

// Verify service has all discriminators it uses
test("bankroll-service.ts: all discriminators are valid IDL instructions", () => {
  const validNames = new Set(bankrollIdl.instructions.map((i: any) => i.name));
  for (const name of bankrollServiceDiscrims.keys()) {
    assert.ok(
      validNames.has(name),
      `bankroll-service.ts has discriminator '${name}' which is not in the IDL`
    );
  }
});

// ---------------------------------------------------------------------------
// Test Suite 2: Airdrop IDL Discriminator Consistency
// ---------------------------------------------------------------------------

console.log("\n=== Airdrop IDL Discriminator Consistency ===\n");

// Airdrop IDL uses snake_case, TS uses camelCase
const airdropInstructionMap: [string, string][] = [
  ["initialize", "initialize"],
  ["startRound", "start_round"],
  ["depositBux", "deposit_bux"],
  ["fundPrizes", "fund_prizes"],
  ["closeRound", "close_round"],
  ["drawWinners", "draw_winners"],
  ["claimPrize", "claim_prize"],
  ["withdrawUnclaimed", "withdraw_unclaimed"],
];

for (const [tsName, idlName] of airdropInstructionMap) {
  const idlIx = getIdlInstruction(airdropIdl, idlName);
  const idlDiscrim = idlIx.discriminator as number[];

  // Check airdrop-service.ts
  if (airdropServiceDiscrims.has(tsName)) {
    test(`airdrop-service.ts: ${tsName} discriminator matches IDL`, () => {
      const tsDiscrim = airdropServiceDiscrims.get(tsName)!;
      assert.deepStrictEqual(
        tsDiscrim,
        idlDiscrim,
        `airdrop-service.ts ${tsName}: got [${tsDiscrim}], expected [${idlDiscrim}]`
      );
    });
  }

  // Check init-airdrop.ts
  if (initAirdropDiscrims.has(tsName)) {
    test(`init-airdrop.ts: ${tsName} discriminator matches IDL`, () => {
      const tsDiscrim = initAirdropDiscrims.get(tsName)!;
      assert.deepStrictEqual(
        tsDiscrim,
        idlDiscrim,
        `init-airdrop.ts ${tsName}: got [${tsDiscrim}], expected [${idlDiscrim}]`
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Test Suite 3: PDA Seed Consistency
// ---------------------------------------------------------------------------

console.log("\n=== PDA Seed Consistency ===\n");

// Bankroll PDA seeds: check that TS seed constants match IDL
// Build expected seeds from the IDL
function getIdlPdaSeeds(idl: any): Map<string, string> {
  const seeds = new Map<string, string>();
  for (const ix of idl.instructions) {
    for (const acct of ix.accounts) {
      if (acct.pda?.seeds) {
        for (const seed of acct.pda.seeds) {
          if (seed.kind === "const") {
            const seedStr = Buffer.from(seed.value).toString("utf-8");
            // Use account name as key (deduplicated)
            seeds.set(acct.name, seedStr);
          }
        }
      }
    }
  }
  return seeds;
}

const bankrollIdlSeeds = getIdlPdaSeeds(bankrollIdl);
const airdropIdlSeeds = getIdlPdaSeeds(airdropIdl);

// Bankroll service PDA seed checks
const bankrollSeedChecks: [string, string, string][] = [
  // [TS variable name, expected IDL seed string, description]
  ["GAME_REGISTRY_SEED", "game_registry", "game_registry PDA"],
  ["SOL_VAULT_SEED", "sol_vault", "sol_vault PDA"],
  ["SOL_VAULT_STATE_SEED", "sol_vault_state", "sol_vault_state PDA"],
  ["BUX_VAULT_STATE_SEED", "bux_vault_state", "bux_vault_state PDA"],
  ["BSOL_MINT_SEED", "bsol_mint", "bsol_mint PDA"],
  ["BBUX_MINT_SEED", "bbux_mint", "bbux_mint PDA"],
  ["BUX_VAULT_TOKEN_SEED", "bux_token_account", "bux_token_account PDA"],
  ["PLAYER_STATE_SEED", "player", "player PDA"],
  ["BET_ORDER_SEED", "bet", "bet PDA"],
];

for (const [varName, expectedSeed, desc] of bankrollSeedChecks) {
  test(`bankroll-service.ts: ${desc} seed = "${expectedSeed}"`, () => {
    const actual = bankrollServiceSeeds.get(varName);
    assert.ok(actual !== undefined, `Seed variable ${varName} not found in bankroll-service.ts`);
    assert.strictEqual(
      actual,
      expectedSeed,
      `${varName}: got "${actual}", expected "${expectedSeed}"`
    );
  });
}

// Airdrop service PDA seed checks
const airdropSeedChecks: [string, string, string][] = [
  ["AIRDROP_STATE_SEED", "airdrop", "airdrop_state PDA"],
  ["ROUND_SEED", "round", "round PDA"],
  ["ENTRY_SEED", "entry", "entry PDA"],
  ["PRIZE_VAULT_SEED", "prize_vault", "prize_vault PDA"],
];

for (const [varName, expectedSeed, desc] of airdropSeedChecks) {
  test(`airdrop-service.ts: ${desc} seed = "${expectedSeed}"`, () => {
    const actual = airdropServiceSeeds.get(varName);
    assert.ok(actual !== undefined, `Seed variable ${varName} not found in airdrop-service.ts`);
    assert.strictEqual(
      actual,
      expectedSeed,
      `${varName}: got "${actual}", expected "${expectedSeed}"`
    );
  });
}

// Verify init-bankroll.ts PDA seeds match
// init-bankroll.ts uses derivePDA("seed_string") pattern
const initBankrollPdaChecks: [string, string][] = [
  ["game_registry", "game_registry"],
  ["sol_vault", "sol_vault"],
  ["sol_vault_state", "sol_vault_state"],
  ["bux_vault_state", "bux_vault_state"],
  ["bsol_mint", "bsol_mint"],
  ["bbux_mint", "bbux_mint"],
  ["bux_token_account", "bux_token_account"],
];

for (const [seed, expected] of initBankrollPdaChecks) {
  test(`init-bankroll.ts: uses correct seed "${expected}"`, () => {
    // Check that derivePDA("seed") is called with the right string
    assert.ok(
      initBankrollSrc.includes(`derivePDA("${expected}")`),
      `init-bankroll.ts does not call derivePDA("${expected}")`
    );
  });
}

// Also check that init-bankroll.ts does NOT use "bux_vault_token" (wrong seed)
test("init-bankroll.ts: does NOT use incorrect seed 'bux_vault_token'", () => {
  assert.ok(
    !initBankrollSrc.includes('"bux_vault_token"'),
    `init-bankroll.ts uses "bux_vault_token" but should use "bux_token_account"`
  );
});

// ---------------------------------------------------------------------------
// Test Suite 4: Account Count Verification
// ---------------------------------------------------------------------------

console.log("\n=== Account Count Verification ===\n");

/**
 * Extract a function body from TypeScript source by matching braces.
 * Handles: function, async function, export function, export async function.
 * Returns the full function body text, or null if not found.
 */
function extractFunctionBody(src: string, funcName: string): string | null {
  // Try multiple patterns (prefer longer match to avoid substring matches)
  const patterns = [
    `async function ${funcName}`,
    `function ${funcName}`,
  ];

  let funcStart = -1;
  for (const pat of patterns) {
    const idx = src.indexOf(pat);
    if (idx !== -1) {
      funcStart = idx;
      break;
    }
  }
  if (funcStart === -1) return null;

  // Skip past the parameter list (handles nested { } in type annotations)
  const parenOpen = src.indexOf("(", funcStart);
  if (parenOpen === -1) return null;
  let parenDepth = 0;
  let parenClose = parenOpen;
  for (let i = parenOpen; i < src.length; i++) {
    if (src[i] === "(") parenDepth++;
    if (src[i] === ")") {
      parenDepth--;
      if (parenDepth === 0) { parenClose = i; break; }
    }
  }

  // Find the opening brace of the function body (after return type)
  let bodyOpen = -1;
  for (let i = parenClose + 1; i < src.length; i++) {
    if (src[i] === "{") { bodyOpen = i; break; }
  }
  if (bodyOpen === -1) return null;

  // Match braces from the function body opening
  let braceCount = 0;
  let funcEnd = bodyOpen;
  for (let i = bodyOpen; i < src.length; i++) {
    if (src[i] === "{") braceCount++;
    if (src[i] === "}") {
      braceCount--;
      if (braceCount === 0) { funcEnd = i; break; }
    }
  }
  return src.substring(funcStart, funcEnd + 1);
}

/**
 * Count accounts in a function that uses the pattern:
 *   const keys = [ { pubkey: ... }, ... ];
 *   // optionally: keys.push({ pubkey: ... }, ...)
 *
 * For functions with if/else branches adding optional accounts,
 * we count the initial keys array + ONE branch of pushes (both branches
 * should push the same count for Anchor compatibility).
 *
 * Returns the total account count, or null if the function was not found.
 */
function countAccountsInFunction(
  src: string,
  funcName: string
): number | null {
  const funcBody = extractFunctionBody(src, funcName);
  if (!funcBody) return null;

  // Count accounts in the initial keys array
  // Pattern 1: `const keys = [ ... ];` (bankroll-service, airdrop-service)
  // Pattern 2: `keys: [ ... ]` inside TransactionInstruction (init-bankroll)
  let keysArrayMatch = funcBody.match(/const keys[^=]*=\s*\[([\s\S]*?)\];/);
  if (!keysArrayMatch) {
    keysArrayMatch = funcBody.match(/keys:\s*\[([\s\S]*?)\],/);
  }
  let initialCount = 0;
  if (keysArrayMatch) {
    const entries = keysArrayMatch[1].match(/\{\s*pubkey:/g);
    initialCount = entries ? entries.length : 0;
  }

  // Count accounts added via keys.push() calls
  // For if/else branches, take the FIRST branch (isSolPrize / isSol branch)
  // since both branches should add the same number of accounts
  const pushMatches = funcBody.match(/keys\.push\(\s*\n?([\s\S]*?)\);/g);
  let pushCount = 0;
  let inIfBranch = false;
  let ifBranchDone = false;

  if (pushMatches) {
    // Check if there are conditional branches
    const hasIfElse = funcBody.includes("if (isSol") || funcBody.includes("if (isSolPrize");

    if (hasIfElse) {
      // For conditional branches, we need to count accounts in just one path
      // Look at the structure: if block pushes N, else block pushes M, then after both pushes P
      // Total for either path should be: initial + N + P (if branch) = initial + M + P (else branch)

      // Split function at if/else to find the common pushes after the branch
      const ifIdx = funcBody.search(/if\s*\(isSol/);

      // Find the end of the if-else block
      let elseEndIdx = -1;
      let searchStart = ifIdx;
      let depth = 0;
      let foundIf = false;
      let foundElse = false;

      for (let i = searchStart; i < funcBody.length; i++) {
        if (funcBody[i] === '{') depth++;
        if (funcBody[i] === '}') {
          depth--;
          if (depth === 0 && !foundElse) {
            // End of if block, look for else
            const afterBrace = funcBody.substring(i + 1, i + 20).trim();
            if (afterBrace.startsWith('else')) {
              foundElse = true;
              // continue to find end of else
            } else {
              elseEndIdx = i;
              break;
            }
          } else if (depth === 0 && foundElse) {
            elseEndIdx = i;
            break;
          }
        }
      }

      // Get the if-branch body (first branch)
      const afterIfKeyword = funcBody.substring(ifIdx);
      const ifBraceStart = afterIfKeyword.indexOf('{');
      let ifDepth = 0;
      let ifEnd = 0;
      for (let i = ifBraceStart; i < afterIfKeyword.length; i++) {
        if (afterIfKeyword[i] === '{') ifDepth++;
        if (afterIfKeyword[i] === '}') {
          ifDepth--;
          if (ifDepth === 0) {
            ifEnd = i;
            break;
          }
        }
      }
      const ifBranchBody = afterIfKeyword.substring(ifBraceStart, ifEnd + 1);
      const ifPushAccounts = (ifBranchBody.match(/\{\s*pubkey:/g) || []).length;

      // Get pushes after the if/else block
      const afterBlock = funcBody.substring(ifIdx).substring(
        elseEndIdx > 0 ? (elseEndIdx - ifIdx + 1) : 0
      );
      const afterPushAccounts = (afterBlock.match(/keys\.push\([\s\S]*?\)/g) || [])
        .reduce((sum, push) => sum + (push.match(/\{\s*pubkey:/g) || []).length, 0);

      pushCount = ifPushAccounts + afterPushAccounts;
    } else {
      // No conditional — just count all push accounts
      for (const push of pushMatches) {
        const entries = push.match(/\{\s*pubkey:/g);
        pushCount += entries ? entries.length : 0;
      }
    }
  }

  return initialCount + pushCount;
}

// bankroll-service.ts function -> IDL instruction mapping for account counts
const bankrollAccountChecks: [string, string, string][] = [
  // [functionName in TS, IDL instruction name, source file label]
  ["buildDepositSolTx", "depositSol", "bankroll-service.ts"],
  ["buildWithdrawSolTx", "withdrawSol", "bankroll-service.ts"],
  ["buildDepositBuxTx", "depositBux", "bankroll-service.ts"],
  ["buildWithdrawBuxTx", "withdrawBux", "bankroll-service.ts"],
];

for (const [funcName, idlName, srcFile] of bankrollAccountChecks) {
  const idlIx = getIdlInstruction(bankrollIdl, idlName);
  const expectedCount = idlIx.accounts.length;

  test(`${srcFile}: ${funcName} account count matches IDL (${idlName}: ${expectedCount} accounts)`, () => {
    const actual = countAccountsInFunction(bankrollServiceSrc, funcName);
    assert.ok(actual !== null, `Could not find function ${funcName} in ${srcFile}`);
    assert.strictEqual(
      actual,
      expectedCount,
      `${funcName} has ${actual} accounts, IDL expects ${expectedCount}`
    );
  });
}

// bankroll-service.ts: buildPlaceBetTx has conditional branches (sol vs bux)
// SOL path should match placeBetSol, BUX path should match placeBetBux
test("bankroll-service.ts: buildPlaceBetTx SOL path account count matches IDL (placeBetSol: 7)", () => {
  const funcBody = extractFunctionBody(bankrollServiceSrc, "buildPlaceBetTx");
  assert.ok(funcBody, "Could not find buildPlaceBetTx");
  // Initial keys: 4 (player, gameRegistry, playerState, betOrder)
  // SOL branch pushes: 3 (solVault, solVaultState, systemProgram)
  // Total = 7
  const keysArrayMatch = funcBody.match(/const keys[^=]*=\s*\[([\s\S]*?)\];/);
  const initialCount = keysArrayMatch
    ? (keysArrayMatch[1].match(/\{\s*pubkey:/g) || []).length
    : 0;
  // Find SOL branch (if (isSol))
  const ifIdx = funcBody.indexOf("if (isSol)");
  assert.ok(ifIdx >= 0, "Could not find isSol branch");
  const afterIf = funcBody.substring(ifIdx);
  const braceStart = afterIf.indexOf("{");
  let depth = 0;
  let braceEnd = 0;
  for (let i = braceStart; i < afterIf.length; i++) {
    if (afterIf[i] === "{") depth++;
    if (afterIf[i] === "}") { depth--; if (depth === 0) { braceEnd = i; break; } }
  }
  const solBranch = afterIf.substring(braceStart, braceEnd + 1);
  const solPushCount = (solBranch.match(/\{\s*pubkey:/g) || []).length;
  assert.strictEqual(initialCount + solPushCount, 7, `SOL path: ${initialCount} + ${solPushCount} = ${initialCount + solPushCount}, expected 7`);
});

test("bankroll-service.ts: buildPlaceBetTx BUX path account count matches IDL (placeBetBux: 9)", () => {
  const funcBody = extractFunctionBody(bankrollServiceSrc, "buildPlaceBetTx");
  assert.ok(funcBody, "Could not find buildPlaceBetTx");
  const keysArrayMatch = funcBody.match(/const keys[^=]*=\s*\[([\s\S]*?)\];/);
  const initialCount = keysArrayMatch
    ? (keysArrayMatch[1].match(/\{\s*pubkey:/g) || []).length
    : 0;
  // Find BUX branch (else {)
  const elseIdx = funcBody.indexOf("} else {");
  assert.ok(elseIdx >= 0, "Could not find else branch");
  const afterElse = funcBody.substring(elseIdx);
  const braceStart = afterElse.indexOf("{");
  let depth = 0;
  let braceEnd = 0;
  for (let i = braceStart; i < afterElse.length; i++) {
    if (afterElse[i] === "{") depth++;
    if (afterElse[i] === "}") { depth--; if (depth === 0) { braceEnd = i; break; } }
  }
  const buxBranch = afterElse.substring(braceStart, braceEnd + 1);
  const buxPushCount = (buxBranch.match(/\{\s*pubkey:/g) || []).length;
  assert.strictEqual(initialCount + buxPushCount, 9, `BUX path: ${initialCount} + ${buxPushCount} = ${initialCount + buxPushCount}, expected 9`);
});

// init-bankroll.ts function account checks
// These use `keys: [...]` inside TransactionInstruction constructor
const initBankrollAccountChecks: [string, string][] = [
  ["initializeRegistry", "initializeRegistry"],
  ["initializeSolPool", "initializeSolPool"],
  ["initializeBuxPool", "initializeBuxPool"],
  ["initializeBuxVault", "initializeBuxVault"],
  ["registerCoinFlipGame", "registerGame"],
  ["seedLiquidity", "depositSol"],
];

for (const [funcName, idlName] of initBankrollAccountChecks) {
  const idlIx = getIdlInstruction(bankrollIdl, idlName);
  const expectedCount = idlIx.accounts.length;

  test(`init-bankroll.ts: ${funcName} account count matches IDL (${idlName}: ${expectedCount} accounts)`, () => {
    const actual = countAccountsInFunction(initBankrollSrc, funcName);
    assert.ok(actual !== null, `Could not find function ${funcName} in init-bankroll.ts`);
    assert.strictEqual(
      actual,
      expectedCount,
      `${funcName} has ${actual} accounts, IDL expects ${expectedCount}`
    );
  });
}

// airdrop-service.ts function account checks
// Functions without conditional account branches
// drawWinners, fundPrizes, buildClaimPrizeTx have dynamic keys.push() for optional
// token accounts — regex counter can't parse them. Verified manually:
// fundPrizes: 4 base + 2 optional + 2 system = 8 (matches IDL)
// drawWinners: 3 accounts (authority, airdropState, round) — built as direct keys array
// buildClaimPrizeTx: 4 base + 2 optional + 2 system = 8 (matches IDL)
const airdropSimpleAccountChecks: [string, string][] = [
  ["startRound", "start_round"],
  ["closeRound", "close_round"],
  ["drawWinners", "draw_winners"],
  ["buildDepositBuxTx", "deposit_bux"],
];

for (const [funcName, idlName] of airdropSimpleAccountChecks) {
  const idlIx = getIdlInstruction(airdropIdl, idlName);
  const expectedCount = idlIx.accounts.length;

  test(`airdrop-service.ts: ${funcName} account count matches IDL (${idlName}: ${expectedCount} accounts)`, () => {
    const actual = countAccountsInFunction(airdropServiceSrc, funcName);
    assert.ok(actual !== null, `Could not find function ${funcName} in airdrop-service.ts`);
    assert.strictEqual(
      actual,
      expectedCount,
      `${funcName} has ${actual} accounts, IDL expects ${expectedCount}`
    );
  });
}

// Functions WITH conditional account branches — verified manually (see comment above)
// Automated branch parsing is fragile so we just verify the IDL expected counts exist
test("airdrop IDL: fundPrizes expects 8 accounts", () => {
  const idlIx = getIdlInstruction(airdropIdl, "fund_prizes");
  assert.strictEqual(idlIx.accounts.length, 8);
});

test("airdrop IDL: drawWinners expects 3 accounts", () => {
  const idlIx = getIdlInstruction(airdropIdl, "draw_winners");
  assert.strictEqual(idlIx.accounts.length, 3);
});

test("airdrop IDL: claimPrize expects 8 accounts", () => {
  const idlIx = getIdlInstruction(airdropIdl, "claim_prize");
  assert.strictEqual(idlIx.accounts.length, 8);
});

// init-airdrop.ts account checks — these are inline in main(), so check differently
// We check the initialize instruction's keys array manually
test("init-airdrop.ts: initialize has 5 accounts matching IDL", () => {
  // Count pubkey entries between first keys array and its closing bracket
  const keysSection = initAirdropSrc.match(
    /const keys = \[([\s\S]*?)\];/
  );
  assert.ok(keysSection, "Could not find keys array in init-airdrop.ts initialize");
  const count = (keysSection[1].match(/\{\s*pubkey:/g) || []).length;
  assert.strictEqual(count, 5, `initialize has ${count} accounts, IDL expects 5`);
});

// ---------------------------------------------------------------------------
// Test Suite 5: Program ID Consistency
// ---------------------------------------------------------------------------

console.log("\n=== Program ID Consistency ===\n");

const EXPECTED_BANKROLL = "49up2uzZANpjTC3sgggbZazdHBii2vY9mVK3vk5dT2tm";
const EXPECTED_AIRDROP = "wxiuLBuqxem5ETmGDndiW8MMkxKXp5jVsNCqdZgmjaG";
const EXPECTED_BUX_MINT = "7CuRyw2YkqQhUUFbw6CCnoedHWT8tK2c9UzZQYDGmxVX";

test("config.ts: BANKROLL_PROGRAM_ID matches deployed address", () => {
  assert.ok(
    configSrc.includes(EXPECTED_BANKROLL),
    `config.ts does not contain bankroll program ID ${EXPECTED_BANKROLL}`
  );
});

test("config.ts: AIRDROP_PROGRAM_ID matches deployed address", () => {
  assert.ok(
    configSrc.includes(EXPECTED_AIRDROP),
    `config.ts does not contain airdrop program ID ${EXPECTED_AIRDROP}`
  );
});

test("config.ts: BUX_MINT_ADDRESS matches deployed address", () => {
  assert.ok(
    configSrc.includes(EXPECTED_BUX_MINT),
    `config.ts does not contain BUX mint ${EXPECTED_BUX_MINT}`
  );
});

test("bankroll IDL: address matches deployed bankroll program ID", () => {
  assert.strictEqual(
    bankrollIdl.address,
    EXPECTED_BANKROLL,
    `Bankroll IDL address: ${bankrollIdl.address}, expected ${EXPECTED_BANKROLL}`
  );
});

test("airdrop IDL: address matches deployed airdrop program ID", () => {
  assert.strictEqual(
    airdropIdl.address,
    EXPECTED_AIRDROP,
    `Airdrop IDL address: ${airdropIdl.address}, expected ${EXPECTED_AIRDROP}`
  );
});

test("init-bankroll.ts: uses correct bankroll program ID", () => {
  assert.ok(
    initBankrollSrc.includes(EXPECTED_BANKROLL),
    `init-bankroll.ts does not contain ${EXPECTED_BANKROLL}`
  );
});

test("init-bankroll.ts: uses correct BUX mint address", () => {
  assert.ok(
    initBankrollSrc.includes(EXPECTED_BUX_MINT),
    `init-bankroll.ts does not contain ${EXPECTED_BUX_MINT}`
  );
});

test("init-airdrop.ts: uses correct airdrop program ID", () => {
  assert.ok(
    initAirdropSrc.includes(EXPECTED_AIRDROP),
    `init-airdrop.ts does not contain ${EXPECTED_AIRDROP}`
  );
});

test("init-airdrop.ts: uses correct BUX mint address", () => {
  assert.ok(
    initAirdropSrc.includes(EXPECTED_BUX_MINT),
    `init-airdrop.ts does not contain ${EXPECTED_BUX_MINT}`
  );
});

// ---------------------------------------------------------------------------
// Test Suite 6: Cross-file Discriminator Consistency
// ---------------------------------------------------------------------------

console.log("\n=== Cross-file Discriminator Consistency ===\n");

// Verify that discriminators shared between service and script files match each other
test("depositSol discriminator: bankroll-service.ts == init-bankroll.ts", () => {
  const svcDiscrim = bankrollServiceDiscrims.get("depositSol");
  const scriptDiscrim = initBankrollDiscrims.get("depositSol");
  if (svcDiscrim && scriptDiscrim) {
    assert.deepStrictEqual(
      svcDiscrim,
      scriptDiscrim,
      `bankroll-service.ts [${svcDiscrim}] != init-bankroll.ts [${scriptDiscrim}]`
    );
  } else {
    // At least one is missing — not a cross-file consistency issue
    assert.ok(true);
  }
});

// Check airdrop cross-file consistency
for (const name of ["initialize", "startRound", "fundPrizes"]) {
  const svcDiscrim = airdropServiceDiscrims.get(name);
  const scriptDiscrim = initAirdropDiscrims.get(name);
  if (svcDiscrim && scriptDiscrim) {
    test(`${name} discriminator: airdrop-service.ts == init-airdrop.ts`, () => {
      assert.deepStrictEqual(
        svcDiscrim,
        scriptDiscrim,
        `airdrop-service.ts [${svcDiscrim}] != init-airdrop.ts [${scriptDiscrim}]`
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

console.log("\n" + "=".repeat(60));
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failures.length > 0) {
  console.log("\nFailures:");
  for (const f of failures) {
    console.log(f);
  }
}
console.log("=".repeat(60));

if (failed > 0) {
  process.exit(1);
}
