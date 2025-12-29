import { createThirdwebClient } from "thirdweb";
import { inAppWallet, createWallet, smartWallet } from "thirdweb/wallets";
import { preAuthenticate } from "thirdweb/wallets/in-app";
import { defineChain } from "thirdweb/chains";

// Initialize Thirdweb client - client ID is loaded from environment variable
// Set THIRDWEB_CLIENT_ID in your .env file
const getClient = () => {
  if (!window.THIRDWEB_CLIENT_ID) {
    console.error('THIRDWEB_CLIENT_ID not found. Please set it in your .env file.');
    return null;
  }
  return createThirdwebClient({
    clientId: window.THIRDWEB_CLIENT_ID
  });
};

let client = null;
let rpc
let id
let blockExplorer
let factoryAddress
let paymasterAddress
let entryPoint
let bundlerUrl
if (window.location.origin != "http://localhost:40001111111") { // changed from 4000 to use mainnet all the time, testnet down
    // Mainnet (Production) - Chain ID: 560013
    id = 560013
    blockExplorer = "https://roguescan.io"
    rpc = "https://rpc.roguechain.io/rpc"
    factoryAddress = "0xfbbe1193496752e99BA6Ad74cdd641C33b48E0C3" // ManagedAccountFactory (mainnet)
    paymasterAddress = "0x804cA06a85083eF01C9aE94bAE771446c25269a6" // EIP7702Paymaster (mainnet)
    entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789" // EntryPoint v0.6.0 (canonical)
    bundlerUrl = "https://rogue-bundler-mainnet.fly.dev" // Mainnet bundler on Fly.io
} else {
    // Testnet (Localhost) - Chain ID: 71499284269
    id = 71499284269
    blockExplorer = "https://testnet-explorer.roguechain.io/"
    rpc = "https://testnet-rpc.roguechain.io" // Rogue Chain testnet RPC
    // ManagedAccountFactory (Thirdweb Advanced) - DEPLOYED & STAKED
    factoryAddress = "0x39CeCF786830d1E073e737870E2A6e66fE92FDE9" // ManagedAccountFactory (testnet)
    paymasterAddress = "0xd4ECb9C22e0c7495e167698cb8D0D9c84F65c02a" // EIP7702Paymaster (testnet)
    entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789" // EntryPoint v0.6.0 (canonical)
    bundlerUrl = "https://rogue-bundler-testnet.fly.dev" // Testnet bundler on Fly.io
} 

// Define Rogue Chain with custom RPC
const rogueChain = defineChain({
  id: id,
  name: "Rogue Chain",
  nativeCurrency: {
    name: "Rogue",
    symbol: "ROGUE",
    decimals: 18,
  },
  rpc: rpc,
  blockExplorers: [blockExplorer],
});

// Expose globals for use by other hooks (e.g., BuxBoosterOnchain)
window.rogueChain = rogueChain;
// Initialize and expose the Thirdweb client
const initClient = getClient();
if (initClient) {
  window.thirdwebClient = initClient;
}

export const HomeHooks = {
  mounted() {
    // Toggle modal function
    this.handleEvent("toggle_modal", ({ id }) => {
      const modal = document.getElementById(id);
      if (modal) {
        modal.classList.toggle('hidden');
      }
    });

    // Drag-to-scroll for walker elements
    const walkers = this.el.querySelectorAll(".walker");
    walkers.forEach(walk => {
      let isDown = false, startX, scrollLeft;

      walk.addEventListener("mousedown", e => {
        isDown = true;
        startX = e.pageX - walk.offsetLeft;
        scrollLeft = walk.scrollLeft;
      });

      walk.addEventListener("mouseleave", () => isDown = false);
      walk.addEventListener("mouseup", () => isDown = false);

      walk.addEventListener("mousemove", e => {
        if (!isDown) return;
        e.preventDefault();
        const x = e.pageX - walk.offsetLeft;
        walk.scrollLeft = scrollLeft - (x - startX) * 2;
      });
    });

    // Bottom nav scroll effect
    const handleScroll = () => {
      const bottomNav = document.querySelector('.fixed-bottom-nav');
      if (bottomNav) {
        if (window.scrollY > 1) {
          bottomNav.classList.add('scrolled');
        } else {
          bottomNav.classList.remove('scrolled');
        }
      }
    };

    window.addEventListener('scroll', handleScroll);

    // Cleanup on destroy
    this.handleEvent("cleanup", () => {
      window.removeEventListener('scroll', handleScroll);
    });
  }
};

export const ModalHooks = {
  mounted() {
    this.el.addEventListener('click', (e) => {
      if (e.target === this.el) {
        this.el.classList.add('hidden');
      }
    });
  }
};

export const DropdownHooks = {
  mounted() {
    this.el.addEventListener('click', (e) => {
      e.stopPropagation();
      const dropdown = this.el.querySelector('.nested-list, .nested-list-drop, .footer-list');
      if (dropdown) {
        const isOpen = dropdown.classList.contains('show');

        // Close all other dropdowns
        document.querySelectorAll('.nested-list, .nested-list-drop, .footer-list').forEach(dd => {
          if (dd !== dropdown) {
            dd.classList.remove('show');
            dd.style.height = '0px';
          }
        });

        if (isOpen) {
          dropdown.classList.remove('show');
          dropdown.style.height = '0px';
        } else {
          dropdown.classList.add('show');
          dropdown.style.height = dropdown.scrollHeight + 'px';
        }
      }
    });
  }
};

export const SearchHooks = {
  mounted() {
    const searchBtn = this.el.querySelector('.search-trigger');
    const searchMobile = document.querySelector('.search-mobile');
    const noSearchWrapper = document.querySelector('.no-search-wrapper');
    const searchModal = document.getElementById('searchModal');

    if (searchBtn) {
      searchBtn.addEventListener('click', () => {
        if (noSearchWrapper) noSearchWrapper.classList.add('hidden');
        if (searchMobile) searchMobile.classList.remove('hidden');
        if (searchModal) searchModal.classList.remove('hidden');
      });
    }

    // Close search function
    const closeBtn = this.el.querySelector('[data-close-search]');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => {
        if (searchMobile) searchMobile.classList.add('hidden');
        if (searchModal) searchModal.classList.add('hidden');
        if (noSearchWrapper) noSearchWrapper.classList.remove('hidden');
      });
    }
  }
};

