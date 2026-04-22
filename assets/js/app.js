// Node-global polyfills (Buffer/process/global). MUST be the first import
// so its side effects run before any Web3Auth / Solana deps evaluate.
import "./polyfills.js"

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Swiper - self-hosted instead of CDN for better performance
import Swiper from 'swiper';
import 'swiper/css';
import 'swiper/css/navigation';
import 'swiper/css/pagination';

// Make Swiper globally available
window.Swiper = Swiper;

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { TipTapEditor } from "./tiptap_editor.js";
import { FeaturedImageUpload } from "./featured_image_upload.js";
import { ContentFeaturedImageUpload } from "./content_featured_image_upload.js";
import { HubLogoUpload, HubLogoFormUpload } from "./hub_logo_upload.js";
import { TwitterWidgets } from "./twitter_widgets.js";
// DEPRECATED (EVM): home_hooks.js contained ThirdwebLogin/ThirdwebWallet hooks.
// None of those hooks are used in any template anymore. Import removed to eliminate
// the massive Thirdweb SDK bundle (~5MB) and SES lockdown that was causing blank page on load.
import { TimeTracker } from "./time_tracker.js";
import { EngagementTracker } from "./engagement_tracker.js";
import { PhoneNumberFormatter } from "./phone_number_formatter.js";
import { BannerUpload } from "./banner_upload.js";
import { BannerAdminUpload } from "./banner_admin_upload.js";
import { BannerDrag } from "./banner_drag.js";
import { TextBlockDrag, TextBlockDragResize, ButtonDrag, AdminControlsDrag } from "./text_block_drag.js";
import { ProductImageUpload } from "./product_image_upload.js";
import { ProductDescriptionEditor } from "./product_description_editor.js";
import { ArtistImageUpload } from "./artist_image_upload.js";
import { CoinFlip } from "./coin_flip.js";
// DEPRECATED (EVM): BuxBoosterOnchain - Rogue Chain on-chain game, replaced by CoinFlipSolana
import { BuxBoosterOnchain } from "./bux_booster_onchain.js";
import { CoinFlipSolana } from "./coin_flip_solana.js";
import { PoolHook } from "./hooks/pool_hook.js";
import { RtSkyscraperWidget } from "./hooks/widgets/rt_skyscraper.js";
import { FsSkyscraperWidget } from "./hooks/widgets/fs_skyscraper.js";
import { RtChartWidget } from "./hooks/widgets/rt_chart.js";
import { RtSquareCompactWidget } from "./hooks/widgets/rt_square_compact.js";
import { RtTickerWidget } from "./hooks/widgets/rt_ticker.js";
import { FsTickerWidget } from "./hooks/widgets/fs_ticker.js";
import { RtLeaderboardWidget } from "./hooks/widgets/rt_leaderboard.js";
import { FsHeroWidget } from "./hooks/widgets/fs_hero.js";
import { CfDemoCycle } from "./hooks/widgets/cf_demo_cycle.js";
import { CfLiveCycle } from "./hooks/widgets/cf_live_cycle.js";
import { VideoWatchTracker } from "./video_watch_tracker.js";
import { AnonymousClaimManager } from "./anonymous_claim_manager.js";
import { FingerprintHook } from "./fingerprint_hook.js";
// DEPRECATED (EVM): ConnectWalletHook, BalanceFetcherHook, WalletTransferHook - Rogue Chain hardware wallet integration
// Still used by onboarding_live wallet step and member_live profile page. Remove when those are migrated to Solana.
import { ConnectWalletHook } from "./connect_wallet_hook.js";
import { BalanceFetcherHook } from "./balance_fetcher.js";
import { WalletTransferHook } from "./wallet_transfer.js";
import { SolanaWallet } from "./hooks/solana_wallet.js";
import { BuxPaymentHook } from "./hooks/bux_payment.js";
// DEPRECATED (EVM): RoguePaymentHook - Rogue Chain native token shop payment. No longer used by any LiveView.
import { RoguePaymentHook } from "./hooks/rogue_payment.js";
import { SolPaymentHook } from "./hooks/sol_payment.js"
import { NotificationToastHook } from "./hooks/notification_toast.js";
import { EventTracker } from "./hooks/event_tracker.js";
// DEPRECATED (EVM): AirdropDepositHook - Rogue Chain EVM airdrop deposit, replaced by AirdropSolanaHook
import { AirdropDepositHook } from "./hooks/airdrop_deposit.js";
import { AirdropSolanaHook } from "./hooks/airdrop_solana.js";
import { PriceChart } from "./hooks/price_chart.js";
import { FsA2CombinedAd } from "./hooks/fs_a2_combined_ad.js";
import { FsKineticAd } from "./hooks/fs_kinetic_ad.js";
// Phase 5 production Web3Auth hook. Lazy-loads the SDK on first login.
import { Web3Auth } from "./hooks/web3auth_hook.js";
// /wallet self-custody panel — social-login users only.
import { Web3AuthWithdraw } from "./hooks/web3auth_withdraw.js";
import { Web3AuthExport } from "./hooks/web3auth_export.js";
import { PasteFromClipboard } from "./hooks/paste_from_clipboard.js";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

