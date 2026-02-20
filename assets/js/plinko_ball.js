/**
 * PlinkoBall Hook - SVG ball drop animation for Plinko game
 *
 * Handles ball animation through peg rows with:
 * - Row-by-row timing with ease-out cubic easing
 * - Trail effects showing ball path
 * - Peg flash on collision
 * - Landing slot highlight
 * - 6 second total animation time across all configs
 */

export const PlinkoBall = {
  mounted() {
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
    this.trails = [];

    this.handleEvent("drop_ball", ({ ball_path, landing_position, rows }) => {
      this.animateDrop(ball_path, landing_position, rows);
    });
    this.handleEvent("reset_ball", () => this.resetBall());
  },

  updated() {
    // Re-cache elements after LiveView re-renders
    this.ball = this.el.querySelector('#plinko-ball');
    this.pegs = this.el.querySelectorAll('.plinko-peg');
    this.slots = this.el.querySelectorAll('.plinko-slot');
  },

  // ============ SVG Coordinate System ============

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
    const startX = 200 - rowWidth / 2;

    return {
      x: startX + col * spacing,
      y: topMargin + row * rowHeight
    };
  },

  getBallPositionAfterBounce(row, pathSoFar, rows) {
    const rightCount = pathSoFar.filter(d => d === 1).length;
    const { topMargin, rowHeight, spacing } = this.getLayout(rows);

    const nextRow = row + 1;
    if (nextRow >= rows) {
      return this.getSlotPosition(rightCount, rows);
    }

    const numPegsNext = nextRow + 1;
    const rowWidthNext = (numPegsNext - 1) * spacing;
    const startXNext = 200 - rowWidthNext / 2;

    return {
      x: startXNext + rightCount * spacing,
      y: topMargin + row * rowHeight + rowHeight / 2
    };
  },

  getSlotPosition(index, rows) {
    const { viewHeight } = this.getLayout(rows);
    const numSlots = rows + 1;
    const slotWidth = 340 / numSlots;
    const startX = 200 - (numSlots - 1) * slotWidth / 2;

    return {
      x: startX + index * slotWidth,
      y: viewHeight - 25
    };
  },

  // ============ Animation ============

  async animateDrop(ballPath, landingPosition, rows) {
    this.clearTrails();
    this.ball.style.display = 'block';
    this.ball.setAttribute('cx', '200');
    this.ball.setAttribute('cy', '10');

    const timings = this.calculateTimings(rows);

    for (let i = 0; i < ballPath.length; i++) {
      const pathSoFar = ballPath.slice(0, i + 1);
      await this.animateToRow(i, ballPath[i], pathSoFar, rows, timings[i]);
    }

    await this.animateLanding(landingPosition, rows, 800);
    this.pushEvent("ball_landed", {});
  },

  animateToRow(rowIndex, direction, pathSoFar, rows, duration) {
    return new Promise(resolve => {
      const startX = parseFloat(this.ball.getAttribute('cx'));
      const startY = parseFloat(this.ball.getAttribute('cy'));
      const target = this.getBallPositionAfterBounce(rowIndex, pathSoFar, rows);
      const startTime = performance.now();

      this.addTrail(startX, startY);
      this.flashPeg(rowIndex, pathSoFar, rows);

      const animate = (now) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        // Ease-out cubic for natural deceleration
        const eased = 1 - Math.pow(1 - progress, 3);

        const currentX = startX + (target.x - startX) * eased;
        const currentY = startY + (target.y - startY) * eased;

        this.ball.setAttribute('cx', currentX);
        this.ball.setAttribute('cy', currentY);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  animateLanding(landingPosition, rows, duration) {
    return new Promise(resolve => {
      const startX = parseFloat(this.ball.getAttribute('cx'));
      const startY = parseFloat(this.ball.getAttribute('cy'));
      const target = this.getSlotPosition(landingPosition, rows);
      const startTime = performance.now();

      const animate = (now) => {
        const elapsed = now - startTime;
        const progress = Math.min(elapsed / duration, 1);
        // Bounce ease for landing
        const eased = 1 - Math.pow(1 - progress, 2);

        this.ball.setAttribute('cx', startX + (target.x - startX) * eased);
        this.ball.setAttribute('cy', startY + (target.y - startY) * eased);

        if (progress < 1) {
          requestAnimationFrame(animate);
        } else {
          this.highlightSlot(landingPosition);
          resolve();
        }
      };

      requestAnimationFrame(animate);
    });
  },

  calculateTimings(rows) {
    const totalMs = 6000;
    const ratio = 2.5;
    const minTime = 2 * (totalMs / rows) / (1 + ratio);
    return Array.from({length: rows}, (_, i) =>
      minTime + (minTime * ratio - minTime) * (i / (rows - 1))
    );
  },

  // ============ Visual Effects ============

  addTrail(x, y) {
    const trail = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    trail.setAttribute('cx', x);
    trail.setAttribute('cy', y);
    trail.setAttribute('r', '3');
    trail.setAttribute('fill', '#CAFC00');
    trail.setAttribute('opacity', '0.4');
    trail.classList.add('plinko-trail');
    this.el.appendChild(trail);
    this.trails.push(trail);

    setTimeout(() => {
      trail.setAttribute('opacity', '0.15');
    }, 300);
  },

  flashPeg(rowIndex, pathSoFar, rows) {
    const rightsBefore = pathSoFar.slice(0, -1).filter(d => d === 1).length;
    const col = rightsBefore;
    const pegIndex = this.getPegIndex(rowIndex, col, rows);

    if (this.pegs[pegIndex]) {
      const peg = this.pegs[pegIndex];
      const origFill = peg.getAttribute('fill');
      const origR = parseFloat(peg.getAttribute('r'));
      peg.setAttribute('fill', '#ffffff');
      peg.setAttribute('r', origR * 1.5);
      setTimeout(() => {
        peg.setAttribute('fill', origFill);
        peg.setAttribute('r', origR);
      }, 200);
    }
  },

  getPegIndex(row, col, rows) {
    // Pegs rendered sequentially: row 0 has 1, row 1 has 2, etc.
    let index = 0;
    for (let r = 0; r < row; r++) {
      index += (r + 1);
    }
    return index + col;
  },

  highlightSlot(position) {
    if (this.slots[position]) {
      this.slots[position].classList.add('plinko-slot-hit');
    }
  },

  clearTrails() {
    this.trails.forEach(t => t.remove());
    this.trails = [];
    this.el.querySelectorAll('.plinko-slot-hit').forEach(s => {
      s.classList.remove('plinko-slot-hit');
    });
  },

  resetBall() {
    if (this.ball) {
      this.ball.style.display = 'none';
      this.ball.setAttribute('cx', '200');
      this.ball.setAttribute('cy', '10');
    }
    this.clearTrails();
  }
};
