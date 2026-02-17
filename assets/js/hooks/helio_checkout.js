/**
 * HelioCheckoutHook - Embed Helio checkout widget for card/crypto payment
 *
 * Loads the Helio SDK via CDN, renders the checkout widget when a charge
 * token is received from the server, and reports payment results back
 * to the LiveView via pushEvent.
 */

export const HelioCheckoutHook = {
  mounted() {
    this.chargeToken = null;

    this.handleEvent("helio_charge_created", ({ charge_id }) => {
      this.chargeToken = charge_id;
      this.renderWidget();
    });
  },

  renderWidget() {
    if (!this.chargeToken) return;

    // Load Helio SDK script if not already loaded
    if (!window.HelioCheckout) {
      const script = document.createElement('script');
      script.src = 'https://cdn.hel.io/checkout.js';
      script.onload = () => this.initCheckout();
      script.onerror = () => {
        console.error("[HelioCheckout] Failed to load Helio SDK");
        this.pushEvent("helio_payment_error", { error: "Failed to load payment widget. Please try again." });
      };
      document.head.appendChild(script);
    } else {
      this.initCheckout();
    }
  },

  initCheckout() {
    const container = this.el.querySelector('#helio-widget-container') || this.el;

    // Clear any existing widget
    container.innerHTML = '';

    try {
      new window.HelioCheckout({
        chargeToken: this.chargeToken,
        display: "inline",
        theme: { themeMode: "light" },
        primaryColor: "#CAFC00",
        neutralColor: "#141414",
        showPayWithCard: true,
        onSuccess: (event) => {
          console.log("[HelioCheckout] Payment success:", event);
          this.pushEvent("helio_payment_success", {
            transaction_id: event.transactionId || (event.transaction && event.transaction.id) || event.id
          });
        },
        onError: (error) => {
          console.error("[HelioCheckout] Payment error:", error);
          this.pushEvent("helio_payment_error", {
            error: (error && error.message) || "Payment failed"
          });
        },
        onCancel: () => {
          console.log("[HelioCheckout] Payment cancelled");
          this.pushEvent("helio_payment_cancelled", {});
        },
        additionalJSON: {
          order_id: this.el.dataset.orderId,
          order_number: this.el.dataset.orderNumber
        }
      }).render(container);
    } catch (error) {
      console.error("[HelioCheckout] Widget init error:", error);
      this.pushEvent("helio_payment_error", {
        error: "Failed to initialize payment widget. Please try again."
      });
    }
  }
};