export const ThirdwebLogin = {
  mounted() {
    console.log('ThirdwebLogin hook mounted on login page');

    // Expose this hook instance globally for disconnect button
    window.ThirdwebLoginHook = this;

    // Initialize the Thirdweb client
    client = getClient();
    if (!client) {
      console.error('Failed to initialize Thirdweb client. Email authentication will not work.');
    }

    // Initialize the in-app wallet (will be used as personal account for smart wallet)
    this.personalWallet = inAppWallet();
    // Store in window for global access
    window.personalWallet = this.personalWallet;

    // Initialize smart wallet that wraps the in-app wallet
    // Bundler service deployed on Fly.io (Rundler v0.9.2)
    const walletConfig = {
      chain: rogueChain,
      factoryAddress: factoryAddress,
      gasless: true, // Enable gasless mode (uses paymaster)
      overrides: {
        entryPoint: entryPoint,
        // Rundler bundler deployed on Fly.io (separate apps for testnet/mainnet)
        bundlerUrl: bundlerUrl,

        // Paymaster configuration with gas sponsorship
        // OPTIMIZED: Reduced gas limits for faster transaction processing
        paymaster: async (userOp) => {
          console.log('💰 Paymaster function called');

          // Convert BigInt to string for logging
          const userOpForLog = {};
          for (const key in userOp) {
            userOpForLog[key] = typeof userOp[key] === 'bigint' ? userOp[key].toString() : userOp[key];
          }
          console.log('   UserOp received:', userOpForLog);

          // Check if initCode is present (account deployment)
          const hasInitCode = userOp.initCode && userOp.initCode !== '0x' && userOp.initCode.length > 2;

          // Check if callData suggests a batch transaction (executeBatch)
          const isBatchTx = userOp.callData && userOp.callData.startsWith('0x47e1da2a'); // executeBatch selector

          // Fill in any missing gas values with optimized amounts
          // Reduced from previous conservative values for better performance
          if (!userOp.preVerificationGas || userOp.preVerificationGas === '0x0' || userOp.preVerificationGas === 0n) {
            // Reduced from 46856 to 30000 (sufficient for standard UserOps)
            userOp.preVerificationGas = '0x7530'; // 30000
          }

          if (!userOp.verificationGasLimit || userOp.verificationGasLimit === '0x0' || userOp.verificationGasLimit === 0n) {
            if (hasInitCode) {
              // Account deployment needs high gas - keep at 400000
              userOp.verificationGasLimit = '0x061a80'; // 400000
              console.log('   🏭 Account deployment detected, using higher verificationGasLimit');
            } else {
              // Reduced from 100000 to 62500 for regular verification
              userOp.verificationGasLimit = '0xf424'; // 62500
            }
          }

          if (!userOp.callGasLimit || userOp.callGasLimit === '0x0' || userOp.callGasLimit === 0n) {
            if (isBatchTx) {
              // Batch transactions (approve + placeBet) need more gas
              userOp.callGasLimit = '0x493e0'; // 300000 for batched operations
              console.log('   📦 Batch transaction detected, using higher callGasLimit');
            } else {
              // Single operations use standard gas
              userOp.callGasLimit = '0x30d40'; // 200000 (increased from 120000 for safety)
            }
          }

          console.log('✅ Paymaster returning paymasterAndData');

          // SimplePaymaster (EIP7702) only needs address - no signature validation
          // Rundler configured with --unsafe flag to bypass strict paymaster checks
          console.log('📝 PaymasterAndData (SimplePaymaster):', paymasterAddress);

          // Add 20% buffer to preVerificationGas to avoid bundler precheck errors
          let preVerificationGas = userOp.preVerificationGas;
          if (typeof preVerificationGas === 'bigint') {
            preVerificationGas = preVerificationGas + (preVerificationGas / 5n);  // +20%
          } else if (typeof preVerificationGas === 'string') {
            const pvg = BigInt(preVerificationGas);
            preVerificationGas = '0x' + (pvg + (pvg / 5n)).toString(16);
          }

          return {
            paymasterAndData: paymasterAddress,
            // Return optimized gas values to skip bundler's gas estimation
            // Rogue Chain RPC throws Router errors during simulation
            callGasLimit: userOp.callGasLimit,
            verificationGasLimit: userOp.verificationGasLimit,
            preVerificationGas: preVerificationGas,
          };
        },
      },
      sponsorGas: true, // Enable paymaster gas sponsorship
    };

    console.log(`✅ Smart wallet configuration for Rogue Chain:`);
    console.log(`   Chain: ${rogueChain.name} (${rogueChain.id})`);
    console.log(`   Factory: ${factoryAddress}`);
    console.log(`   EntryPoint: ${entryPoint}`);
    console.log(`   Bundler: ${bundlerUrl}`);
    console.log(`   Paymaster: ${paymasterAddress}`);
    console.log(`   Gas Sponsorship: ENABLED ✅`);

    this.wallet = smartWallet(walletConfig);
    // Store in window for global access
    window.smartWalletInstance = this.wallet;

    this.activeWallet = null;

    // Try to auto-connect the wallet if user is already logged in
    this.autoConnectWallet();

    // Check if user is already authenticated (redirect if so)
    this.checkCurrentUser();

    // Attach event listeners to buttons
    this.attachEventListeners();
  },

  updated() {
    console.log('ThirdwebLogin hook updated - reattaching event listeners');
    this.attachEventListeners();
  },

  attachEventListeners() {
    console.log('attachEventListeners() called');

    // Get all the buttons
    const metamaskBtn = document.getElementById('connect-metamask');
    const trustBtn = document.getElementById('connect-trust');
    const walletConnectBtn = document.getElementById('connect-walletconnect');
    const emailBtn = document.getElementById('connect-email');
    const sendCodeBtn = document.getElementById('send-code-btn');
    const verifyCodeBtn = document.getElementById('verify-code-btn');
    const resendCodeBtn = document.getElementById('resend-code-btn');

    console.log('Found buttons:', {
      metamaskBtn,
      trustBtn,
      walletConnectBtn,
      emailBtn,
      sendCodeBtn,
      verifyCodeBtn,
      resendCodeBtn
    });

    // Wallet connections
    if (metamaskBtn && !metamaskBtn.dataset.listenerAttached) {
      metamaskBtn.addEventListener('click', () => {
        console.log('MetaMask button clicked');
        this.connectMetaMask();
      });
      metamaskBtn.dataset.listenerAttached = 'true';
    }

    if (trustBtn && !trustBtn.dataset.listenerAttached) {
      trustBtn.addEventListener('click', () => {
        console.log('Trust Wallet button clicked');
        this.connectTrust();
      });
      trustBtn.dataset.listenerAttached = 'true';
    }

    if (walletConnectBtn && !walletConnectBtn.dataset.listenerAttached) {
      walletConnectBtn.addEventListener('click', () => {
        console.log('WalletConnect button clicked');
        this.connectWalletConnect();
      });
      walletConnectBtn.dataset.listenerAttached = 'true';
    }

    if (emailBtn && !emailBtn.dataset.listenerAttached) {
      emailBtn.addEventListener('click', () => {
        console.log('Email button clicked');
        this.pushEvent("show_email_form", {});
      });
      emailBtn.dataset.listenerAttached = 'true';
    }

    // Email flow
    if (sendCodeBtn && !sendCodeBtn.dataset.listenerAttached) {
      sendCodeBtn.addEventListener('click', () => {
        console.log('Send code button clicked');
        this.sendVerificationCode();
      });
      sendCodeBtn.dataset.listenerAttached = 'true';
    }

    if (verifyCodeBtn && !verifyCodeBtn.dataset.listenerAttached) {
      verifyCodeBtn.addEventListener('click', () => {
        console.log('Verify code button clicked');
        this.verifyCode();
      });
      verifyCodeBtn.dataset.listenerAttached = 'true';
    }

    if (resendCodeBtn && !resendCodeBtn.dataset.listenerAttached) {
      resendCodeBtn.addEventListener('click', () => {
        console.log('Resend code button clicked');
        this.sendVerificationCode();
      });
      resendCodeBtn.dataset.listenerAttached = 'true';
    }

    // Enter key support
    const emailInput = document.getElementById('email-input');
    const codeInput = document.getElementById('code-input');

    if (emailInput && !emailInput.dataset.listenerAttached) {
      emailInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
          console.log('Enter key pressed in email input');
          this.sendVerificationCode();
        }
      });
      emailInput.dataset.listenerAttached = 'true';
    }

    if (codeInput && !codeInput.dataset.listenerAttached) {
      codeInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
          console.log('Enter key pressed in code input');
          this.verifyCode();
        }
      });
      codeInput.dataset.listenerAttached = 'true';
    }

    console.log('Event listeners attached successfully');
  },

  async checkCurrentUser() {
    try {
      const response = await fetch('/api/auth/me', {
        method: 'GET',
        credentials: 'same-origin',
        headers: {
          'Accept': 'application/json'
        }
      });

      if (response.ok) {
        const data = await response.json();
        if (data.success && data.user) {
          console.log('User already authenticated:', data.user);
          this.currentUser = data.user;
          this.updateUI(data.user);
        }
      }
    } catch (error) {
      console.error('Error checking authentication:', error);
    }
  },


  async connectMetaMask() {
    try {
      this.pushEvent("show_loading", {});

      // Step 1: Create and connect MetaMask wallet
      const metamaskWallet = createWallet("io.metamask");
      const personalAccount = await metamaskWallet.connect({ client });

      console.log('Connected to MetaMask:', personalAccount.address);

      // Step 2: Wrap in smart wallet
      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      console.log('Smart wallet created:', smartAccount.address);
      await this.authenticateWallet(smartAccount.address);
    } catch (error) {
      console.error('MetaMask connection error:', error);
      alert('Failed to connect to MetaMask. Please try again.');
      this.pushEvent("back_to_wallets", {});
    }
  },

  async connectTrust() {
    try {
      this.pushEvent("show_loading", {});

      // Step 1: Create and connect Trust Wallet
      const trustWallet = createWallet("com.trustwallet.app");
      const personalAccount = await trustWallet.connect({ client });

      console.log('Connected to Trust Wallet:', personalAccount.address);

      // Step 2: Wrap in smart wallet
      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      console.log('Smart wallet created:', smartAccount.address);
      await this.authenticateWallet(smartAccount.address);
    } catch (error) {
      console.error('Trust Wallet connection error:', error);
      alert('Failed to connect to Trust Wallet. Please try again.');
      this.pushEvent("back_to_wallets", {});
    }
  },

  async connectWalletConnect() {
    try {
      this.pushEvent("show_loading", {});

      // Step 1: Create and connect WalletConnect wallet
      const wcWallet = createWallet("walletConnect");
      const personalAccount = await wcWallet.connect({ client });

      console.log('Connected via WalletConnect:', personalAccount.address);

      // Store the WalletConnect wallet for signing UserOps
      window.thirdwebActiveWallet = wcWallet;
      console.log('✅ Stored WalletConnect wallet for UserOp signing');

      // Step 2: Wrap in smart wallet
      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      console.log('Smart wallet created:', smartAccount.address);
      await this.authenticateWallet(smartAccount.address);
    } catch (error) {
      console.error('WalletConnect connection error:', error);
      alert('Failed to connect via WalletConnect. Please try again.');
      this.pushEvent("back_to_wallets", {});
    }
  },

  async sendVerificationCode() {
    console.log('sendVerificationCode() called');

    const emailInput = document.getElementById('email-input');
    const email = emailInput?.value.trim();

    console.log('Email input element:', emailInput);
    console.log('Email value:', email);

    if (!email) {
      alert('Please enter your email address');
      return;
    }

    if (!this.isValidEmail(email)) {
      alert('Please enter a valid email address');
      return;
    }

    try {
      console.log('Sending verification code to:', email);
      console.log('Thirdweb client:', client);

      if (!client) {
        alert('Thirdweb client not initialized. Please check THIRDWEB_CLIENT_ID configuration.');
        return;
      }

      // Disable the button to prevent double-clicks
      const sendCodeBtn = document.getElementById('send-code-btn');
      if (sendCodeBtn) {
        sendCodeBtn.disabled = true;
        sendCodeBtn.textContent = 'Sending...';
      }

      console.log('Calling preAuthenticate...');
      await preAuthenticate({
        client: client,
        strategy: "email",
        email: email,
      });

      console.log('preAuthenticate succeeded! Showing code input...');

      // Store email for later use
      this.pendingEmail = email;
      console.log('Stored pending email:', this.pendingEmail);

      // Update LiveView state to show code input
      this.pushEvent("show_code_input", { email: email });

      // Focus on code input after LiveView updates
      setTimeout(() => {
        const codeInput = document.getElementById('code-input');
        console.log('Focusing code input:', codeInput);
        codeInput?.focus();
      }, 100);

      console.log('Verification code sent successfully!');
    } catch (error) {
      console.error('Error sending verification code:', error);
      console.error('Error details:', error.message, error.stack);

      // Re-enable the button on error
      const sendCodeBtn = document.getElementById('send-code-btn');
      if (sendCodeBtn) {
        sendCodeBtn.disabled = false;
        sendCodeBtn.textContent = 'Send Verification Code';
      }

      alert('Failed to send verification code. Please try again. Error: ' + error.message);
    }
  },

  async verifyCode() {
    const codeInput = document.getElementById('code-input');
    const code = codeInput?.value.trim();

    if (!code || code.length !== 6) {
      alert('Please enter the 6-digit verification code');
      return;
    }

    try {
      this.pushEvent("show_loading", {});
      console.log('Verifying code...');

      // Step 1: Connect the personal wallet (inAppWallet)
      console.log('Step 1: Connecting personal wallet...');
      const personalAccount = await this.personalWallet.connect({
        client: client,
        strategy: "email",
        email: this.pendingEmail,
        verificationCode: code,
      });

      console.log('Email verified! Personal account:', personalAccount.address);

      // Store the personal wallet for signing UserOps
      window.thirdwebActiveWallet = this.personalWallet;
      console.log('✅ Stored personal wallet for UserOp signing');

      // Step 2: Wrap personal wallet in smart wallet
      console.log('Step 2: Creating smart wallet...');
      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      console.log('Smart wallet created:', smartAccount.address);

      // Store the smart account for later use (in multiple places for persistence)
      this.smartAccount = smartAccount;
      window.smartAccount = smartAccount;
      // Store address in localStorage so we can verify it's the same user
      localStorage.setItem('smartAccountAddress', smartAccount.address);

      // Pass both personal wallet (EOA) and smart wallet addresses
      await this.authenticateEmail(this.pendingEmail, personalAccount.address, smartAccount.address);
    } catch (error) {
      console.error('Verification error:', error);
      console.error('Error message:', error.message);
      console.error('Error stack:', error.stack);

      // Show detailed error to user
      const errorMsg = error.message || 'Unknown error occurred';
      alert(`Verification failed: ${errorMsg}\n\nPlease check the console for details.`);

      this.pushEvent("show_code_input", { email: this.pendingEmail });
      if (codeInput) {
        codeInput.value = '';
        setTimeout(() => codeInput?.focus(), 100);
      }
    }
  },

  isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  },

  async authenticateWallet(walletAddress) {
    try {
      const response = await fetch('/api/auth/wallet/verify', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          wallet_address: walletAddress,
          chain_id: 560013
        })
      });

      const data = await response.json();

      if (data.success) {
        console.log('Wallet authenticated successfully:', data.user);
        this.currentUser = data.user;
        this.updateUI(data.user);
        window.location.reload(); // Reload to update the UI
      } else {
        console.error('Authentication failed:', data.errors);
        alert('Authentication failed. Please try again.');
      }
    } catch (error) {
      console.error('Error authenticating wallet:', error);
      alert('Error connecting to server. Please try again.');
    }
  },

  async authenticateEmail(email, personalWalletAddress, smartWalletAddress) {
    try {
      const response = await fetch('/api/auth/email/verify', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          email: email,
          wallet_address: personalWalletAddress,
          smart_wallet_address: smartWalletAddress
        })
      });

      const data = await response.json();

      if (data.success) {
        console.log('Email authenticated successfully:', data.user);
        this.currentUser = data.user;
        this.updateUI(data.user);
        window.location.reload(); // Reload to update the UI
      } else {
        console.error('Authentication failed:', data.errors);
        alert('Authentication failed. Please try again.');
      }
    } catch (error) {
      console.error('Error authenticating email:', error);
      alert('Error connecting to server. Please try again.');
    }
  },

  async handleDisconnect() {
    try {
      console.log('🔓 Starting complete wallet disconnect...');

      // Step 1: Disconnect wallets
      if (this.personalWallet) {
        try {
          await this.personalWallet.disconnect();
          console.log('✅ Personal wallet disconnected');
        } catch (e) {
          console.log('Personal wallet disconnect error:', e);
        }
      }

      if (this.wallet) {
        try {
          await this.wallet.disconnect();
          console.log('✅ Smart wallet disconnected');
        } catch (e) {
          console.log('Smart wallet disconnect error:', e);
        }
      }

      // Step 3: Clear wallet-related storage only
      console.log('🧹 Clearing wallet-related storage...');

      // Get all localStorage keys
      const keysToRemove = [];
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        // Remove Thirdweb, WalletConnect, and other wallet-related keys
        if (key && (
          key.toLowerCase().includes('thirdweb') ||
          key.toLowerCase().includes('walletconnect') ||
          key.toLowerCase().includes('wallet') ||
          key.includes('TW_') ||
          key.toLowerCase().includes('ews') ||
          key === 'smartAccountAddress'
        )) {
          keysToRemove.push(key);
        }
      }

      // Remove wallet-related keys
      keysToRemove.forEach(key => {
        localStorage.removeItem(key);
        console.log('Removed localStorage key:', key);
      });
      console.log(`✅ Cleared ${keysToRemove.length} wallet-related localStorage items`);

      // Clear wallet-related sessionStorage
      const sessionKeysToRemove = [];
      for (let i = 0; i < sessionStorage.length; i++) {
        const key = sessionStorage.key(i);
        if (key && (
          key.toLowerCase().includes('thirdweb') ||
          key.toLowerCase().includes('walletconnect') ||
          key.toLowerCase().includes('wallet') ||
          key.includes('TW_') ||
          key.toLowerCase().includes('ews')
        )) {
          sessionKeysToRemove.push(key);
        }
      }

      sessionKeysToRemove.forEach(key => {
        sessionStorage.removeItem(key);
        console.log('Removed sessionStorage key:', key);
      });
      console.log(`✅ Cleared ${sessionKeysToRemove.length} wallet-related sessionStorage items`);

      // Clear wallet-related IndexedDB databases only
      try {
        const databases = await indexedDB.databases();
        console.log('🧹 Checking IndexedDB databases:', databases.length);
        for (const db of databases) {
          if (db.name && (
            db.name.toLowerCase().includes('thirdweb') ||
            db.name.toLowerCase().includes('walletconnect') ||
            db.name.toLowerCase().includes('wallet')
          )) {
            indexedDB.deleteDatabase(db.name);
            console.log('Deleted IndexedDB:', db.name);
          }
        }
      } catch (e) {
        console.log('IndexedDB cleanup error (may not be supported):', e);
      }

      // Step 4: Clear Thirdweb-related cookies
      console.log('🧹 Clearing Thirdweb cookies...');
      const cookies = document.cookie.split(';');
      for (let cookie of cookies) {
        const eqPos = cookie.indexOf('=');
        const name = eqPos > -1 ? cookie.substring(0, eqPos).trim() : cookie.trim();
        // Only clear cookies that contain thirdweb, walletconnect, or TW_
        if (name.toLowerCase().includes('thirdweb') ||
            name.toLowerCase().includes('walletconnect') ||
            name.includes('TW_') ||
            name.toLowerCase().includes('ews')) { // Embedded Wallet Service
          // Delete cookie for all possible paths and domains
          document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/';
          document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=' + window.location.hostname;
          document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=.' + window.location.hostname;
          console.log('Cleared cookie:', name);
        }
      }
      console.log('✅ Thirdweb cookies cleared');

      // Step 5: Clear all references
      delete window.personalWallet;
      delete window.smartWalletInstance;
      delete window.smartAccount;
      delete window.thirdwebActiveWallet;
      delete window.ThirdwebLoginHook;

      this.personalWallet = null;
      this.wallet = null;
      this.smartAccount = null;
      this.activeWallet = null;

      // Step 5: Call backend logout
      const response = await fetch('/api/auth/logout', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Accept': 'application/json'
        }
      });

      const data = await response.json();

      if (data.success) {
        console.log('✅ Backend logout successful');
        this.currentUser = null;

        // Double-check storage is cleared before reload
        localStorage.removeItem('smartAccountAddress');
        console.log('Final check - smartAccountAddress cleared:', localStorage.getItem('smartAccountAddress') === null);

        // Small delay to ensure storage operations complete
        await new Promise(resolve => setTimeout(resolve, 100));

        console.log('🔄 Reloading page...');

        // Force a full page reload
        window.location.reload();
      } else {
        console.error('Logout failed:', data);
        alert('Failed to logout. Please try again.');
      }
    } catch (error) {
      console.error('Error logging out:', error);
      alert('Error disconnecting. Please try again.');
    }
  },

  updateUI(user) {
    // Update button text to show connected state
    const connectButton = this.el.querySelector('button span');
    if (connectButton) {
      const shortAddress = `${user.wallet_address.slice(0, 6)}...${user.wallet_address.slice(-4)}`;
      connectButton.textContent = user.username || shortAddress;
    }
  },

  async autoConnectWallet() {
    try {
      console.log('🚀 autoConnectWallet called');

      // Check URL hash for logout signal
      const hash = window.location.hash;
      const justLoggedOut = hash === '#logout';

      console.log('📊 URL hash:', hash);
      console.log('�� Just logged out:', justLoggedOut);
      console.log('📊 localStorage.smartAccountAddress:', localStorage.getItem('smartAccountAddress'));

      // CRITICAL: Check if user just logged out FIRST - prevent auto-reconnection
      if (justLoggedOut) {
        console.log('⛔ User just logged out - skipping auto-connect');

        // Clear the logout hash from URL
        window.history.replaceState({}, '', window.location.pathname);

        // Clear any remaining wallet data
        localStorage.removeItem('smartAccountAddress');
        console.log('✅ Logout flag detected and cleared - auto-connect prevented');
        return;
      }

      console.log('🔄 Auto-connect: Checking if user is already authenticated...');

      // Check if there's a stored smart account address (indicates previous login)
      const storedAddress = localStorage.getItem('smartAccountAddress');
      if (!storedAddress) {
        console.log('No stored wallet address found, skipping auto-connect');
        return;
      }

      console.log('Found stored wallet address:', storedAddress);

      // First, try to auto-connect the personal wallet (in-app wallet)
      // The in-app wallet has its own autoConnect method
      console.log('Step 1: Auto-connecting personal wallet...');

      const personalAccount = await this.personalWallet.autoConnect({
        client: client,
      });

      if (!personalAccount) {
        console.log('Personal wallet auto-connect returned null, no active session');
        // Clear stale data
        localStorage.removeItem('smartAccountAddress');
        delete window.smartAccount;
        delete this.smartAccount;
        return;
      }

      console.log('✅ Personal wallet auto-connected:', personalAccount.address);

      // Now connect the smart wallet using the personal account
      console.log('Step 2: Connecting smart wallet...');

      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      console.log('✅ Smart wallet connected:', smartAccount.address);

      // Verify it's the same account
      if (smartAccount.address.toLowerCase() !== storedAddress.toLowerCase()) {
        console.warn('⚠️ Connected wallet address does not match stored address');
        console.log('Expected:', storedAddress);
        console.log('Got:', smartAccount.address);
        // Clear stored data and require re-login
        localStorage.removeItem('smartAccountAddress');
        return;
      }

      // Store in multiple places for persistence
      this.smartAccount = smartAccount;
      window.smartAccount = smartAccount;

      console.log('✅ Auto-connect successful! Wallet is ready.');
    } catch (error) {
      console.log('Auto-connect failed (this is normal if user is not logged in):', error.message);
      // Clear any stale data
      localStorage.removeItem('smartAccountAddress');
      delete window.smartAccount;
      delete this.smartAccount;
    }
  },

  async testPaymaster() {
    // Set up network request interceptor to log all RPC calls
    const originalFetch = window.fetch;
    const rpcCalls = [];

    window.fetch = async (...args) => {
      const [url, options] = args;

      // Log all requests to Rogue Chain RPC or bundler
      if (url && (url.includes('roguechain.io') || url.includes('rogue-bundler'))) {
        const timestamp = new Date().toISOString();
        let body = null;

        if (options?.body) {
          try {
            body = JSON.parse(options.body);
          } catch (e) {
            body = options.body;
          }
        }

        const callInfo = {
          timestamp,
          url,
          method: body?.method || 'unknown',
          params: body?.params || [],
          id: body?.id
        };

        console.log('🌐 RPC Call:', callInfo);

        // Log UserOperation details if this is eth_estimateUserOperationGas
        if (body?.method === 'eth_estimateUserOperationGas' && body?.params?.[0]) {
          console.log('📦 FULL UserOperation being sent to bundler:');
          console.log(JSON.stringify(body.params[0], null, 2));
        }

        rpcCalls.push(callInfo);
      }

      // FIX: Remove paymaster during gas estimation to avoid Router errors
      // Then restore it for eth_sendUserOperation
      if (url && url.includes('rogue-bundler') && options?.body) {
        try {
          const body = JSON.parse(options.body);

          // Handle gas estimation - Rogue Chain RPC workarounds
          if (body?.method === 'eth_estimateUserOperationGas' && body?.params?.[0]) {
            const userOp = body.params[0];

            // Check if this is account deployment (initCode present)
            const hasInitCode = userOp.initCode && userOp.initCode !== '0x' && userOp.initCode.length > 2;

            // DEBUG AA14: Check address mismatch during gas estimation too
            if (hasInitCode) {
              console.log('🔍 DEBUG AA14 (gas estimation) - Checking factory address...');
              try {
                const factoryAddr = '0x' + userOp.initCode.slice(2, 42);
                const factoryCalldata = '0x' + userOp.initCode.slice(42);

                const rpcResponse = await originalFetch('https://testnet-rpc.roguechain.io', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    jsonrpc: '2.0',
                    method: 'eth_call',
                    params: [{
                      to: factoryAddr,
                      data: factoryCalldata
                    }, 'latest'],
                    id: 1
                  })
                });

                const rpcData = await rpcResponse.json();
                if (rpcData.result && rpcData.result !== '0x') {
                  const factoryAddress = '0x' + rpcData.result.slice(-40);
                  console.log('   ❌ MISMATCH:');
                  console.log('   Thirdweb sender:', userOp.sender);
                  console.log('   Factory returns:', factoryAddress);
                }
              } catch (e) {
                console.error('Failed to query factory:', e);
              }
            }

            // Workaround 1: Remove callData during account deployment
            if (hasInitCode && userOp.callData && userOp.callData !== '0x' && userOp.callData.length > 2) {
              console.log('🔧 Clearing callData during account deployment (Router workaround)');
              console.log('   Account deployment cannot include function calls - deploy first, call later');
              userOp.callData = '0x';
              options.body = JSON.stringify(body);
            }

            // Workaround 2: Remove paymaster during gas estimation to avoid Router errors
            // Rogue Chain RPC doesn't like simulating paymaster calls
            if (userOp.paymasterAndData && userOp.paymasterAndData !== '0x') {
              console.log('🔧 Removing paymaster for gas estimation (Rogue Chain RPC workaround)');
              window.tempPaymasterData = userOp.paymasterAndData;
              userOp.paymasterAndData = '0x';
              options.body = JSON.stringify(body);
            }

            console.log('📊 UserOp for gas estimation:');
            console.log(JSON.stringify(userOp, null, 2));
          }

          // Handle sendUserOperation - restore paymaster and handle deployment
          if (body?.method === 'eth_sendUserOperation' && body?.params?.[0]) {
            const userOp = body.params[0];

            // Check if this is account deployment
            const hasInitCode = userOp.initCode && userOp.initCode !== '0x' && userOp.initCode.length > 2;

            // DEBUG AA14: Log what address the factory will actually return
            if (hasInitCode) {
              console.log('🔍 DEBUG AA14 - Checking factory address calculation...');
              try {
                const factoryAddr = '0x' + userOp.initCode.slice(2, 42);
                const factoryCalldata = '0x' + userOp.initCode.slice(42);

                const rpcResponse = await originalFetch('https://testnet-rpc.roguechain.io', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    jsonrpc: '2.0',
                    method: 'eth_call',
                    params: [{
                      to: factoryAddr,
                      data: factoryCalldata
                    }, 'latest'],
                    id: 1
                  })
                });

                const rpcData = await rpcResponse.json();
                if (rpcData.result && rpcData.result !== '0x') {
                  const factoryAddress = '0x' + rpcData.result.slice(-40);
                  console.log('   ❌ MISMATCH DETECTED:');
                  console.log('   Thirdweb SDK sender:', userOp.sender);
                  console.log('   Factory will return:', factoryAddress);
                  console.log('   This is why we get AA14 error!');
                }
              } catch (e) {
                console.error('Failed to query factory:', e);
              }
            }

            // Restore paymaster if we stripped it during gas estimation
            if (window.tempPaymasterData && (!userOp.paymasterAndData || userOp.paymasterAndData === '0x')) {
              console.log('🔧 Restoring paymaster for sendUserOperation');
              userOp.paymasterAndData = window.tempPaymasterData;
              delete window.tempPaymasterData;
              options.body = JSON.stringify(body);
            }

            console.log('📤 UserOp being sent to bundler:');
            console.log(JSON.stringify(userOp, null, 2));
          }
        } catch (e) {
          console.error('Error in fetch interceptor:', e);
        }
      }

      // Make the actual request
      const response = await originalFetch(...args);

      // Log responses for RPC calls
      if (url && (url.includes('roguechain.io') || url.includes('rogue-bundler'))) {
        const clonedResponse = response.clone();
        try {
          const responseData = await clonedResponse.json();
          console.log('📥 RPC Response:', {
            url,
            status: response.status,
            data: responseData
          });

          // Check for Router error
          if (responseData?.error?.message?.includes('Router')) {
            console.error('🚨 ROUTER ERROR DETECTED:', {
              url,
              request: rpcCalls[rpcCalls.length - 1],
              error: responseData.error
            });
          }
        } catch (e) {
          // Not JSON response
        }
      }

      return response;
    };

    try {
      console.log('🧪 Testing paymaster gas sponsorship...');
      console.log('🔍 Network request logging enabled - all RPC calls will be logged');

      if (!this.wallet) {
        alert('Wallet not initialized. Please connect first.');
        return;
      }

      // Get personal wallet from window or this
      const personalWallet = window.personalWallet || this.personalWallet;

      if (!personalWallet) {
        alert('Personal wallet not initialized. Please log in first.');
        return;
      }

      // IMPORTANT: Always force a fresh connection to use the latest wallet configuration
      // This ensures we're not using a cached account with old paymaster settings
      console.log('Forcing fresh smart account connection with updated config...');

      // Clear any cached accounts
      delete window.smartAccount;
      delete this.smartAccount;

      // Try to get existing account first
      let personalAccount = personalWallet.getAccount();

      // If no account, try to auto-connect
      if (!personalAccount) {
        console.log('No personal account, trying auto-connect...');
        try {
          personalAccount = await personalWallet.autoConnect({
            client: client,
          });
        } catch (autoConnectError) {
          console.log('Auto-connect failed:', autoConnectError.message);
        }
      }

      // If still no account, session expired
      if (!personalAccount) {
        alert('Session expired. Please log in again.');
        window.location.href = '/login';
        return;
      }

      console.log('Personal account:', personalAccount.address);

      // Store the personal wallet for UserOp signing
      window.thirdwebActiveWallet = personalWallet;
      console.log('✅ Stored personal wallet for UserOp signing');

      // Connect smart wallet with latest configuration
      // Now using Rogue Chain RPC instead of bundler URL
      console.log('🔗 Connecting smart wallet...');
      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      // Store for future use in multiple places
      this.smartAccount = smartAccount;
      window.smartAccount = smartAccount;
      localStorage.setItem('smartAccountAddress', smartAccount.address);
      console.log('Smart account connected with updated configuration');

      console.log('Smart account:', smartAccount.address);
      console.log('📦 Preparing transaction to send 0 ROGUE to self via smart wallet...');
      console.log('✅ Testing bundler WITH paymaster gas sponsorship');
      console.log(`EntryPoint: ${entryPoint}`);
      console.log(`Factory: ${factoryAddress}`);
      console.log(`Paymaster: ${paymasterAddress}`);
      console.log(`Bundler: https://rogue-bundler.fly.dev`);

      // Use Thirdweb's sendTransaction which should work with bundlerUrl in smart account config
      const { sendTransaction, prepareTransaction } = await import('thirdweb');

      // Prepare a simple transaction to send 0 ROGUE to self
      const transaction = prepareTransaction({
        to: smartAccount.address,
        value: 0n,
        chain: rogueChain,
        client: client,
        gas: 100000n,
      });

      console.log('📤 Sending transaction via smart account (which will create UserOperation)...');
      console.log('The smart account is configured with bundlerUrl: https://rogue-bundler.fly.dev');

      // Send the transaction using SMART ACCOUNT
      // This should use the bundlerUrl configured in the smart account
      const result = await sendTransaction({
        transaction,
        account: smartAccount,
      });

      console.log('✅ Transaction submitted!');
      console.log('Transaction hash:', result.transactionHash);

      alert(`✅ Bundler test successful!\n\nTransaction Hash: ${result.transactionHash}\n\nThe bundler processed the UserOperation with paymaster gas sponsorship! Check the transaction on the explorer:\n${blockExplorer}/tx/${result.transactionHash}`);
    } catch (error) {
      console.error('❌ Paymaster test failed:', error);
      console.error('Error details:', error.message);
      console.error('Stack:', error.stack);

      // Log all RPC calls that were made
      console.log('📋 All RPC calls made during this test:', rpcCalls);

      // Check if it's the nonce/EntryPoint error
      if (error.message && (error.message.includes('AbiDecodingZeroDataError') || error.message.includes('Cannot decode zero data'))) {
        const helpMessage = `❌ Smart Wallet Setup Issue\n\nThe smart wallet cannot retrieve its nonce from the EntryPoint contract. This usually means:\n\n1. The EntryPoint contract is not deployed on Rogue Chain testnet\n2. The bundler doesn't support Rogue Chain\n3. The factory address may be incorrect\n\nFactory: ${factoryAddress}\nPaymaster: ${paymasterAddress}\nEntryPoint: ${entryPoint}\n\nPlease verify the EntryPoint contract is deployed on Rogue Chain testnet.`;
        alert(helpMessage);
      } else if (error.message && error.message.includes('Router')) {
        alert(`❌ Router Error Detected!\n\n${error.message}\n\nThis is a Rogue Chain RPC error. Check the console for the exact RPC call that failed.`);
      } else {
        alert(`❌ Paymaster test failed:\n\n${error.message}\n\nCheck console for full details including all RPC calls.`);
      }
    } finally {
      // Restore original fetch
      window.fetch = originalFetch;
      console.log('🔍 Network request logging disabled');
    }
  }
};