// Capture referral code from URL immediately on page load
(function captureReferralCode() {
  const urlParams = new URLSearchParams(window.location.search);
  const refCode = urlParams.get('ref');

  if (refCode && /^0x[a-fA-F0-9]{40}$/i.test(refCode)) {
    localStorage.setItem('blockster_referrer', refCode.toLowerCase());
    console.log('[Referral] Captured referrer from URL:', refCode);
  }
})();
// TagInput Hook for handling Enter key
let TagInput = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        const value = this.el.value.trim();
        if (value) {
          this.pushEventTo(this.el.dataset.componentId, "add_tag_from_input", { value });
        }
      }
    });
  }
};

// DepositBuxInput Hook - handles deposit BUX button click
let DepositBuxInput = {
  mounted() {
    const input = this.el.querySelector('#deposit-amount-input');
    const button = this.el.querySelector('#deposit-bux-btn');
    const target = this.el.dataset.target;

    if (button && input) {
      button.addEventListener('click', () => {
        const amount = input.value.trim();
        if (amount) {
          // Use pushEventTo to target the LiveComponent
          this.pushEventTo(target, "deposit_bux", { amount: amount });
          // Clear input after successful push
          input.value = '';
        }
      });
    }
  }
};

// Autocomplete Hook for closing dropdowns when clicking outside
let Autocomplete = {
  mounted() {
    this.handleClickOutside = (e) => {
      if (!this.el.contains(e.target)) {
        const dropdown = this.el.querySelector('.absolute');
        if (dropdown) {
          // Clear search results by triggering a blur event
          const input = this.el.querySelector('input[type="text"]');
          if (input) {
            input.value = input.value; // Keep the selected value
          }
        }
      }
    };

    document.addEventListener('click', this.handleClickOutside);
  },

  destroyed() {
    document.removeEventListener('click', this.handleClickOutside);
  }
};

// TokenInput Hook for instant value clamping when user enters more than max
let TokenInput = {
  mounted() {
    this.el.addEventListener("input", (e) => {
      // Allow empty input for typing
      if (this.el.value === '' || this.el.value === null) {
        return;
      }

      const max = parseFloat(this.el.dataset.max) || 0;
      let value = parseFloat(this.el.value);

      // If not a valid number, allow user to continue typing
      if (isNaN(value)) {
        return;
      }

      // Only clamp if value exceeds max (not if it's 0 or below)
      if (value > max) {
        this.el.value = max;
      } else if (value < 0) {
        this.el.value = 0;
      }
    });
  },

  updated() {
    // Don't update if user is actively editing (field is focused)
    if (document.activeElement === this.el) {
      return;
    }

    // When server updates the max, re-clamp current value
    const max = parseFloat(this.el.dataset.max) || 0;
    let value = parseFloat(this.el.value) || 0;
    if (value > max) {
      this.el.value = max;
    }
  }
};

