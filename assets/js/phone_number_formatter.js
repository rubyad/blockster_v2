// Real-time phone number formatting as user types

export const PhoneNumberFormatter = {
  mounted() {
    this.input = this.el;

    // Add input listener for formatting
    this.input.addEventListener('input', (e) => {
      this.formatPhoneNumber(e);
    });

    // Add paste listener
    this.input.addEventListener('paste', (e) => {
      setTimeout(() => this.formatPhoneNumber(e), 10);
    });
  },

  formatPhoneNumber(e) {
    let value = this.input.value;

    // Remove all non-digit characters except +
    let cleaned = value.replace(/[^\d+]/g, '');

    // If starts with +, preserve it and format intelligently
    if (cleaned.startsWith('+')) {
      // Just add space after country code if user is typing
      // Keep it simple - server will validate
      return;
    }

    // If starts with 1 and has more digits, format as US: +1 (XXX) XXX-XXXX
    if (cleaned.startsWith('1') && cleaned.length > 1) {
      let digits = cleaned.substring(1); // Remove the leading 1
      let formatted = '+1';

      if (digits.length > 6) {
        formatted = `+1 (${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6, 10)}`;
      } else if (digits.length > 3) {
        formatted = `+1 (${digits.slice(0, 3)}) ${digits.slice(3)}`;
      } else if (digits.length > 0) {
        formatted = `+1 ${digits}`;
      }

      this.input.value = formatted;
      return;
    }

    // For other numbers starting with digits (not 1), add + and space
    if (cleaned.length > 0) {
      this.input.value = '+' + cleaned;
    }
  },

  destroyed() {
    // Cleanup if needed
  }
};
