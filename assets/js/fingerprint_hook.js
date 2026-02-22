import FingerprintJS from '@fingerprintjs/fingerprintjs-pro';

export const FingerprintHook = {
  async mounted() {
    console.log('FingerprintHook mounted');

    // Store this hook instance globally so ThirdwebLogin can access it
    window.FingerprintHookInstance = this;

    // Check if we already have a fingerprint in localStorage from a previous session
    const cachedFingerprint = localStorage.getItem('fp_visitor_id');
    const cachedConfidence = localStorage.getItem('fp_confidence');

    if (cachedFingerprint) {
      console.log('Using cached fingerprint:', cachedFingerprint);
      window.fingerprintData = {
        visitorId: cachedFingerprint,
        confidence: parseFloat(cachedConfidence) || 0.99,
        cached: true
      };
    } else {
      console.log('No cached fingerprint, will fetch on signup');
    }
  },

  /**
   * Get fingerprint only when needed (on signup attempt)
   * This minimizes API calls and costs
   */
  async getFingerprint() {
    try {
      console.log('Fetching fresh fingerprint from FingerprintJS...');

      if (!window.FINGERPRINTJS_PUBLIC_KEY) {
        console.log('FingerprintJS public key not configured, using dev bypass');
        const devData = { visitorId: 'dev-local-bypass', confidence: 0.99, cached: false };
        window.fingerprintData = devData;
        return devData;
      }

      // Initialize FingerprintJS Pro with public API key
      const fpPromise = FingerprintJS.load({
        apiKey: window.FINGERPRINTJS_PUBLIC_KEY
        // Using default endpoint - custom subdomain (fp.blockster.com) not configured
      });

      const fp = await fpPromise;

      // Get visitor identifier
      const result = await fp.get({
        extendedResult: true  // Get confidence score and additional signals
      });

      console.log('Fingerprint result:', result);

      const fingerprintData = {
        visitorId: result.visitorId,
        confidence: result.confidence.score,
        requestId: result.requestId,
        cached: false
      };

      // Cache for future use (avoid repeat API calls)
      localStorage.setItem('fp_visitor_id', result.visitorId);
      localStorage.setItem('fp_confidence', result.confidence.score.toString());
      localStorage.setItem('fp_request_id', result.requestId);

      window.fingerprintData = fingerprintData;

      return fingerprintData;
    } catch (error) {
      console.error('Error getting fingerprint:', error);
      // Graceful fallback - don't block signup if fingerprint service fails
      // Server-side handles validation; client sends a fallback ID
      const fallbackData = { visitorId: 'fp-unavailable', confidence: 0, cached: false };
      window.fingerprintData = fallbackData;
      return fallbackData;
    }
  }
};