// Mobile and Desktop Navigation Highlight Hook
let MobileNavHighlight = {
  mounted() {
    this.updateActiveNav();
    // Listen for LiveView navigation changes
    window.addEventListener('phx:navigate', () => {
      setTimeout(() => this.updateActiveNav(), 50);
    });
  },

  updated() {
    this.updateActiveNav();
  },

  updateActiveNav() {
    const currentPath = window.location.pathname;
    const links = this.el.querySelectorAll('[data-nav-path]');

    // Known section paths (everything else is considered "News" content)
    // Note: /hub (singular) is for hub detail pages, /hubs is the index
    const sectionPaths = ['/hubs', '/hub', '/shop', '/cart', '/checkout', '/airdrop', '/play', '/pool', '/members', '/login', '/admin'];

    // Check if current path is in a known section
    const isInKnownSection = sectionPaths.some(section =>
      currentPath === section || currentPath.startsWith(section + '/')
    );

    links.forEach(link => {
      const navPath = link.dataset.navPath;
      let isActive = false;

      if (navPath === '/') {
        // News icon: active on homepage OR any post page (not in known sections)
        isActive = currentPath === '/' || !isInKnownSection;
      } else if (navPath === '/hubs') {
        // Hubs nav: active for /hubs index AND /hub/:slug detail pages
        isActive = currentPath === '/hubs' || currentPath.startsWith('/hubs/') || currentPath.startsWith('/hub/');
      } else if (navPath === '/shop') {
        // Shop nav: active for /shop, /cart, and /checkout pages
        isActive = currentPath === '/shop' || currentPath.startsWith('/shop/') || currentPath === '/cart' || currentPath.startsWith('/checkout/');
      } else if (navPath === '/play') {
        // Play nav: active for /play and /pool pages
        isActive = currentPath === '/play' || currentPath.startsWith('/play/') || currentPath === '/pool' || currentPath.startsWith('/pool/');
      } else {
        // Other nav items: active if path matches or starts with nav path
        isActive = currentPath === navPath || currentPath.startsWith(navPath + '/');
      }

      if (isActive) {
        link.classList.add('bg-[#CAFC00]');
        link.classList.remove('hover:bg-gray-100');
      } else {
        link.classList.remove('bg-[#CAFC00]');
        link.classList.add('hover:bg-gray-100');
      }
    });
  }
};

// Deep-links the user into a wallet app's in-app browser at the current URL.
// Works for any Solana wallet with a universal-link browse URL (Phantom,
// Solflare). Resolves the mobile Safari / Chrome problem where Wallet Standard
// doesn't see the wallet unless the page is already inside its browser.
// Element must carry `data-browse-url` — e.g. `https://phantom.app/ul/browse/`.
let OpenInWallet = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const browseUrl = this.el.dataset.browseUrl;
      if (!browseUrl) return;
      const ref = encodeURIComponent(window.location.origin);
      const target = encodeURIComponent(window.location.href);
      window.location.href = `${browseUrl}${target}?ref=${ref}`;
    });
  }
};

// Design-system mobile bottom nav highlight. Toggles `data-active` on the
// current tab so Tailwind's `data-[active]:text-…` selectors style it.
let DsMobileNavHighlight = {
  mounted() {
    this.apply();
    window.addEventListener('phx:navigate', () => setTimeout(() => this.apply(), 50));
  },
  updated() {
    this.apply();
  },
  apply() {
    const path = window.location.pathname;
    const sections = ['/hubs', '/hub', '/shop', '/cart', '/checkout', '/airdrop', '/play', '/pool', '/members', '/member', '/login', '/admin'];
    const inKnown = sections.some(s => path === s || path.startsWith(s + '/'));

    this.el.querySelectorAll('[data-nav-path]').forEach(link => {
      const p = link.dataset.navPath;
      let active = false;

      if (p === '/') {
        // News: homepage, category/tag pages, and any unknown top-level path (article pages)
        active = path === '/' || !inKnown;
      } else if (p === '/hubs') {
        active = path === '/hubs' || path.startsWith('/hubs/') || path.startsWith('/hub/');
      } else if (p === '/shop') {
        active = path === '/shop' || path.startsWith('/shop/') || path === '/cart' || path.startsWith('/checkout/');
      } else {
        active = path === p || path.startsWith(p + '/');
      }

      if (active) link.setAttribute('data-active', 'true');
      else link.removeAttribute('data-active');
    });
  }
};

