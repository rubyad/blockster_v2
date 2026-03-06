/**
 * AirdropApproveHook - Handle BUX approve for airdrop vault deposit
 *
 * Calls BUX.approve(vault, amount) from the user's smart wallet so that
 * the vault can transferFrom the user's BUX during depositFor().
 */

const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";
const AIRDROP_VAULT_ADDRESS = "0x27049F96f8a00203fEC5f871e6DAa6Ee4c244F6c";

export const AirdropApproveHook = {
  mounted() {
    this.handleEvent("airdrop_approve_bux", async ({ amount, round_id }) => {
      try {
        const wallet = window.smartAccount;
        if (!wallet) {
          this.pushEvent("airdrop_approve_error", { error: "No wallet connected. Please refresh." });
          return;
        }

        const { prepareContractCall, sendTransaction, waitForReceipt } = await import("thirdweb");
        const { getContract } = await import("thirdweb/contract");

        const buxContract = getContract({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          address: BUX_TOKEN_ADDRESS
        });

        // BUX has 18 decimals
        const amountWei = BigInt(amount) * BigInt(10 ** 18);

        console.log(`[AirdropApprove] Approving vault ${AIRDROP_VAULT_ADDRESS} to spend ${amount} BUX`);

        const approveTx = prepareContractCall({
          contract: buxContract,
          method: "function approve(address spender, uint256 amount) returns (bool)",
          params: [AIRDROP_VAULT_ADDRESS, amountWei]
        });

        const result = await sendTransaction({ transaction: approveTx, account: wallet });
        console.log("[AirdropApprove] TX submitted:", result.transactionHash);

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash: result.transactionHash
        });

        if (receipt.status === "success") {
          console.log("[AirdropApprove] Approve confirmed:", result.transactionHash);
          this.pushEvent("airdrop_approve_complete", {
            tx_hash: result.transactionHash,
            amount: amount,
            round_id: round_id
          });
        } else {
          this.pushEvent("airdrop_approve_error", { error: "BUX approve transaction failed on-chain" });
        }
      } catch (error) {
        console.error("[AirdropApprove] Error:", error);
        let msg = error.message;
        if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "Approval cancelled";
        else if (msg?.includes("insufficient")) msg = "Insufficient BUX balance";
        this.pushEvent("airdrop_approve_error", { error: msg });
      }
    });
  }
};
