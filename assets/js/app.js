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
import { HubLogoUpload, HubLogoFormUpload } from "./hub_logo_upload.js";
import { TwitterWidgets } from "./twitter_widgets.js";
import { HomeHooks, ModalHooks, DropdownHooks, SearchHooks, ThirdwebLogin, ThirdwebWallet } from "./home_hooks.js";
import { TimeTracker } from "./time_tracker.js";
import { EngagementTracker } from "./engagement_tracker.js";
import { PhoneNumberFormatter } from "./phone_number_formatter.js";
import { BannerUpload } from "./banner_upload.js";
import { BannerDrag } from "./banner_drag.js";
import { TextBlockDrag, TextBlockDragResize, ButtonDrag, AdminControlsDrag } from "./text_block_drag.js";
import { ProductImageUpload } from "./product_image_upload.js";
import { ProductDescriptionEditor } from "./product_description_editor.js";
import { ArtistImageUpload } from "./artist_image_upload.js";
import { CoinFlip } from "./coin_flip.js";
import { BuxBoosterOnchain } from "./bux_booster_onchain.js";
import { VideoWatchTracker } from "./video_watch_tracker.js";
import { AnonymousClaimManager } from "./anonymous_claim_manager.js";
import { FingerprintHook } from "./fingerprint_hook.js";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
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

let CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const textToCopy = this.el.dataset.copyText;
      if (textToCopy) {
        navigator.clipboard.writeText(textToCopy).then(() => {
          // Show brief feedback
          const originalHTML = this.el.innerHTML;
          this.el.innerHTML = `<svg class="w-4 h-4 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>`;
          setTimeout(() => {
            this.el.innerHTML = originalHTML;
          }, 1500);
        }).catch(err => {
          console.error('Failed to copy: ', err);
        });
      }
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

    // Create intersection observer with larger margin
    this.observer = new IntersectionObserver(
      entries => {
        const entry = entries[0];
        if (entry.isIntersecting && !this.pending && !this.endReached) {
          this.loadMore();
        }
      },
      {
        root: this.useElementScroll ? this.el : null, // Use element as root if it's scrollable
        rootMargin: '200px',
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

      // Trigger when within 200px of bottom
      if (scrollHeight - scrollTop - clientHeight < 200) {
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

    // Determine which event to push based on element ID
    let eventName = 'load-more';
    if (this.el.id === 'hub-news-stream') {
      eventName = 'load-more-news';
    } else if (this.el.id === 'recent-games-scroll') {
      eventName = 'load-more-games';
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

    return {
      _csrf_token: csrfToken,
      pending_claims: pendingClaims.length > 0 ? pendingClaims : null
    };
  },
  hooks: { TipTapEditor, FeaturedImageUpload, HubLogoUpload, HubLogoFormUpload, TwitterWidgets, HomeHooks, ModalHooks, DropdownHooks, SearchHooks, ThirdwebLogin, ThirdwebWallet, TagInput, Autocomplete, CopyToClipboard, ClaimCleanup, InfiniteScroll, TimeTracker, EngagementTracker, PhoneNumberFormatter, BannerUpload, BannerDrag, TextBlockDrag, TextBlockDragResize, ButtonDrag, AdminControlsDrag, ProductImageUpload, TokenInput, ProductDescriptionEditor, ArtistImageUpload, CoinFlip, BuxBoosterOnchain, DepositBuxInput, VideoWatchTracker, FingerprintHook },
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

// Global function to handle wallet disconnect
window.handleWalletDisconnect = async function() {
  try {
    // Call backend logout endpoint
    await fetch('/api/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });

    // Clear localStorage wallet data
    localStorage.removeItem('walletAddress');
    localStorage.removeItem('smartAccountAddress');

    // Try to disconnect wallets - check both hooks
    if (window.ThirdwebWalletHook && typeof window.ThirdwebWalletHook.handleDisconnect === 'function') {
      await window.ThirdwebWalletHook.handleDisconnect();
    } else if (window.ThirdwebLoginHook && typeof window.ThirdwebLoginHook.handleDisconnect === 'function') {
      await window.ThirdwebLoginHook.handleDisconnect();
    }

    // Redirect to homepage
    window.location.href = '/';
  } catch (error) {
    console.error('Disconnect error:', error);
    // Still redirect to homepage even if there's an error
    window.location.href = '/';
  }
};

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
