/**
 * @deprecated EVM/Rogue Chain — replaced by Solana wallet integration.
 * These hooks are no longer functional. See solana_wallet.js for the current implementation.
 *
 * Previously contained Thirdweb initialization, Rogue Chain config, and EVM wallet login.
 * Stubbed to eliminate ~5MB thirdweb bundle dependency.
 */

export const HomeHooks = {
  mounted() {
    console.warn("HomeHooks is deprecated (EVM/Rogue Chain). This hook is non-functional.");
  }
};

export const ModalHooks = {
  mounted() {
    console.warn("ModalHooks is deprecated (EVM/Rogue Chain). This hook is non-functional.");
  }
};

export const DropdownHooks = {
  mounted() {
    console.warn("DropdownHooks is deprecated (EVM/Rogue Chain). This hook is non-functional.");
  }
};

export const SearchHooks = {
  mounted() {
    console.warn("SearchHooks is deprecated (EVM/Rogue Chain). This hook is non-functional.");
  }
};

export const ThirdwebLogin = {
  mounted() {
    console.warn("ThirdwebLogin is deprecated (EVM/Rogue Chain). This hook is non-functional.");
  }
};

export const ThirdwebWallet = {
  mounted() {
    console.warn("ThirdwebWallet is deprecated (EVM/Rogue Chain). This hook is non-functional.");
  }
};
