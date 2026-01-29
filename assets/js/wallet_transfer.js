/**
 * WalletTransferHook - Handle transfers between hardware wallet and Blockster smart wallet
 *
 * Supports:
 * - Send ROGUE from hardware wallet to Blockster (hardware → smart wallet)
 * - Send ROGUE from Blockster to hardware wallet (smart wallet → hardware via BUX Minter)
 */

export const WalletTransferHook = {
  mounted() {
    console.log("[WalletTransfer] Hook mounted");

    // Transfer from hardware wallet to Blockster smart wallet
    this.handleEvent("transfer_to_blockster", async ({
      amount,
      blockster_wallet
    }) => {
      try {
        console.log("[WalletTransfer] Transferring", amount, "ROGUE to Blockster wallet:", blockster_wallet);

        // Get connected wallet from window (set by ConnectWalletHook)
        const connectedWallet = window.connectedHardwareWallet;

        if (!connectedWallet) {
          throw new Error("No wallet connected. Please connect your wallet first.");
        }

        // Dynamic imports
        const { prepareTransaction, sendTransaction, waitForReceipt } = await import("thirdweb");

        // Get the active account from connected wallet
        const account = connectedWallet.getAccount();

        if (!account) {
          throw new Error("No active account found");
        }

        console.log("[WalletTransfer] Preparing transaction from:", account.address);

        // Switch to Rogue Chain (only chain where we can transfer ROGUE to Blockster)
        await connectedWallet.switchChain(window.rogueChain);

        // Convert amount to wei (ROGUE has 18 decimals)
        const amountWei = BigInt(Math.floor(amount * 1e18));

        // Prepare native ROGUE transfer on Rogue Chain
        const transaction = prepareTransaction({
          to: blockster_wallet,
          value: amountWei,
          chain: window.rogueChain,
          client: window.thirdwebClient
        });

        console.log("[WalletTransfer] Sending transaction...");

        // Send transaction (user confirms in wallet)
        const { transactionHash } = await sendTransaction({
          transaction,
          account
        });

        console.log("[WalletTransfer] Transaction sent:", transactionHash);

        // Notify Phoenix that tx was submitted
        this.pushEvent("transfer_submitted", {
          tx_hash: transactionHash,
          amount: amount,
          from_address: account.address,
          to_address: blockster_wallet,
          direction: "to_blockster",
          token: "ROGUE",
          chain_id: 560013
        });

        // Wait for confirmation in background
        console.log("[WalletTransfer] Waiting for confirmation...");

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash
        });

        console.log("[WalletTransfer] Transaction confirmed:", receipt);

        // Notify Phoenix of confirmation
        this.pushEvent("transfer_confirmed", {
          tx_hash: transactionHash,
          block_number: Number(receipt.blockNumber),
          gas_used: Number(receipt.gasUsed),
          amount: amount,
          direction: "to_blockster",
          status: receipt.status === "success" ? "confirmed" : "failed"
        });

      } catch (error) {
        console.error("[WalletTransfer] Transfer failed:", error);

        // Parse user-friendly error
        let errorMessage = error.message;

        if (error.message.includes("User rejected") || error.message.includes("user rejected")) {
          errorMessage = "Transfer cancelled by user";
        } else if (error.message.includes("insufficient funds")) {
          errorMessage = "Insufficient ROGUE balance for transfer + gas fees";
        } else if (error.message.includes("No wallet connected")) {
          errorMessage = error.message;
        }

        this.pushEvent("transfer_error", {
          error: errorMessage,
          direction: "to_blockster"
        });
      }
    });

    // Transfer from Blockster smart wallet to hardware wallet
    this.handleEvent("transfer_from_blockster", async ({
      amount,
      to_address,
      from_address
    }) => {
      try {
        console.log("[WalletTransfer] Transferring", amount, "ROGUE from Blockster to hardware wallet:", to_address);

        // Get Blockster smart wallet from window (set by ThirdwebWallet hook)
        const smartWallet = window.smartAccount;

        if (!smartWallet) {
          throw new Error("No Blockster wallet found. Please refresh and try again.");
        }

        console.log("[WalletTransfer] Using Blockster smart wallet:", smartWallet.address);

        // Dynamic imports
        const { prepareTransaction, sendTransaction, waitForReceipt } = await import("thirdweb");

        // Convert amount to wei (ROGUE has 18 decimals)
        const amountWei = BigInt(Math.floor(amount * 1e18));

        // Prepare native ROGUE transfer from smart wallet
        const transaction = prepareTransaction({
          to: to_address,
          value: amountWei,
          chain: window.rogueChain
        });

        console.log("[WalletTransfer] Sending transaction...");

        // Send transaction (gasless via Paymaster for smart wallet)
        const { transactionHash } = await sendTransaction({
          transaction,
          account: smartWallet
        });

        console.log("[WalletTransfer] Transaction sent:", transactionHash);

        // Notify Phoenix that tx was submitted
        this.pushEvent("transfer_submitted", {
          tx_hash: transactionHash,
          amount: amount,
          from_address: from_address,
          to_address: to_address,
          direction: "from_blockster",
          token: "ROGUE",
          chain_id: 560013
        });

        // Wait for confirmation in background
        console.log("[WalletTransfer] Waiting for confirmation...");

        const receipt = await waitForReceipt({
          client: window.thirdwebClient,
          chain: window.rogueChain,
          transactionHash
        });

        console.log("[WalletTransfer] Transaction confirmed:", receipt);

        // Notify Phoenix of confirmation
        this.pushEvent("transfer_confirmed", {
          tx_hash: transactionHash,
          block_number: Number(receipt.blockNumber),
          gas_used: Number(receipt.gasUsed),
          amount: amount,
          direction: "from_blockster",
          status: receipt.status === "success" ? "confirmed" : "failed"
        });

      } catch (error) {
        console.error("[WalletTransfer] Transfer from Blockster failed:", error);

        // Parse user-friendly error
        let errorMessage = error.message;

        if (error.message.includes("User rejected") || error.message.includes("user rejected")) {
          errorMessage = "Transfer cancelled by user";
        } else if (error.message.includes("insufficient funds")) {
          errorMessage = "Insufficient ROGUE balance in Blockster wallet";
        } else if (error.message.includes("No Blockster wallet")) {
          errorMessage = error.message;
        }

        this.pushEvent("transfer_error", {
          error: errorMessage,
          direction: "from_blockster"
        });
      }
    });
  }
};
