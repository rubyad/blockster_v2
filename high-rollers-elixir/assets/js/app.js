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

// Import ethers.js for wallet interactions and expose globally
import * as ethers from "../vendor/ethers.min.js"
window.ethers = ethers

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/high_rollers"
import topbar from "../vendor/topbar"

// Import LiveView hooks for High Rollers NFT
import WalletHook from "./hooks/wallet_hook"
import MintHook from "./hooks/mint_hook"
import InfiniteScrollHook from "./hooks/infinite_scroll_hook"
import CopyToClipboardHook from "./hooks/copy_to_clipboard_hook"
import TimeRewardHook from "./hooks/time_reward_hook"
import GlobalTimeRewardHook from "./hooks/global_time_reward_hook"
import GlobalTimeReward24hHook from "./hooks/global_time_reward_24h_hook"
import CountdownHook from "./hooks/countdown_hook"
import AffiliateWithdrawHook from "./hooks/affiliate_withdraw_hook"
import AffiliateBalanceHook from "./hooks/affiliate_balance_hook"

// Combine all hooks
// Note: Hook names must match exactly what's used in phx-hook="..." attributes
const hooks = {
  ...colocatedHooks,
  WalletHook,
  MintHook,
  InfiniteScroll: InfiniteScrollHook,
  CopyToClipboard: CopyToClipboardHook,
  TimeRewardHook,
  GlobalTimeRewardHook,
  GlobalTimeReward24hHook,
  CountdownHook,
  AffiliateWithdraw: AffiliateWithdrawHook,
  AffiliateBalance: AffiliateBalanceHook
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Global event listener for wallet connection requests from any LiveView
window.addEventListener("phx:open_wallet_modal", () => {
  // Show the wallet modal instead of directly connecting
  const modal = document.getElementById('wallet-modal')
  if (modal) {
    modal.classList.remove('hidden')
    modal.classList.add('flex')
  } else {
    console.error('[App] Wallet modal not found')
  }
})

// Hero "Mint Now" button - navigate to mint tab and scroll to mint button
function scrollToMintSection() {
  const mintBtn = document.getElementById('mint-btn')
  const nav = document.querySelector('nav.sticky')
  if (mintBtn) {
    // Calculate position to scroll so tabs are at top of viewport
    const navHeight = nav ? nav.offsetHeight : 56
    const elementTop = mintBtn.getBoundingClientRect().top + window.scrollY
    const offsetPosition = elementTop - navHeight - 32 // 32px padding

    window.scrollTo({
      top: offsetPosition,
      behavior: 'smooth'
    })
  }
}

function setupHeroMintButton() {
  const heroMintBtn = document.getElementById('hero-mint-btn')
  if (heroMintBtn && !heroMintBtn._heroMintListenerAttached) {
    heroMintBtn._heroMintListenerAttached = true
    heroMintBtn.addEventListener('click', () => {
      // Check if we're already on the mint page (/ or /mint)
      if (window.location.pathname === '/' || window.location.pathname === '/mint') {
        scrollToMintSection()
      } else {
        // Set flag then click the Mint tab link to use LiveView navigation
        window._scrollToMintBtn = true
        const mintTabLink = document.querySelector('nav a[href="/"]')
        if (mintTabLink) {
          mintTabLink.click()
        }
      }
    })
  }
}

// Scroll to mint button after LiveView navigation
function checkScrollToMintBtn() {
  if (window._scrollToMintBtn && (window.location.pathname === '/' || window.location.pathname === '/mint')) {
    window._scrollToMintBtn = false
    // Small delay to ensure LiveView has mounted
    setTimeout(scrollToMintSection, 100)
  }
}

// Setup on initial load
document.addEventListener("DOMContentLoaded", setupHeroMintButton)

// Update hero special remaining count from mint page data
function updateHeroSpecialRemaining() {
  const mintContainer = document.getElementById('mint-container')
  const heroSpecialRemaining = document.getElementById('hero-special-remaining')

  // If we're on mint page, read and cache the value
  if (mintContainer) {
    const specialRemaining = mintContainer.dataset.specialRemaining
    if (specialRemaining) {
      window._specialRemaining = specialRemaining
    }
  }

  // Always update the hero if we have a cached value
  if (heroSpecialRemaining && window._specialRemaining) {
    heroSpecialRemaining.textContent = window._specialRemaining
  }
}

// Re-setup after LiveView navigation
window.addEventListener("phx:page-loading-stop", () => {
  setupHeroMintButton()
  checkScrollToMintBtn()
  updateHeroSpecialRemaining()
})

// Also run on initial load
document.addEventListener("DOMContentLoaded", updateHeroSpecialRemaining)

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

