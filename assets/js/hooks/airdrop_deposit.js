/**
 * AirdropDepositHook - Client-side approve + deposit for AirdropVault V2
 *
 * Matches the BuxBooster pattern: user's smart wallet does approve + deposit
 * entirely client-side. No minter backend involvement for deposits.
 *
 * Flow:
 * 1. LiveView pushes "airdrop_deposit" event with {amount, round_id, external_wallet}
 * 2. Hook checks if BUX approval is needed (localStorage cache + on-chain check)
 * 3. If needed: BUX.approve(vault, MAX_UINT256), wait for receipt, cache
 * 4. vault.deposit(externalWallet, amountWei), wait for receipt
 * 5. Parse BuxDeposited event for startPosition/endPosition
 * 6. Push "airdrop_deposit_complete" or "airdrop_deposit_error" back to LiveView
 */

const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const AIRDROP_VAULT_ADDRESS = "0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c";

export const AirdropDepositHook = {
  mounted() {
    this.handleEvent("airdrop_deposit", async ({ amount, round_id, external_wallet }) => {
      try {
        const wallet = window.smartAccount;
        if (!wallet) {
          this.pushEvent("airdrop_deposit_error", { error: "No wallet connected. Please refresh." });
          return;
        }

        const amountWei = BigInt(amount) * BigInt(10 ** 18);

        // Step 1: Check if approval is needed
        const needsApproval = await this.needsApproval(wallet, amountWei);

        if (needsApproval) {
          console.log("[AirdropDeposit] Approval needed, executing approve...");
          const approveResult = await this.executeApprove(wallet);
          if (!approveResult.success) {
            this.pushEvent("airdrop_deposit_error", { error: approveResult.error });
            return;
          }
          console.log("[AirdropDeposit] Approve confirmed:", approveResult.txHash);
        }

        // Step 2: Execute deposit
        console.log(`[AirdropDeposit] Depositing ${amount} BUX to vault for external wallet ${external_wallet}`);
        const depositResult = await this.executeDeposit(wallet, external_wallet, amountWei);

        if (depositResult.success) {
          console.log("[AirdropDeposit] Deposit confirmed:", depositResult.txHash);
          this.pushEvent("airdrop_deposit_complete", {
            tx_hash: depositResult.txHash,
            amount: amount,
            round_id: round_id,
            start_position: depositResult.startPosition,
            end_position: depositResult.endPosition
          });
        } else {
          this.pushEvent("airdrop_deposit_error", { error: depositResult.error });
        }

      } catch (error) {
        console.error("[AirdropDeposit] Error:", error);
        let msg = error.message;
        if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "Transaction cancelled";
        else if (msg?.includes("insufficient")) msg = "Insufficient BUX balance";
        this.pushEvent("airdrop_deposit_error", { error: msg });
      }
    });
  },

  /**
   * Check if BUX approval is needed for the vault.
   * Uses localStorage cache + on-chain verification (same pattern as BuxBooster).
   */
  async needsApproval(wallet, amount) {
    const cacheKey = `approval_${wallet.address}_${BUX_TOKEN_ADDRESS}_${AIRDROP_VAULT_ADDRESS}`;
    const cachedApproval = localStorage.getItem(cacheKey);

    if (cachedApproval === 'true') {
      return false;
    }

    try {
      const { readContract } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const buxContract = getContract({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        address: BUX_TOKEN_ADDRESS
      });

      const currentAllowance = await readContract({
        contract: buxContract,
        method: "function allowance(address owner, address spender) view returns (uint256)",
        params: [wallet.address, AIRDROP_VAULT_ADDRESS]
      });

      const allowanceBigInt = BigInt(currentAllowance);
      const INFINITE_THRESHOLD = BigInt('0x8000000000000000000000000000000000000000000000000000000000000000');

      if (allowanceBigInt >= INFINITE_THRESHOLD) {
        localStorage.setItem(cacheKey, 'true');
        return false;
      }

      if (allowanceBigInt >= amount) {
        return false;
      }

      return true;

    } catch (error) {
      console.error("[AirdropDeposit] Error checking allowance:", error);
      return true;
    }
  },

  /**
   * Execute BUX.approve(vault, MAX_UINT256) with infinite approval.
   * Waits for receipt, then caches the approval in localStorage.
   */
  async executeApprove(wallet) {
    try {
      const { prepareContractCall, sendTransaction, waitForReceipt } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const buxContract = getContract({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        address: BUX_TOKEN_ADDRESS
      });

      const INFINITE_APPROVAL = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');
      const approveTx = prepareContractCall({
        contract: buxContract,
        method: "function approve(address spender, uint256 amount) returns (bool)",
        params: [AIRDROP_VAULT_ADDRESS, INFINITE_APPROVAL]
      });

      const result = await sendTransaction({ transaction: approveTx, account: wallet });

      await waitForReceipt({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        transactionHash: result.transactionHash
      });

      const cacheKey = `approval_${wallet.address}_${BUX_TOKEN_ADDRESS}_${AIRDROP_VAULT_ADDRESS}`;
      localStorage.setItem(cacheKey, 'true');

      return { success: true, txHash: result.transactionHash };

    } catch (error) {
      console.error("[AirdropDeposit] Approve error:", error);
      let msg = error.message;
      if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "Approval cancelled";
      return { success: false, error: msg };
    }
  },

  /**
   * Execute vault.deposit(externalWallet, amount) from the user's smart wallet.
   * Waits for receipt and parses BuxDeposited event for position data.
   */
  async executeDeposit(wallet, externalWallet, amountWei) {
    try {
      const { prepareContractCall, sendTransaction, waitForReceipt } = await import("thirdweb");
      const { getContract } = await import("thirdweb/contract");

      const vaultContract = getContract({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        address: AIRDROP_VAULT_ADDRESS
      });

      const depositTx = prepareContractCall({
        contract: vaultContract,
        method: "function deposit(address externalWallet, uint256 amount) external",
        params: [externalWallet, amountWei]
      });

      const result = await sendTransaction({ transaction: depositTx, account: wallet });

      const receipt = await waitForReceipt({
        client: window.thirdwebClient,
        chain: window.rogueChain,
        transactionHash: result.transactionHash
      });

      if (receipt.status !== "success") {
        return { success: false, error: "Deposit transaction failed on-chain" };
      }

      // Parse BuxDeposited event for position data
      // Event: BuxDeposited(uint256 roundId, address indexed blocksterWallet, address indexed externalWallet, uint256 amount, uint256 startPosition, uint256 endPosition)
      let startPosition = null;
      let endPosition = null;

      for (const log of receipt.logs) {
        try {
          // BuxDeposited event topic
          // keccak256("BuxDeposited(uint256,address,address,uint256,uint256,uint256)")
          const BUX_DEPOSITED_TOPIC = "0x9e6ca3d02b55cac94a5901cced1eb608e60898e08e3f07dd02f3d4540c084de4";
          if (log.topics && log.topics[0] === BUX_DEPOSITED_TOPIC) {
            // Non-indexed params are in data: roundId, amount, startPosition, endPosition
            // Each is 32 bytes (64 hex chars)
            const data = log.data;
            if (data && data.length >= 258) { // 0x + 4*64 = 258
              // data layout: roundId (32) + amount (32) + startPosition (32) + endPosition (32)
              startPosition = parseInt(data.slice(130, 194), 16).toString();
              endPosition = parseInt(data.slice(194, 258), 16).toString();
            }
            break;
          }
        } catch (e) {
          // Not our event, skip
        }
      }

      return {
        success: true,
        txHash: result.transactionHash,
        startPosition: startPosition,
        endPosition: endPosition
      };

    } catch (error) {
      console.error("[AirdropDeposit] Deposit error:", error);
      let msg = error.message;
      if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "Transaction cancelled";
      else if (msg?.includes("insufficient")) msg = "Insufficient BUX balance";
      else if (msg?.includes("Round not open")) msg = "Airdrop round is not open";
      return { success: false, error: msg };
    }
  }
};
