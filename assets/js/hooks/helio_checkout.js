/**
 * HelioCheckoutHook - Embed Helio (MoonPay Commerce) checkout widget
 *
 * Loads the Helio SDK via CDN, renders the checkout widget with the
 * paylink ID and dynamic amount, and reports payment results back
 * to the LiveView via pushEvent.
 */

export const HelioCheckoutHook = {
  mounted() {
    this.handleEvent("helio_render_widget", ({ paylink_id, amount, order_id, order_number }) => {
      this.paylinkId = paylink_id;
      this.amount = amount;
      this.orderId = order_id;
      this.orderNumber = order_number;
      this.renderWidget();
    });
  },

  renderWidget() {
    if (!this.paylinkId) return;

    // Load Helio SDK script if not already loaded
    if (!window.helioCheckout) {
      const script = document.createElement('script');
      script.type = 'module';
      script.crossOrigin = 'anonymous';
      script.src = 'https://embed.hel.io/assets/index-v1.js';
      script.onload = () => {
        // Module scripts may need a tick to register globals
        setTimeout(() => this.initCheckout(), 100);
      };
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
    const container = this.el.querySelector('#helio-widget-container');
    if (!container) {
      console.error("[HelioCheckout] Widget container not found");
      this.pushEvent("helio_payment_error", { error: "Widget container not found. Please try again." });
      return;
    }

    // Clear any existing widget
    container.innerHTML = '';

    try {
      if (window.helioCheckout) {
        window.helioCheckout(container, {
          paylinkId: this.paylinkId,
          amount: this.amount,
          display: "inline",
          theme: { themeMode: "light" },
          primaryColor: "#141414",
          neutralColor: "#515B70",
          showPayWithCard: true,
          additionalJSON: JSON.stringify({
            order_id: this.orderId,
            order_number: this.orderNumber
          }),
          onSuccess: (event) => {
            console.log("[HelioCheckout] Payment success:", JSON.stringify(event));
            this.pushEvent("helio_payment_success", {
              transaction_id: event?.transactionId || event?.transaction?.id || event?.id || event?.transaction || null
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
          }
        });
      } else {
        console.error("[HelioCheckout] Helio SDK not available after loading");
        this.pushEvent("helio_payment_error", { error: "Payment SDK not available. Please try again." });
      }
    } catch (error) {
      console.error("[HelioCheckout] Widget init error:", error);
      this.pushEvent("helio_payment_error", {
        error: "Failed to initialize payment widget. Please try again."
      });
    }
  }
};