// Desktop Navigation Highlight Hook
let DesktopNavHighlight = {
  mounted() {
    this.updateActiveNav();
    window.addEventListener('phx:navigate', () => {
      setTimeout(() => this.updateActiveNav(), 50);
    });
  },

  updated() {
    this.updateActiveNav();
  },

  updateActiveNav() {
    const currentPath = window.location.pathname;
    const links = this.el.querySelectorAll('[data-nav-path]');

    links.forEach(link => {
      const navPath = link.dataset.navPath;
      let isActive = false;

      if (navPath === '/') {
        // News icon: active on homepage, category pages, and post pages
        // Post pages are any path that's not a known section
        const knownSections = ['/hubs', '/hub/', '/shop', '/cart', '/checkout', '/airdrop', '/play', '/pool', '/login', '/members', '/admin'];
        const isKnownSection = knownSections.some(section => currentPath.startsWith(section));
        isActive = currentPath === '/' || currentPath.startsWith('/category/') || !isKnownSection;
      } else if (navPath === '/hubs') {
        // Hubs nav: active for /hubs index AND /hub/:slug detail pages
        isActive = currentPath === '/hubs' || currentPath.startsWith('/hubs/') || currentPath.startsWith('/hub/');
      } else if (navPath === '/shop') {
        // Shop nav: active for /shop, /cart, and /checkout pages
        isActive = currentPath === '/shop' || currentPath.startsWith('/shop/') || currentPath === '/cart' || currentPath.startsWith('/checkout/');
      } else if (navPath === '/play') {
        // Play nav: active for /play and /pool pages
        isActive = currentPath === '/play' || currentPath.startsWith('/play/') || currentPath === '/pool' || currentPath.startsWith('/pool/');
      } else {
        isActive = currentPath === navPath || currentPath.startsWith(navPath + '/');
      }

      if (isActive) {
        link.classList.add('bg-[#CAFC00]');
        link.classList.remove('hover:bg-[#CAFC00]');
      } else {
        link.classList.remove('bg-[#CAFC00]');
        link.classList.add('hover:bg-[#CAFC00]');
      }
    });
  }
};

// Category Navigation Highlight Hook
let CategoryNavHighlight = {
  mounted() {
    this.updateActiveCategory();
    window.addEventListener('phx:navigate', () => {
      setTimeout(() => this.updateActiveCategory(), 50);
    });
  },

  updated() {
    this.updateActiveCategory();
  },

  updateActiveCategory() {
    const currentPath = window.location.pathname;
    const links = this.el.querySelectorAll('[data-category-path]');
    // Get post's category from data attribute (set when on a post page)
    const postCategory = this.el.dataset.postCategory;

    links.forEach(link => {
      const categoryPath = link.dataset.categoryPath;
      const categorySlug = categoryPath.replace('/category/', '');
      // Active if: on category page OR post's category matches this category
      const isActive = currentPath === categoryPath ||
                       currentPath.startsWith(categoryPath + '/') ||
                       (postCategory && postCategory === categorySlug);

      if (isActive) {
        // Thin black underline
        link.classList.remove('border-transparent');
        link.style.borderBottom = '1px solid black';
      } else {
        link.classList.add('border-transparent');
        link.style.borderBottom = '';
      }
    });
  }
};

let CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const textToCopy = this.el.dataset.copyText;
      if (textToCopy) {
        navigator.clipboard.writeText(textToCopy).then(() => {
          // Check for new-style button with separate text/icon elements
          const copyText = this.el.querySelector('.copy-text');
          const copyIcon = this.el.querySelector('.copy-icon');

          if (copyText && copyIcon) {
            // New style: show checkmark icon, change text to "Copied!"
            copyText.textContent = 'Copied!';
            copyIcon.classList.remove('hidden');
            setTimeout(() => {
              copyText.textContent = 'Copy';
              copyIcon.classList.add('hidden');
            }, 2000);
          } else {
            // Legacy style: replace entire content
            const originalHTML = this.el.innerHTML;
            this.el.innerHTML = `<svg class="w-4 h-4 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>`;
            setTimeout(() => {
              this.el.innerHTML = originalHTML;
            }, 1500);
          }
        }).catch(err => {
          console.error('Failed to copy: ', err);
        });
      }
    });
  }
};

// AutoFocus - focuses input when mounted (for mobile search)
let AutoFocus = {
  mounted() {
    // Wait for next paint cycle to ensure element is fully rendered
    requestAnimationFrame(() => {
      this.el.focus();
    });
  }
};

// Hook to clear localStorage after successful claim processing
let ClaimCleanup = {
  mounted() {
    // When this hook mounts on the success message, clear all claims
    AnonymousClaimManager.clearAllClaims();
    console.log('ClaimCleanup: Cleared all pending claims from localStorage');
  }
};

// ScrollToBottom - auto-scrolls chat container when new messages arrive
let ScrollToBottom = {
  mounted() {
    this.scrollToBottom();
    this.observer = new MutationObserver(() => this.scrollToBottom());
    this.observer.observe(this.el, { childList: true, subtree: true });
  },
  updated() {
    this.scrollToBottom();
  },
  destroyed() {
    if (this.observer) this.observer.disconnect();
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  }
};

// ScrollToCenter - scrolls selected child into center of scrollable container
let ScrollToCenter = {
  mounted() {
    requestAnimationFrame(() => {
      const container = this.el;
      const selected = container.querySelector('[data-selected="true"]');
      if (selected) {
        const containerRect = container.getBoundingClientRect();
        const selectedRect = selected.getBoundingClientRect();
        const scrollLeft = container.scrollLeft + (selectedRect.left - containerRect.left) - (containerRect.width / 2) + (selectedRect.width / 2);
        container.scrollLeft = scrollLeft;
      }
    });
  }
};

// Tagline rotator - alternates between two taglines every 2 seconds
let TaglineRotator = {
  mounted() {
    this.taglines = this.el.querySelectorAll('.tagline-text');
    this.currentIndex = 0;
    this.interval = null;

    if (this.taglines.length >= 2) {
      // Start rotation after 2 seconds
      this.interval = setInterval(() => {
        this.rotate();
      }, 2000);
    }
  },

  rotate() {
    const current = this.taglines[this.currentIndex];
    const next = this.taglines[(this.currentIndex + 1) % this.taglines.length];

    // Fade out current
    current.style.opacity = '0';
    current.style.transform = 'translateY(-10px)';

    // Fade in next
    next.style.opacity = '1';
    next.style.transform = 'translateY(0)';

    this.currentIndex = (this.currentIndex + 1) % this.taglines.length;
  },

  destroyed() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
};

