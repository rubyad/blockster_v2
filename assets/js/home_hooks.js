import { createThirdwebClient } from "thirdweb";
import { inAppWallet, createWallet } from "thirdweb/wallets";
import { preAuthenticate } from "thirdweb/wallets/in-app";

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

    // Initialize the in-app wallet
    this.wallet = inAppWallet();
    this.activeWallet = null;

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
      if (typeof window.ethereum !== 'undefined') {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        const walletAddress = accounts[0];
        console.log('Connected to MetaMask:', walletAddress);
        await this.authenticateWallet(walletAddress);
      } else {
        alert('Please install MetaMask to connect with this wallet');
        this.pushEvent("back_to_wallets", {});
      }
    } catch (error) {
      console.error('MetaMask connection error:', error);
      alert('Failed to connect to MetaMask. Please try again.');
      this.pushEvent("back_to_wallets", {});
    }
  },

  async connectTrust() {
    try {
      this.pushEvent("show_loading", {});

      // Trust Wallet uses the injected provider like MetaMask
      if (typeof window.ethereum !== 'undefined') {
        // Check if Trust Wallet is available
        const isTrust = window.ethereum.isTrust;

        if (isTrust) {
          const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
          const walletAddress = accounts[0];
          console.log('Connected to Trust Wallet:', walletAddress);
          await this.authenticateWallet(walletAddress);
        } else {
          // If not Trust Wallet specifically, try connecting anyway (might be Trust Wallet without the flag)
          const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
          const walletAddress = accounts[0];
          console.log('Connected to wallet (possibly Trust):', walletAddress);
          await this.authenticateWallet(walletAddress);
        }
      } else {
        alert('Please install Trust Wallet to connect. Download it from trustwallet.com');
        this.pushEvent("back_to_wallets", {});
      }
    } catch (error) {
      console.error('Trust Wallet connection error:', error);
      alert('Failed to connect to Trust Wallet. Please try again.');
      this.pushEvent("back_to_wallets", {});
    }
  },

  async connectWalletConnect() {
    try {
      this.pushEvent("show_loading", {});
      const wallet = createWallet("walletConnect");
      const account = await wallet.connect({ client });
      console.log('Connected via WalletConnect:', account.address);
      await this.authenticateWallet(account.address);
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

      const account = await this.wallet.connect({
        client: client,
        strategy: "email",
        email: this.pendingEmail,
        verificationCode: code,
      });

      console.log('Email verified! Wallet address:', account.address);
      await this.authenticateEmail(this.pendingEmail, account.address);
    } catch (error) {
      console.error('Verification error:', error);
      alert('Invalid verification code. Please try again.');
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

  async authenticateEmail(email, walletAddress) {
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
          wallet_address: walletAddress
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
      const response = await fetch('/api/auth/logout', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Accept': 'application/json'
        }
      });

      const data = await response.json();

      if (data.success) {
        console.log('Logged out successfully');
        this.currentUser = null;
        window.location.reload(); // Reload to show connect button again
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
  }
};
