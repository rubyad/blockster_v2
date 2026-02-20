import { getContract, prepareContractCall, sendTransaction, readContract, waitForReceipt } from "thirdweb";

const BUX_BANKROLL_ADDRESS = "0xED7B00Ab2aDE39AC06d4518d16B465C514ba8630";
const BUX_TOKEN_ADDRESS = "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8";

export const BankrollOnchain = {
  mounted() {
    // Listen for deposit command from LiveView
    this.handleEvent("deposit_bux", async ({ amount }) => {
      await this.deposit(amount);
    });

    // Listen for withdraw command from LiveView
    this.handleEvent("withdraw_bux", async ({ lp_amount }) => {
      await this.withdraw(lp_amount);
    });
  },

  async deposit(amount) {
    try {
      const wallet = window.smartAccount;
      if (!wallet) {
        this.pushEvent("deposit_failed", { error: "No wallet connected. Please refresh." });
        return;
      }

      const amountWei = BigInt(amount) * BigInt(10 ** 18);
      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      // 1. Check BUX approval for BUXBankroll
      const buxContract = getContract({ client, chain, address: BUX_TOKEN_ADDRESS });

      const allowance = await readContract({
        contract: buxContract,
        method: "function allowance(address owner, address spender) view returns (uint256)",
        params: [wallet.address, BUX_BANKROLL_ADDRESS],
      });

      if (BigInt(allowance) < amountWei) {
        console.log("[BankrollOnchain] Approving BUX for BUXBankroll...");
        const INFINITE = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

        const approveTx = prepareContractCall({
          contract: buxContract,
          method: "function approve(address spender, uint256 amount) returns (bool)",
          params: [BUX_BANKROLL_ADDRESS, INFINITE],
        });

        const approveResult = await sendTransaction({ transaction: approveTx, account: wallet });
        await waitForReceipt({ client, chain, transactionHash: approveResult.transactionHash });
        console.log("[BankrollOnchain] BUX approved:", approveResult.transactionHash);
      }

      // 2. Call depositBUX on BUXBankroll
      const bankrollContract = getContract({ client, chain, address: BUX_BANKROLL_ADDRESS });

      const depositTx = prepareContractCall({
        contract: bankrollContract,
        method: "function depositBUX(uint256 amount)",
        params: [amountWei],
      });

      console.log("[BankrollOnchain] Depositing BUX...");
      const receipt = await sendTransaction({ transaction: depositTx, account: wallet });
      const finalReceipt = await waitForReceipt({ client, chain, transactionHash: receipt.transactionHash });
      console.log("[BankrollOnchain] Deposit confirmed:", finalReceipt.transactionHash);

      this.pushEvent("deposit_confirmed", { tx_hash: finalReceipt.transactionHash });

    } catch (error) {
      console.error("[BankrollOnchain] Deposit failed:", error);
      const msg = this.parseError(error);
      this.pushEvent("deposit_failed", { error: msg });
    }
  },

  async withdraw(lpAmount) {
    try {
      const wallet = window.smartAccount;
      if (!wallet) {
        this.pushEvent("withdraw_failed", { error: "No wallet connected. Please refresh." });
        return;
      }

      const lpAmountWei = BigInt(lpAmount) * BigInt(10 ** 18);
      const client = window.thirdwebClient;
      const chain = window.rogueChain;

      const bankrollContract = getContract({ client, chain, address: BUX_BANKROLL_ADDRESS });

      const withdrawTx = prepareContractCall({
        contract: bankrollContract,
        method: "function withdrawBUX(uint256 lpAmount)",
        params: [lpAmountWei],
      });

      console.log("[BankrollOnchain] Withdrawing LP-BUX...");
      const receipt = await sendTransaction({ transaction: withdrawTx, account: wallet });
      const finalReceipt = await waitForReceipt({ client, chain, transactionHash: receipt.transactionHash });
      console.log("[BankrollOnchain] Withdrawal confirmed:", finalReceipt.transactionHash);

      this.pushEvent("withdraw_confirmed", { tx_hash: finalReceipt.transactionHash });

    } catch (error) {
      console.error("[BankrollOnchain] Withdrawal failed:", error);
      const msg = this.parseError(error);
      this.pushEvent("withdraw_failed", { error: msg });
    }
  },

  parseError(error) {
    const msg = error?.message || error?.toString() || "";
    if (msg.includes("insufficient funds")) return "Insufficient funds for transaction";
    if (msg.includes("user rejected") || msg.includes("User rejected")) return "Transaction cancelled";
    if (msg.includes("InsufficientBalance")) return "Insufficient LP-BUX balance";
    if (msg.includes("InsufficientLiquidity")) return "Insufficient pool liquidity for withdrawal";
    if (msg.includes("ZeroAmount")) return "Amount must be greater than zero";
    return msg.slice(0, 200) || "Transaction failed";
  },
};
