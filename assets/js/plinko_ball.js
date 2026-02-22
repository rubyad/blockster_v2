/**
 * PlinkoBall Hook - Plinko ball drop animation
 *
 * Physics-based simulation: gravity pulls the ball down, pegs deflect it
 * left or right with elastic bounce. The ball accelerates, hits a peg,
 * bounces off at an angle, arcs through the air, hits the next peg, etc.
 * Real ballistic trajectories between pegs — no splines or keyframes.
 *
 * Ball positioning uses CSS transform (not cx/cy attributes) so LiveView
 * DOM patches mid-animation can't cause visual glitches.
 */

// Base position matching server-rendered cx/cy on #plinko-ball
const BASE_X = 200;
const BASE_Y = 10;

export const PlinkoBall = {
  mounted() {
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
    this.trails = [];
    this.effects = [];
    this.isAnimating = false;
    this._ballPos = null;
    this._hitSlot = null; // { position, brightColor }

    this.handleEvent("drop_ball", ({ ball_path, landing_position, rows }) => {
      this.animateDrop(ball_path, landing_position, rows);
    });
    this.handleEvent("reset_ball", () => this.resetBall());
  },

  updated() {
    // Ball is inside phx-update="ignore" so it survives morphdom untouched.
    // But pegs/slots DO get re-rendered when rows change, so re-query them.
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');

    // Update ball radius when rows change (morphdom can't do it for us)
    if (this.ball) {
      const numSlots = this.slots.length;
      const rows = numSlots > 0 ? numSlots - 1 : 8;
      const radius = rows === 8 ? 9 : rows === 12 ? 7 : 6;
      this.ball.setAttribute('r', radius);
    }

    // Re-apply slot highlight after LiveView patch (morphdom resets fill attrs)
    if (this._hitSlot && this.slots[this._hitSlot.position]) {
      const slot = this.slots[this._hitSlot.position];
      slot.setAttribute('fill', this._hitSlot.brightColor);
      slot.classList.add('plinko-slot-hit');
    }
  },

  // ============ Ball Positioning ============

  /**
   * Position the ball via CSS transform instead of cx/cy attributes.
   * Server renders cx="200" cy="10" — morphdom sees no diff, leaves them alone.
   * The transform is client-only, invisible to morphdom.
   */
  setBallPosition(x, y) {
    this._ballPos = { x, y };
    if (this.ball) {
      this.ball.style.transform = `translate(${x - BASE_X}px, ${y - BASE_Y}px)`;
    }
  },

  clearBallTransform() {
    this._ballPos = null;
    if (this.ball) {
      this.ball.style.transform = '';
    }
  },

  // ============ Layout ============

  getLayout(rows) {
    const viewHeight = rows === 8 ? 340 : rows === 12 ? 460 : 580;
    const topMargin = 30;
    const bottomMargin = 50;
    const boardHeight = viewHeight - topMargin - bottomMargin;
    const rowHeight = boardHeight / rows;
    const spacing = 380 / (rows + 1);
    return { viewHeight, topMargin, bottomMargin, boardHeight, rowHeight, spacing };
  },

  getPegPosition(row, col, rows) {
    const { topMargin, rowHeight, spacing } = this.getLayout(rows);
    const numPegsInRow = row + 1;
    const rowWidth = (numPegsInRow - 1) * spacing;
    return {
      x: 200 - rowWidth / 2 + col * spacing,
      y: topMargin + row * rowHeight
    };
  },

  getSlotPosition(index, rows) {
    const { viewHeight } = this.getLayout(rows);
    const numSlots = rows + 1;
    const slotWidth = 380 / numSlots;
    return {
      x: 200 - (numSlots - 1) * slotWidth / 2 + index * slotWidth,
      y: viewHeight - 25
    };
  },

  getPegIndex(row, col) {
    let index = 0;
    for (let r = 0; r < row; r++) index += (r + 1);
    return index + col;
  },

  // ============ Physics Trajectory ============

  /**
   * Compute a ballistic arc from `start` to `end` under gravity.
   * Returns an array of {x, y, t} samples.
   *
   * We pick a flight time that looks natural, then solve for the
   * initial velocity needed to hit the target in that time.
   *   vx = (end.x - start.x) / T
   *   vy = (end.y - start.y - 0.5 * g * T^2) / T
   * Position at time t:
   *   x(t) = start.x + vx * t
   *   y(t) = start.y + vy * t + 0.5 * g * t^2
   */
  ballisticArc(start, end, gravity, flightTime, sampleCount) {
    const T = flightTime;
    const vx = (end.x - start.x) / T;
    const vy = (end.y - start.y - 0.5 * gravity * T * T) / T;

    const samples = [];
    for (let i = 0; i <= sampleCount; i++) {
      const t = (i / sampleCount) * T;
      samples.push({
        x: start.x + vx * t,
        y: start.y + vy * t + 0.5 * gravity * t * t,
        t
      });
    }
    return samples;
  },

  /**
   * Build the full trajectory: a sequence of ballistic arcs.
   *
   * Ball drops from top → first peg (pure gravity drop).
   * At each peg, it deflects left or right and arcs to the next peg.
   * After the last peg, it arcs down to just above the landing slot.
   *
   * Each frame carries a cumulative physical time stamp so the animation
   * can interpolate on real time rather than frame index — preserving
   * natural gravity acceleration throughout.
   *
   * Returns { frames, pegHitFrames, totalTime }
   */
  buildTrajectory(ballPath, rows) {
    const { rowHeight, spacing } = this.getLayout(rows);
    const startPos = { x: 200, y: 10 };
    const gravity = 1800; // px/s² — tuned to feel weighty
    const samplesPerArc = 30;

    const frames = []; // { x, y, physTime }
    const pegHitFrames = []; // { frameIdx, row, col }
    let cumTime = 0;

    let col = 0;

    // Arc 0: drop from start to first peg
    const firstPeg = this.getPegPosition(0, 0, rows);
    const dropDist = firstPeg.y - startPos.y;
    const dropTime = Math.sqrt(2 * Math.abs(dropDist) / gravity);
    const dropArc = this.ballisticArc(startPos, firstPeg, gravity, dropTime, samplesPerArc);

    // Add drop arc frames with cumulative time stamps (all samples including last)
    for (let j = 0; j < dropArc.length; j++) {
      frames.push({ x: dropArc[j].x, y: dropArc[j].y, physTime: cumTime + dropArc[j].t });
    }
    cumTime += dropTime;

    // The last sample of the arc IS the peg position — no separate frame needed
    pegHitFrames.push({ frameIdx: frames.length - 1, row: 0, col: 0 });

    // Arcs between pegs
    for (let i = 0; i < ballPath.length; i++) {
      const pegCol = col;
      const pegPos = this.getPegPosition(i, pegCol, rows);

      let nextPos;
      if (i < ballPath.length - 1) {
        const nextCol = col + ballPath[i];
        nextPos = this.getPegPosition(i + 1, nextCol, rows);
      } else {
        const finalCol = col + ballPath[i];
        const slotPos = this.getSlotPosition(finalCol, rows);
        nextPos = { x: slotPos.x, y: slotPos.y - 25 };
      }

      const dy = Math.abs(nextPos.y - pegPos.y);
      const flightTime = Math.max(Math.sqrt(2 * dy / gravity) * 1.3, 0.12);

      // Arc starts from exact peg position — no offset discontinuity.
      // The 1.3x flight time naturally gives upward initial velocity,
      // creating a bounce arc without needing a positional offset.
      const arc = this.ballisticArc(pegPos, nextPos, gravity, flightTime, samplesPerArc);

      // Add arc frames with cumulative time (skip first = peg already added,
      // include last = it IS the next position, no separate frame needed)
      for (let j = 1; j <= samplesPerArc; j++) {
        frames.push({ x: arc[j].x, y: arc[j].y, physTime: cumTime + arc[j].t });
      }
      cumTime += flightTime;

      if (i < ballPath.length - 1) {
        pegHitFrames.push({ frameIdx: frames.length - 1, row: i + 1, col: col + ballPath[i] });
      }

      col += ballPath[i];
    }

    return { frames, pegHitFrames, totalTime: cumTime };
  },

  // ============ Main Animation ============

  async animateDrop(ballPath, landingPosition, rows) {
    this.clearEffects();
    this.isAnimating = true;
    this.setBallPosition(200, 10);

    // Short CSS transition acts as a jank absorber: the compositor thread
    // interpolates between positions independently of JavaScript. If the
    // main thread blocks (Thirdweb SDK), the compositor keeps the ball
    // moving smoothly toward its last target instead of freezing.
    if (this.ball) {
      this.ball.style.transition = 'transform 20ms linear';
      this.ball.style.willChange = 'transform';
    }

    const { frames, pegHitFrames, totalTime } = this.buildTrajectory(ballPath, rows);

    // Total duration scales with row count
    const duration = rows === 8 ? 2800 : rows === 12 ? 3400 : 4000;

    await this.animateFrames(frames, pegHitFrames, rows, duration, totalTime);

    // Bouncy landing into slot
    const col = ballPath.reduce((c, dir) => c + dir, 0);
    const slotPos = this.getSlotPosition(col, rows);
    const approachPos = { x: slotPos.x, y: slotPos.y - 25 };
    // Remove jank absorber for landing (bounce easing needs precise control)
    if (this.ball) {
      this.ball.style.transition = '';
      this.ball.style.willChange = '';
    }

    await this.animateLanding(approachPos, slotPos, landingPosition);

    this.isAnimating = false;
    this.pushEvent("ball_landed", {});
  },

  /**
   * Find the frame pair surrounding a given physical time via binary search,
   * then lerp between them. This preserves natural gravity speed — the ball
   * genuinely accelerates on downward arcs and decelerates on upward ones.
   */
  sampleAtPhysTime(frames, targetTime) {
    let lo = 0, hi = frames.length - 1;
    while (lo < hi - 1) {
      const mid = (lo + hi) >> 1;
      if (frames[mid].physTime <= targetTime) lo = mid;
      else hi = mid;
    }
    const segDur = frames[hi].physTime - frames[lo].physTime;
    const frac = segDur > 0 ? (targetTime - frames[lo].physTime) / segDur : 0;
    return {
      x: frames[lo].x + (frames[hi].x - frames[lo].x) * frac,
      y: frames[lo].y + (frames[hi].y - frames[lo].y) * frac,
      frameIdx: lo
    };
  },

  animateFrames(frames, pegHitFrames, rows, duration, totalPhysTime) {
    return new Promise(resolve => {
      const startTime = performance.now();
      const flushed = new Set();

      const animate = (now) => {
        const elapsed = now - startTime;
        const p = Math.min(elapsed / duration, 1);

        // Map screen time to physical time
        const physTime = p * totalPhysTime;
        const { x, y, frameIdx } = this.sampleAtPhysTime(frames, physTime);

        // Position ball via CSS transform (immune to LiveView DOM patches)
        this.setBallPosition(x, y);

        // Flash pegs deferred off this frame so DOM work can't cause jank
        for (const ph of pegHitFrames) {
          if (!flushed.has(ph.frameIdx) && frameIdx >= ph.frameIdx) {
            flushed.add(ph.frameIdx);
            const { row, col } = ph;
            setTimeout(() => this.flashPeg(row, col, rows), 0);
          }
        }

        if (p < 1) {
          requestAnimationFrame(animate);
        } else {
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  /**
   * Bouncy landing into the slot — ball drops, bounces twice, settles.
   */
  animateLanding(from, to, slotIndex) {
    return new Promise(resolve => {
      const startTime = performance.now();
      const duration = 600;
      const dropDist = to.y - from.y;

      const animate = (now) => {
        const elapsed = now - startTime;
        const p = Math.min(elapsed / duration, 1);

        // Bounce easing (Robert Penner's easeOutBounce)
        const bounce = this.easeOutBounce(p);

        const cx = from.x + (to.x - from.x) * p;
        const cy = from.y + dropDist * bounce;

        this.setBallPosition(cx, cy);

        if (p < 1) {
          requestAnimationFrame(animate);
        } else {
          this.setBallPosition(to.x, to.y);
          this.highlightSlot(slotIndex);
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  easeOutBounce(t) {
    if (t < 1 / 2.75) {
      return 7.5625 * t * t;
    } else if (t < 2 / 2.75) {
      t -= 1.5 / 2.75;
      return 7.5625 * t * t + 0.75;
    } else if (t < 2.5 / 2.75) {
      t -= 2.25 / 2.75;
      return 7.5625 * t * t + 0.9375;
    } else {
      t -= 2.625 / 2.75;
      return 7.5625 * t * t + 0.984375;
    }
  },

  // ============ Visual Effects ============

  flashPeg(row, col, rows) {
    const pegIndex = this.getPegIndex(row, col);
    if (!this.pegs[pegIndex]) return;

    const peg = this.pegs[pegIndex];
    const origFill = peg.getAttribute('fill');
    const origR = parseFloat(peg.getAttribute('r'));

    // Instant flash: bright lime glow + expand
    peg.style.transition = 'none';
    peg.setAttribute('fill', '#CAFC00');
    peg.setAttribute('r', origR * 2.5);

    // Slow fade back creates a glowing trail behind the ball
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        peg.style.transition = 'fill 1.5s ease-out, r 0.6s ease-out';
        peg.setAttribute('fill', origFill);
        peg.setAttribute('r', origR);
      });
    });

    // Expanding ring effect
    const pos = this.getPegPosition(row, col, rows);
    const ring = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    ring.setAttribute('cx', pos.x);
    ring.setAttribute('cy', pos.y);
    ring.setAttribute('r', origR * 2);
    ring.setAttribute('fill', 'none');
    ring.setAttribute('stroke', '#CAFC00');
    ring.setAttribute('stroke-width', '1.5');
    ring.setAttribute('opacity', '0.6');
    this.ball.parentNode.insertBefore(ring, this.ball);
    this.effects.push(ring);

    const ringStart = performance.now();
    const maxR = origR * 7;
    const ringDur = 350;
    const animateRing = (now) => {
      const p = Math.min((now - ringStart) / ringDur, 1);
      ring.setAttribute('r', origR * 2 + (maxR - origR * 2) * p);
      ring.setAttribute('opacity', 0.6 * (1 - p));
      if (p < 1) requestAnimationFrame(animateRing);
      else ring.remove();
    };
    requestAnimationFrame(animateRing);
  },

  highlightSlot(position) {
    if (!this.slots[position]) return;
    const slot = this.slots[position];
    const origColor = slot.getAttribute('fill') || '#fff';
    slot.classList.add('plinko-slot-hit');

    // Store original fill so clearEffects can restore it
    slot._origFill = origColor;

    // Change slot fill to a brighter version — mix with white
    const bright = this.brightenColor(origColor, 0.45);
    slot.setAttribute('fill', bright);

    // Track so updated() can re-apply after LiveView DOM patches
    this._hitSlot = { position, brightColor: bright };
  },

  /**
   * Mix a hex color with white by the given amount (0 = original, 1 = white).
   */
  brightenColor(hex, amount) {
    // Parse hex
    const m = hex.match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
    if (!m) return hex;
    const r = Math.round(parseInt(m[1], 16) + (255 - parseInt(m[1], 16)) * amount);
    const g = Math.round(parseInt(m[2], 16) + (255 - parseInt(m[2], 16)) * amount);
    const b = Math.round(parseInt(m[3], 16) + (255 - parseInt(m[3], 16)) * amount);
    return `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
  },

  clearEffects() {
    this.trails.forEach(t => t.remove());
    this.trails = [];
    this.effects.forEach(e => e.remove());
    this.effects = [];
    this._hitSlot = null;
    this.el.querySelectorAll('.plinko-slot-hit').forEach(s => {
      s.classList.remove('plinko-slot-hit');
      if (s._origFill) {
        s.setAttribute('fill', s._origFill);
        delete s._origFill;
      }
    });
  },

  resetBall() {
    this.isAnimating = false;
    if (this.ball) {
      this.ball.style.transition = '';
      this.ball.style.willChange = '';
    }
    this.clearBallTransform();
    this.clearEffects();

    // Since ball is phx-update="ignore", morphdom won't reset cx/cy for us.
    // Explicitly move ball back to start position.
    if (this.ball) {
      this.ball.setAttribute('cx', BASE_X);
      this.ball.setAttribute('cy', BASE_Y);
    }
  }
};
