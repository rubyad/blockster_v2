/**
 * PlinkoBall Hook - Plinko ball drop animation
 *
 * Catmull-Rom spline through all key points, pre-sampled at high resolution
 * and arc-length reparameterized for perfectly uniform speed.
 * Dedicated bouncy landing animation at the end.
 */

export const PlinkoBall = {
  mounted() {
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
    this.trails = [];
    this.effects = [];
    this.isAnimating = false;
    this._ballPos = null;

    this.handleEvent("drop_ball", ({ ball_path, landing_position, rows }) => {
      this.animateDrop(ball_path, landing_position, rows);
    });
    this.handleEvent("reset_ball", () => this.resetBall());
  },

  updated() {
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
    if (this.isAnimating && this.ball && this._ballPos) {
      this.ball.setAttribute('cx', this._ballPos.x);
      this.ball.setAttribute('cy', this._ballPos.y);
    }
  },

  // ============ Layout ============

  getLayout(rows) {
    const viewHeight = rows === 8 ? 340 : rows === 12 ? 460 : 580;
    const topMargin = 30;
    const bottomMargin = 50;
    const boardHeight = viewHeight - topMargin - bottomMargin;
    const rowHeight = boardHeight / rows;
    const spacing = 340 / (rows + 1);
    return { viewHeight, topMargin, rowHeight, spacing };
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
    const slotWidth = 340 / numSlots;
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

  cr(t, p0, p1, p2, p3) {
    const t2 = t * t, t3 = t2 * t;
    return 0.5 * (
      2 * p1 +
      (-p0 + p2) * t +
      (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
      (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    );
  },

  // ============ Spline Sampling ============

  /**
   * Pre-sample the Catmull-Rom spline at high resolution,
   * then build an arc-length lookup table for uniform-speed playback.
   *
   * Virtual extension points are added before the first and after the last
   * control point so every segment has proper Catmull-Rom neighbor context.
   * Without these, boundary segments clamp to duplicated endpoints, producing
   * flat tangents and visible stiffness at the start/end of the path.
   */
  buildSplinePath(pts) {
    const segs = pts.length - 1;

    // Virtual extension: extrapolate one point before and after
    const first = pts[0], second = pts[1];
    const last = pts[pts.length - 1], secondLast = pts[pts.length - 2];
    const ext = [
      { x: 2 * first.x - second.x, y: 2 * first.y - second.y },
      ...pts,
      { x: 2 * last.x - secondLast.x, y: 2 * last.y - secondLast.y }
    ];

    const samplesPerSeg = 60;
    const totalSamples = segs * samplesPerSeg;

    // Sample positions along the spline
    const path = [];
    for (let s = 0; s <= totalSamples; s++) {
      const global = s / totalSamples;
      const scaled = global * segs;
      const seg = Math.min(Math.floor(scaled), segs - 1);
      const t = scaled - seg;

      // ext[0] = virtual, ext[1] = pts[0], ..., ext[pts.length] = pts[last], ext[pts.length+1] = virtual
      const i0 = seg;
      const i1 = seg + 1;
      const i2 = seg + 2;
      const i3 = seg + 3;

      path.push({
        x: this.cr(t, ext[i0].x, ext[i1].x, ext[i2].x, ext[i3].x),
        y: this.cr(t, ext[i0].y, ext[i1].y, ext[i2].y, ext[i3].y),
        seg
      });
    }

    // Compute cumulative arc lengths
    const arcLens = [0];
    let total = 0;
    for (let i = 1; i < path.length; i++) {
      const dx = path[i].x - path[i - 1].x;
      const dy = path[i].y - path[i - 1].y;
      total += Math.sqrt(dx * dx + dy * dy);
      arcLens.push(total);
    }

    return { path, arcLens, totalLen: total };
  },

  /**
   * Given a normalized distance [0..1], find the position on the pre-sampled path.
   */
  sampleAtDistance(spline, distFrac) {
    const targetLen = distFrac * spline.totalLen;
    const { path, arcLens } = spline;

    // Binary search for the right sample
    let lo = 0, hi = path.length - 1;
    while (lo < hi - 1) {
      const mid = (lo + hi) >> 1;
      if (arcLens[mid] <= targetLen) lo = mid;
      else hi = mid;
    }

    // Lerp between lo and hi
    const segLen = arcLens[hi] - arcLens[lo];
    const frac = segLen > 0 ? (targetLen - arcLens[lo]) / segLen : 0;

    return {
      x: path[lo].x + (path[hi].x - path[lo].x) * frac,
      y: path[lo].y + (path[hi].y - path[lo].y) * frac
    };
  },

  // ============ Main Animation ============

  async animateDrop(ballPath, landingPosition, rows) {
    this.clearEffects();
    this.isAnimating = true;
    this._ballPos = { x: 200, y: 10 };

    const { rowHeight, spacing } = this.getLayout(rows);

    // Build spline points: start → (peg, bounce)* → approach
    const pts = [{ x: 200, y: 10 }];
    const pegHits = [];

    let col = 0;
    for (let i = 0; i < ballPath.length; i++) {
      const pegCol = col;
      const peg = this.getPegPosition(i, pegCol, rows);

      pegHits.push({ idx: pts.length, row: i, col: pegCol });
      pts.push({ x: peg.x, y: peg.y });

      // Bounce apex above the peg
      const dir = ballPath[i] === 1 ? 1 : -1;
      pts.push({
        x: peg.x + dir * spacing * 0.45,
        y: peg.y - rowHeight * 0.45
      });

      col += ballPath[i];
    }

    // End spline above the slot (landing handled separately)
    const slotPos = this.getSlotPosition(col, rows);
    pts.push({ x: slotPos.x, y: slotPos.y - 25 });

    // Pre-sample and arc-length parameterize
    const spline = this.buildSplinePath(pts);

    // Map peg indices to arc-length fractions for flash timing
    const pegDistFracs = pegHits.map(ph => {
      // Find the arc-length fraction at the peg point index
      const sampleIdx = Math.round((ph.idx / (pts.length - 1)) * (spline.path.length - 1));
      return { ...ph, distFrac: spline.arcLens[sampleIdx] / spline.totalLen };
    });

    // Animate along the spline
    await this.animateAlongPath(spline, pegDistFracs, rows, 3200);

    // Bouncy landing into slot
    const approachPos = { x: slotPos.x, y: slotPos.y - 25 };
    await this.animateLanding(approachPos, slotPos, landingPosition);

    this.isAnimating = false;
    this.pushEvent("ball_landed", {});
  },

  // Ease-in for first 8% of progress, then linear — mimics ball accelerating from rest
  easeInLinear(t) {
    const blend = 0.08;
    if (t < blend) {
      // Quadratic ease-in within the blend zone
      const n = t / blend;
      return blend * n * n;
    }
    return t;
  },

  animateAlongPath(spline, pegDistFracs, rows, duration) {
    return new Promise(resolve => {
      const startTime = performance.now();
      const flushed = new Set();

      const animate = (now) => {
        const elapsed = now - startTime;
        const p = Math.min(elapsed / duration, 1);
        const eased = this.easeInLinear(p);

        const pos = this.sampleAtDistance(spline, eased);

        // Flash pegs (compare against eased progress)
        for (const ph of pegDistFracs) {
          if (!flushed.has(ph.idx) && eased >= ph.distFrac) {
            flushed.add(ph.idx);
            this.flashPeg(ph.row, ph.col, rows);
          }
        }

        this._ballPos = pos;
        this.ball.setAttribute('cx', pos.x);
        this.ball.setAttribute('cy', pos.y);

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

        this._ballPos = { x: cx, y: cy };
        this.ball.setAttribute('cx', cx);
        this.ball.setAttribute('cy', cy);

        if (p < 1) {
          requestAnimationFrame(animate);
        } else {
          this._ballPos = { x: to.x, y: to.y };
          this.ball.setAttribute('cx', to.x);
          this.ball.setAttribute('cy', to.y);
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

    peg.style.transition = 'none';
    peg.setAttribute('fill', '#ffffff');
    peg.setAttribute('r', origR * 2.5);
    peg.getBBox();

    setTimeout(() => {
      peg.style.transition = 'fill 0.3s ease-out, r 0.3s ease-out';
      peg.setAttribute('fill', origFill);
      peg.setAttribute('r', origR);
    }, 120);

    const pos = this.getPegPosition(row, col, rows);
    const ring = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    ring.setAttribute('cx', pos.x);
    ring.setAttribute('cy', pos.y);
    ring.setAttribute('r', origR * 2);
    ring.setAttribute('fill', 'none');
    ring.setAttribute('stroke', '#fff');
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
    slot.classList.add('plinko-slot-hit');

    const rect = slot.getBBox ? slot.getBBox() : null;
    if (rect) {
      const flash = document.createElementNS("http://www.w3.org/2000/svg", "rect");
      flash.setAttribute('x', rect.x);
      flash.setAttribute('y', rect.y);
      flash.setAttribute('width', rect.width);
      flash.setAttribute('height', rect.height);
      flash.setAttribute('rx', '4');
      flash.setAttribute('fill', '#fff');
      flash.setAttribute('opacity', '0.9');
      this.el.appendChild(flash);
      this.effects.push(flash);

      const start = performance.now();
      const dur = 600;
      const fadeFlash = (now) => {
        const p = Math.min((now - start) / dur, 1);
        flash.setAttribute('opacity', 0.9 * (1 - p));
        if (p < 1) requestAnimationFrame(fadeFlash);
        else flash.remove();
      };
      requestAnimationFrame(fadeFlash);
    }
  },

  clearEffects() {
    this.trails.forEach(t => t.remove());
    this.trails = [];
    this.effects.forEach(e => e.remove());
    this.effects = [];
    this.el.querySelectorAll('.plinko-slot-hit').forEach(s => {
      s.classList.remove('plinko-slot-hit');
    });
  },

  resetBall() {
    this.isAnimating = false;
    this._ballPos = null;
    if (this.ball) {
      this.ball.setAttribute('cx', '200');
      this.ball.setAttribute('cy', '10');
    }
    this.clearEffects();
  }
};
