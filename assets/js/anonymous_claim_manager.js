/**
 * AnonymousClaimManager
 *
 * Manages localStorage claim data for anonymous users.
 * Handles storing, retrieving, and cleaning up pending reward claims.
 */
export const AnonymousClaimManager = {
  /**
   * Store a claim in localStorage
   * @param {string|number} postId - Post ID
   * @param {string} type - 'read' or 'video'
   * @param {object} metrics - Engagement metrics
   * @param {number} earnedAmount - BUX earned
   */
  storeClaim(postId, type, metrics, earnedAmount) {
    const key = `pending_claim_${type}_${postId}`;
    const claimData = {
      postId,
      type,
      metrics,
      earnedAmount,
      timestamp: Date.now(),
      expiresAt: Date.now() + (30 * 60 * 1000) // 30 minutes
    };

    try {
      localStorage.setItem(key, JSON.stringify(claimData));
      console.log(`AnonymousClaimManager: Stored ${type} claim for post ${postId}: ${earnedAmount} BUX`);
      return true;
    } catch (e) {
      console.error(`AnonymousClaimManager: Failed to store claim:`, e);
      return false;
    }
  },

  /**
   * Get all pending claims (not expired)
   * @returns {Array} Array of claim objects
   */
  getPendingClaims() {
    const claims = [];
    const now = Date.now();

    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);

        if (key && key.startsWith('pending_claim_')) {
          try {
            const data = JSON.parse(localStorage.getItem(key));

            // Check expiry
            if (data.expiresAt > now) {
              claims.push(data);
            } else {
              // Clean up expired claim
              localStorage.removeItem(key);
              console.log(`AnonymousClaimManager: Removed expired claim for post ${data.postId}`);
            }
          } catch (parseError) {
            // Invalid JSON, remove it
            localStorage.removeItem(key);
            console.warn(`AnonymousClaimManager: Removed invalid claim data:`, parseError);
          }
        }
      }
    } catch (e) {
      console.error(`AnonymousClaimManager: Error getting pending claims:`, e);
    }

    console.log(`AnonymousClaimManager: Found ${claims.length} pending claims`);
    return claims;
  },

  /**
   * Get total BUX from all pending claims
   * @returns {number} Total BUX amount
   */
  getTotalPendingBux() {
    const claims = this.getPendingClaims();
    return claims.reduce((total, claim) => total + (claim.earnedAmount || 0), 0);
  },

  /**
   * Clear a specific claim after processing
   * @param {string|number} postId - Post ID
   * @param {string} type - 'read' or 'video'
   */
  clearClaim(postId, type) {
    const key = `pending_claim_${type}_${postId}`;
    try {
      localStorage.removeItem(key);
      console.log(`AnonymousClaimManager: Cleared ${type} claim for post ${postId}`);
      return true;
    } catch (e) {
      console.error(`AnonymousClaimManager: Failed to clear claim:`, e);
      return false;
    }
  },

  /**
   * Clear all pending claims
   */
  clearAllClaims() {
    const keys = [];

    try {
      // Collect all claim keys first
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith('pending_claim_')) {
          keys.push(key);
        }
      }

      // Remove them
      keys.forEach(key => {
        try {
          localStorage.removeItem(key);
        } catch (e) {
          console.warn(`AnonymousClaimManager: Failed to remove ${key}:`, e);
        }
      });

      console.log(`AnonymousClaimManager: Cleared ${keys.length} claims`);
      return keys.length;
    } catch (e) {
      console.error(`AnonymousClaimManager: Error clearing all claims:`, e);
      return 0;
    }
  },

  /**
   * Check if there are any pending claims
   * @returns {boolean}
   */
  hasPendingClaims() {
    return this.getPendingClaims().length > 0;
  },

  /**
   * Clean up expired claims (can be called periodically)
   */
  cleanupExpired() {
    const now = Date.now();
    let cleanedCount = 0;

    try {
      for (let i = localStorage.length - 1; i >= 0; i--) {
        const key = localStorage.key(i);

        if (key && key.startsWith('pending_claim_')) {
          try {
            const data = JSON.parse(localStorage.getItem(key));
            if (data.expiresAt <= now) {
              localStorage.removeItem(key);
              cleanedCount++;
            }
          } catch (e) {
            // Invalid data, remove it
            localStorage.removeItem(key);
            cleanedCount++;
          }
        }
      }

      if (cleanedCount > 0) {
        console.log(`AnonymousClaimManager: Cleaned up ${cleanedCount} expired claims`);
      }
    } catch (e) {
      console.error(`AnonymousClaimManager: Error during cleanup:`, e);
    }

    return cleanedCount;
  }
};