// ThirdwebWallet - Lightweight hook for wallet initialization on all pages
// This hook silently initializes the wallet without rendering any UI
// Use this on the site header so users can perform blockchain transactions
export const ThirdwebWallet = {
  mounted() {
    console.log('ThirdwebWallet hook mounted - silent wallet initialization');

    // Expose this hook instance globally for disconnect and transactions
    window.ThirdwebWalletHook = this;

    // Initialize the Thirdweb client
    client = getClient();
    if (!client) {
      console.error('Failed to initialize Thirdweb client');
      return;
    }

    // Initialize the in-app wallet (will be used as personal account for smart wallet)
    this.personalWallet = inAppWallet();
    window.personalWallet = this.personalWallet;

    // Initialize smart wallet configuration (same as ThirdwebLogin)
    const walletConfig = {
      chain: rogueChain,
      factoryAddress: factoryAddress,
      gasless: true,
      overrides: {
        entryPoint: entryPoint,
        bundlerUrl: bundlerUrl,
        paymaster: async (userOp) => {
          console.log('💰 Paymaster function called');

          const userOpForLog = {};
          for (const key in userOp) {
            userOpForLog[key] = typeof userOp[key] === 'bigint' ? userOp[key].toString() : userOp[key];
          }
          console.log('   UserOp received:', userOpForLog);

          if (!userOp.preVerificationGas || userOp.preVerificationGas === '0x0' || userOp.preVerificationGas === 0n) {
            userOp.preVerificationGas = '0xb708';
          }

          const hasInitCode = userOp.initCode && userOp.initCode !== '0x' && userOp.initCode.length > 2;

          if (!userOp.verificationGasLimit || userOp.verificationGasLimit === '0x0' || userOp.verificationGasLimit === 0n) {
            userOp.verificationGasLimit = hasInitCode ? '0x061a80' : '0x0186a0';
          }
          if (!userOp.callGasLimit || userOp.callGasLimit === '0x0' || userOp.callGasLimit === 0n) {
            userOp.callGasLimit = '0x1d4c0';
          }

          if (hasInitCode) {
            console.log('   🏭 Account deployment detected, using higher verificationGasLimit');
          }

          console.log('✅ Paymaster returning paymasterAndData');
          console.log('📝 PaymasterAndData (SimplePaymaster):', paymasterAddress);

          // Add 20% buffer to preVerificationGas to avoid bundler precheck errors
          let preVerificationGas = userOp.preVerificationGas;
          if (typeof preVerificationGas === 'bigint') {
            preVerificationGas = preVerificationGas + (preVerificationGas / 5n);  // +20%
          } else if (typeof preVerificationGas === 'string') {
            const pvg = BigInt(preVerificationGas);
            preVerificationGas = '0x' + (pvg + (pvg / 5n)).toString(16);
          }

          return {
            paymasterAndData: paymasterAddress,
            callGasLimit: userOp.callGasLimit,
            verificationGasLimit: userOp.verificationGasLimit,
            preVerificationGas: preVerificationGas,
          };
        },
      },
      sponsorGas: true,
    };

    this.wallet = smartWallet(walletConfig);
    window.smartWalletInstance = this.wallet;

    // Try to auto-connect silently
    this.autoConnectWallet();
  },

  destroyed() {
    console.log('ThirdwebWallet hook destroyed');
    delete window.ThirdwebWalletHook;
  },

  async autoConnectWallet() {
    try {
      console.log('🔄 ThirdwebWallet: Auto-connecting...');

      // Check URL hash for logout signal
      const hash = window.location.hash;
      if (hash === '#logout') {
        console.log('⛔ Logout detected - skipping auto-connect');
        window.history.replaceState({}, '', window.location.pathname);
        localStorage.removeItem('smartAccountAddress');
        return;
      }

      // Only auto-connect if user has an active server session
      const serverSmartWallet = this.el.dataset.smartWallet;
      if (!serverSmartWallet) {
        console.log('No server session, skipping auto-connect');
        localStorage.removeItem('smartAccountAddress');
        return;
      }

      // Sync localStorage with server session
      localStorage.setItem('smartAccountAddress', serverSmartWallet);

      console.log('Found wallet address from server session:', serverSmartWallet);

      // Auto-connect the personal wallet
      const personalAccount = await this.personalWallet.autoConnect({
        client: client,
      });

      if (!personalAccount) {
        console.log('Personal wallet auto-connect returned null');
        localStorage.removeItem('smartAccountAddress');
        return;
      }

      console.log('✅ Personal wallet auto-connected:', personalAccount.address);

      // Connect the smart wallet
      const smartAccount = await this.wallet.connect({
        client: client,
        personalAccount: personalAccount,
      });

      console.log('✅ Smart wallet connected:', smartAccount.address);

      // Verify it's the same account as server session
      if (smartAccount.address.toLowerCase() !== serverSmartWallet.toLowerCase()) {
        console.warn('⚠️ Wallet address mismatch with server session, clearing stored data');
        localStorage.removeItem('smartAccountAddress');
        return;
      }

      // Store for global access
      this.smartAccount = smartAccount;
      window.smartAccount = smartAccount;

      console.log('✅ ThirdwebWallet: Auto-connect successful! Wallet ready for transactions.');
    } catch (error) {
      console.log('ThirdwebWallet auto-connect failed:', error.message);
      localStorage.removeItem('smartAccountAddress');
      delete window.smartAccount;
    }
  },

  // Expose disconnect method for logout
  async handleDisconnect() {
    console.log('ThirdwebWallet: Disconnecting...');
    try {
      if (this.wallet) {
        await this.wallet.disconnect();
      }
      if (this.personalWallet) {
        await this.personalWallet.disconnect();
      }
      localStorage.removeItem('smartAccountAddress');
      delete window.smartAccount;
      delete this.smartAccount;
      console.log('✅ ThirdwebWallet: Disconnected');
    } catch (error) {
      console.error('Disconnect error:', error);
    }
  }
};
