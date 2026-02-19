/**
 * RoguePaymentHook - Handle ROGUE native token transfer for shop checkout
 *
 * Transfers ROGUE (native gas token on Rogue Chain) from the user's smart wallet
 * to the shop treasury address using the Thirdweb SDK.
 * ROGUE is NOT an ERC-20 — it's the native token, so we use prepareTransaction
 * with a value transfer (like sending ETH on Ethereum).
 */

export const RoguePaymentHook = {
  mounted() {
    this.treasuryAddress = this.el.dataset.treasuryAddress;

    this.handleEvent("initiate_rogue_payment", async ({ amount_wei, order_id }) => {
      try {
        if (!this.treasuryAddress || this.treasuryAddress === "0x0000000000000000000000000000000000000000") {
          this.pushEvent("rogue_payment_error", { error: "Shop treasury address not configured. Please contact support." });
          return;
        }

        const wallet = window.smartAccount;
        if (!wallet) {
          this.pushEvent("rogue_payment_error", { error: "No wallet connected. Please refresh." });
          return;
        }

        const { prepareTransaction, sendTransaction, waitForReceipt, toWei } = await import("thirdweb");

        const tx = prepareTransaction({
          to: this.treasuryAddress,
          value: BigInt(amount_wei),
          chain: window.rogueChain,
          client: window.thirdwebClient
        });

        const result = await sendTransaction({ transaction: tx, account: wallet });
        console.log("[RoguePayment] TX submitted:", result.transactionHash);

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash: result.transactionHash
        });

        if (receipt.status === "success") {
          this.pushEvent("rogue_payment_complete", { tx_hash: result.transactionHash });
        } else {
          this.pushEvent("rogue_payment_error", { error: "ROGUE transfer failed on-chain" });
        }
      } catch (error) {
        console.error("[RoguePayment] Error:", error);
        let msg = error.message;
        if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "ROGUE payment cancelled";
        else if (msg?.includes("insufficient")) msg = "Insufficient ROGUE balance";
        this.pushEvent("rogue_payment_error", { error: msg });
      }
    });
  }
};
