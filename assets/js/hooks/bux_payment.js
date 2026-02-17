/**
 * BuxPaymentHook - Handle BUX token transfer for shop checkout
 *
 * Transfers BUX (ERC-20) from the user's smart wallet to the shop treasury address
 * using the Thirdweb SDK. Used as client-side fallback when the BUX Minter service
 * burn endpoint is unavailable.
 */

const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

export const BuxPaymentHook = {
  mounted() {
    this.treasuryAddress = this.el.dataset.treasuryAddress;

    this.handleEvent("initiate_bux_payment_client", async ({ amount, order_id }) => {
      try {
        const wallet = window.smartAccount;
        if (!wallet) {
          this.pushEvent("bux_payment_error", { error: "No wallet connected. Please refresh." });
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

        const transferTx = prepareContractCall({
          contract: buxContract,
          method: "function transfer(address to, uint256 amount) returns (bool)",
          params: [this.treasuryAddress, amountWei]
        });

        const result = await sendTransaction({ transaction: transferTx, account: wallet });
        console.log("[BuxPayment] TX submitted:", result.transactionHash);

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash: result.transactionHash
        });

        if (receipt.status === "success") {
          this.pushEvent("bux_payment_complete", { tx_hash: result.transactionHash });
        } else {
          this.pushEvent("bux_payment_error", { error: "BUX transfer failed on-chain" });
        }
      } catch (error) {
        console.error("[BuxPayment] Error:", error);
        let msg = error.message;
        if (msg?.includes("User rejected") || msg?.includes("user rejected")) msg = "BUX payment cancelled";
        else if (msg?.includes("insufficient")) msg = "Insufficient BUX balance";
        this.pushEvent("bux_payment_error", { error: msg });
      }
    });
  }
};
