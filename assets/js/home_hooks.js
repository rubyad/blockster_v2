import { createThirdwebClient } from "thirdweb";
import { inAppWallet, preAuthenticate } from "thirdweb/wallets/in-app";

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
    console.log('ThirdwebLogin hook mounted');

    // Expose this hook instance globally for disconnect button
    window.ThirdwebLoginHook = this;

    // Initialize the Thirdweb client
    client = getClient();
    if (!client) {
      console.error('Failed to initialize Thirdweb client. Email authentication will not work.');
    }

    // Initialize the in-app wallet
    this.wallet = inAppWallet();

    // Check if user is already authenticated
    this.checkCurrentUser();

    // Initialize the connect button
    this.initializeConnectButton();
  },

  updated() {
    console.log('ThirdwebLogin hook updated');
    this.initializeConnectButton();
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

  initializeConnectButton() {
    const connectButton = this.el.querySelector('button');
    if (connectButton && !connectButton.hasAttribute('data-thirdweb-initialized')) {
      connectButton.setAttribute('data-thirdweb-initialized', 'true');
      connectButton.addEventListener('click', () => this.handleConnect());
    }
  },

  async handleConnect() {
    try {
      console.log('Connecting wallet...');

      // For now, let's show a simple prompt to test the backend integration
      // In production, you'll integrate the full Thirdweb SDK modal
      const useWallet = confirm('Connect with wallet? (Click OK for wallet, Cancel for email)');

      if (useWallet) {
        // Test with MetaMask
        if (typeof window.ethereum !== 'undefined') {
          const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
          const walletAddress = accounts[0];
          console.log('Connected to MetaMask:', walletAddress);
          await this.authenticateWallet(walletAddress);
        } else {
          alert('Please install MetaMask to connect with a wallet');
        }
      } else {
        // Email signup with verification code
        await this.handleEmailAuth();
      }
    } catch (error) {
      console.error('Connection error:', error);
      alert('Failed to connect wallet. Please try again.');
    }
  },

  async handleEmailAuth() {
    try {
      // Step 1: Get user's email
      const email = prompt('Enter your email:');
      if (!email) return;

      console.log('Sending verification email to:', email);

      // Step 2: Send verification email using Thirdweb preAuthenticate
      await preAuthenticate({
        client: client,
        strategy: "email",
        email: email,
      });

      alert(`Verification code sent to ${email}. Please check your inbox.`);

      // Step 3: Prompt for verification code
      const code = prompt('Enter the 6-digit verification code from your email:');
      if (!code) {
        alert('Verification cancelled.');
        return;
      }

      console.log('Verifying code...');

      // Step 4: Connect wallet with the verification code
      const account = await this.wallet.connect({
        client: client,
        strategy: "email",
        email: email,
        verificationCode: code,
      });

      console.log('Email verified! Wallet address:', account.address);

      // Step 5: Authenticate with your backend
      await this.authenticateEmail(email, account.address);

    } catch (error) {
      console.error('Email authentication error:', error);
      alert('Failed to verify email. Please try again.');
    }
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