let InfiniteScroll = {
  mounted() {
    this.pending = false;
    this.endReached = false;
    this.scrollCheckInterval = null;

    // Detect if element has overflow scrolling
    const hasOverflow = this.el.scrollHeight > this.el.clientHeight;
    const isScrollable = getComputedStyle(this.el).overflowY === 'auto' ||
                         getComputedStyle(this.el).overflowY === 'scroll';
    this.useElementScroll = hasOverflow && isScrollable;

    // Create a sentinel element at the bottom
    this.sentinel = document.createElement('div');
    this.sentinel.style.height = '1px';
    this.el.appendChild(this.sentinel);

    // Create intersection observer with large margin to trigger well before footer
    this.observer = new IntersectionObserver(
      entries => {
        const entry = entries[0];
        if (entry.isIntersecting && !this.pending && !this.endReached) {
          this.loadMore();
        }
      },
      {
        root: this.useElementScroll ? this.el : null, // Use element as root if it's scrollable
        rootMargin: '800px',
        threshold: 0
      }
    );

    this.observer.observe(this.sentinel);

    // Backup scroll event handler for very fast scrolling
    this.handleScroll = () => {
      if (this.pending || this.endReached) return;

      let scrollHeight, scrollTop, clientHeight;

      if (this.useElementScroll) {
        // Element scroll
        scrollHeight = this.el.scrollHeight;
        scrollTop = this.el.scrollTop;
        clientHeight = this.el.clientHeight;
      } else {
        // Window scroll
        scrollHeight = document.documentElement.scrollHeight;
        scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        clientHeight = window.innerHeight;
      }

      // Trigger when within 800px of bottom
      if (scrollHeight - scrollTop - clientHeight < 800) {
        this.loadMore();
      }
    };

    if (this.useElementScroll) {
      this.el.addEventListener('scroll', this.handleScroll, { passive: true });
    } else {
      window.addEventListener('scroll', this.handleScroll, { passive: true });
    }
  },

  loadMore() {
    if (this.pending || this.endReached) return;

    this.pending = true;

    // Determine which event to push - prefer data-event attribute, then check element ID
    let eventName = this.el.dataset.event || 'load-more';
    if (eventName === 'load-more') {
      // Fallback to ID-based event names for backwards compatibility
      if (this.el.id === 'hub-news-stream') {
        eventName = 'load-more-news';
      } else if (this.el.id === 'recent-games-scroll') {
        eventName = 'load-more-games';
      }
    }

    // Use pushEvent callback to reset pending only after server responds
    this.pushEvent(eventName, {}, (reply) => {
      // Check if server indicated no more content
      if (reply && reply.end_reached) {
        this.endReached = true;
        // Stop observing since there's nothing more to load
        if (this.observer) {
          this.observer.disconnect();
        }
        window.removeEventListener('scroll', this.handleScroll);
        return;
      }
      // Small delay after server response to let DOM update
      setTimeout(() => {
        this.pending = false;
      }, 200);
    });
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
    if (this.sentinel && this.sentinel.parentNode) {
      this.sentinel.parentNode.removeChild(this.sentinel);
    }
    if (this.handleScroll) {
      if (this.useElementScroll) {
        this.el.removeEventListener('scroll', this.handleScroll);
      } else {
        window.removeEventListener('scroll', this.handleScroll);
      }
    }
    if (this.scrollCheckInterval) {
      clearInterval(this.scrollCheckInterval);
    }
  }
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: (liveViewName) => {
    // Get pending claims from localStorage to pass to LiveView
    const pendingClaims = AnonymousClaimManager.getPendingClaims();

    // Read wallet from localStorage for session restore on connected mount
    let walletAddress = null;
    try {
      const stored = localStorage.getItem("blockster_wallet");
      if (stored) walletAddress = JSON.parse(stored).address || null;
    } catch (_) {}

    return {
      _csrf_token: csrfToken,
      pending_claims: pendingClaims.length > 0 ? pendingClaims : null,
      wallet_address: walletAddress
    };
  },
  hooks: { TipTapEditor, FeaturedImageUpload, ContentFeaturedImageUpload, HubLogoUpload, HubLogoFormUpload, TwitterWidgets, TagInput, Autocomplete, CopyToClipboard, AutoFocus, ClaimCleanup, InfiniteScroll, TimeTracker, EngagementTracker, PhoneNumberFormatter, BannerUpload, BannerAdminUpload, BannerDrag, TextBlockDrag, TextBlockDragResize, ButtonDrag, AdminControlsDrag, ProductImageUpload, TokenInput, ProductDescriptionEditor, ArtistImageUpload, CoinFlip, BuxBoosterOnchain, CoinFlipSolana, PoolHook, RtSkyscraperWidget, FsSkyscraperWidget, RtChartWidget, RtSquareCompactWidget, RtTickerWidget, FsTickerWidget, RtLeaderboardWidget, FsHeroWidget, CfDemoCycle, CfLiveCycle, DepositBuxInput, VideoWatchTracker, FingerprintHook, ConnectWalletHook, BalanceFetcherHook, WalletTransferHook, BuxPaymentHook, RoguePaymentHook, SolPaymentHook, NotificationToastHook, EventTracker, AirdropDepositHook, AirdropSolanaHook, PriceChart, FsA2CombinedAd, FsKineticAd, MobileNavHighlight, DsMobileNavHighlight, OpenInWallet, DesktopNavHighlight, CategoryNavHighlight, ScrollToBottom, ScrollToCenter, TaglineRotator, SolanaWallet, Web3Auth, Web3AuthWithdraw, Web3AuthExport, PasteFromClipboard, ScrollIntoView: { mounted() { this.el.scrollIntoView({ behavior: "smooth", block: "start" }); } } },
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Header scroll behavior - shrink and hide logo on scroll
// Use a function that can be called on initial load and after LiveView navigation

// Helper to collapse the logo row immediately (no transition)
function collapseLogoRow(instant = false) {
  const logoRow = document.getElementById('header-logo-row');
  const scrollLogo = document.getElementById('scroll-logo');
  const desktopHeader = document.getElementById('desktop-header');

  if (logoRow) {
    // If instant, disable transitions temporarily
    if (instant) {
      logoRow.style.transition = 'none';
      if (scrollLogo) scrollLogo.style.transition = 'none';
      if (desktopHeader) desktopHeader.style.transition = 'none';
    }

    logoRow.style.maxHeight = '0px';
    logoRow.style.opacity = '0';
    logoRow.style.marginBottom = '0';
    logoRow.style.paddingTop = '0';
    logoRow.style.paddingBottom = '0';
    logoRow.style.borderBottom = 'none';

    if (scrollLogo) {
      scrollLogo.style.opacity = '1';
      scrollLogo.style.pointerEvents = 'auto';
    }
    if (desktopHeader) {
      desktopHeader.style.paddingTop = '0.5rem';
    }

    // Re-enable transitions after a frame if instant was used
    if (instant) {
      // Force a reflow to apply the styles immediately
      logoRow.offsetHeight;
      requestAnimationFrame(() => {
        if (logoRow) logoRow.style.transition = '';
        if (scrollLogo) scrollLogo.style.transition = '';
        if (desktopHeader) desktopHeader.style.transition = '';
      });
    }
  } else if (scrollLogo) {
    scrollLogo.style.opacity = '1';
    scrollLogo.style.pointerEvents = 'auto';
  }
}

// Helper to expand the logo row
function expandLogoRow() {
  const logoRow = document.getElementById('header-logo-row');
  const scrollLogo = document.getElementById('scroll-logo');
  const desktopHeader = document.getElementById('desktop-header');

  if (logoRow) {
    logoRow.style.maxHeight = '68px';
    logoRow.style.opacity = '1';
    logoRow.style.marginBottom = '0.5rem';
    logoRow.style.paddingTop = '0.125rem';
    logoRow.style.paddingBottom = '1rem';
    logoRow.style.borderBottom = '1px solid #e5e7eb';
  }
  if (scrollLogo) {
    scrollLogo.style.opacity = '0';
    scrollLogo.style.pointerEvents = 'none';
  }
  if (desktopHeader) {
    desktopHeader.style.paddingTop = '1.5rem';
  }
}

function initHeaderScroll() {
  const logoRow = document.getElementById('header-logo-row');

  // Skip if elements don't exist
  if (!logoRow) return;

  function handleScroll() {
    const scrollY = window.scrollY;

    if (scrollY > 50) {
      collapseLogoRow();
    } else {
      expandLogoRow();
    }
  }

  // Remove any existing scroll listener to prevent duplicates
  if (window._headerScrollHandler) {
    window.removeEventListener('scroll', window._headerScrollHandler);
  }

  // Store reference to handler so we can remove it later
  window._headerScrollHandler = function() {
    window.requestAnimationFrame(handleScroll);
  };

  window.addEventListener('scroll', window._headerScrollHandler, { passive: true });

  // Run once immediately to set correct initial state
  if (window.scrollY > 50) {
    collapseLogoRow(true);
  } else {
    expandLogoRow();
  }
}

// Initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', initHeaderScroll);

// Re-initialize header scroll handler after LiveView navigation
window.addEventListener('phx:page-loading-stop', function() {
  initHeaderScroll();
});

// Dropdown toggle functionality
document.addEventListener('DOMContentLoaded', function() {
  // Close dropdown when clicking outside
  document.addEventListener('click', function(event) {
    const desktopDropdown = document.getElementById('desktop-dropdown-menu');
    const mobileDropdown = document.getElementById('mobile-dropdown-menu');
    const desktopButton = document.getElementById('desktop-user-button');
    const mobileButton = document.getElementById('mobile-user-button');

    // Close desktop dropdown if clicking outside
    if (desktopDropdown && !event.target.closest('#desktop-user-dropdown')) {
      desktopDropdown.classList.add('hidden');
    }

    // Close mobile dropdown if clicking outside
    if (mobileDropdown && !event.target.closest('#mobile-user-dropdown')) {
      mobileDropdown.classList.add('hidden');
    }
  });

  // Smooth scrolling for anchor links using event delegation
  document.addEventListener('click', function(e) {
    const anchor = e.target.closest('a[href^="#"]');
    if (!anchor) return;

    const href = anchor.getAttribute('href');
    // Skip if it's just "#" or empty
    if (!href || href === '#') return;

    const targetElement = document.querySelector(href);
    if (targetElement) {
      e.preventDefault();
      const headerOffset = 100; // Offset for fixed header
      const elementPosition = targetElement.getBoundingClientRect().top;
      const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

      window.scrollTo({
        top: offsetPosition,
        behavior: 'smooth'
      });
    }
  });
});

// Global function to toggle dropdowns
window.toggleDropdown = function(dropdownId) {
  const dropdown = document.getElementById(dropdownId);
  if (dropdown) {
    dropdown.classList.toggle('hidden');
  }
};

// Global function to handle wallet disconnect (legacy — prefer phx-click="disconnect_wallet")
window.handleWalletDisconnect = async function() {
  try {
    // Clear Solana wallet localStorage
    localStorage.removeItem('blockster_wallet');
    // Clear legacy EVM localStorage
    localStorage.removeItem('walletAddress');
    localStorage.removeItem('smartAccountAddress');

    // Call backend session clear
    const csrf = document.querySelector("meta[name='csrf-token']")?.content;
    if (csrf) {
      await fetch('/api/auth/session', {
        method: 'DELETE',
        headers: { 'x-csrf-token': csrf }
      });
    }

    // Also try legacy logout endpoint
    await fetch('/api/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }).catch(() => {});

    // Redirect to homepage
    window.location.href = '/';
  } catch (error) {
    console.error('Disconnect error:', error);
    window.location.href = '/';
  }
};

// Open external URLs in a new tab (from notification clicks)
window.addEventListener("phx:open_external_url", (e) => {
  if (e.detail && e.detail.url) {
    window.open(e.detail.url, "_blank", "noopener,noreferrer");
  }
});

// Event listener to clear tag input
window.addEventListener("phx:clear-tag-input", () => {
  const tagInput = document.getElementById("tag-input");
  if (tagInput) {
    tagInput.value = "";
  }
});

// Initialize fingerprint hook globally (mount once on page load)
document.addEventListener('DOMContentLoaded', () => {
  window.FingerprintHookInstance = Object.create(FingerprintHook);
  window.FingerprintHookInstance.mounted();
});

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
