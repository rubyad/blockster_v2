// Banner Drag Hook for repositioning banner images
export const BannerDrag = {
  mounted() {
    this.isDragging = false;
    this.startX = 0;
    this.startY = 0;
    this.currentX = 50;
    this.currentY = 50;

    // Parse initial position from style
    const style = this.el.style.objectPosition;
    if (style) {
      const match = style.match(/(\d+(?:\.\d+)?)%\s+(\d+(?:\.\d+)?)%/);
      if (match) {
        this.currentX = parseFloat(match[1]);
        this.currentY = parseFloat(match[2]);
      }
    }

    // Get zoom level from data attribute
    this.zoom = parseFloat(this.el.dataset.zoom) || 100;

    this.el.addEventListener("mousedown", this.onMouseDown.bind(this));
    this.el.addEventListener("touchstart", this.onTouchStart.bind(this), { passive: false });

    document.addEventListener("mousemove", this.onMouseMove.bind(this));
    document.addEventListener("mouseup", this.onMouseUp.bind(this));
    document.addEventListener("touchmove", this.onTouchMove.bind(this), { passive: false });
    document.addEventListener("touchend", this.onTouchEnd.bind(this));

    // Prevent default drag behavior
    this.el.addEventListener("dragstart", (e) => e.preventDefault());
  },

  updated() {
    // Update zoom when the element is updated
    this.zoom = parseFloat(this.el.dataset.zoom) || 100;
  },

  destroyed() {
    document.removeEventListener("mousemove", this.onMouseMove.bind(this));
    document.removeEventListener("mouseup", this.onMouseUp.bind(this));
    document.removeEventListener("touchmove", this.onTouchMove.bind(this));
    document.removeEventListener("touchend", this.onTouchEnd.bind(this));
  },

  onMouseDown(e) {
    this.isDragging = true;
    this.startX = e.clientX;
    this.startY = e.clientY;
    this.el.style.cursor = "grabbing";
    e.preventDefault();
  },

  onTouchStart(e) {
    if (e.touches.length === 1) {
      this.isDragging = true;
      this.startX = e.touches[0].clientX;
      this.startY = e.touches[0].clientY;
      e.preventDefault();
    }
  },

  onMouseMove(e) {
    if (!this.isDragging) return;
    this.updatePosition(e.clientX, e.clientY);
  },

  onTouchMove(e) {
    if (!this.isDragging || e.touches.length !== 1) return;
    this.updatePosition(e.touches[0].clientX, e.touches[0].clientY);
    e.preventDefault();
  },

  updatePosition(clientX, clientY) {
    const deltaX = this.startX - clientX;
    const deltaY = this.startY - clientY;

    // Adjust sensitivity based on zoom level
    // Higher zoom = more area to move = need more sensitivity
    const zoomFactor = this.zoom / 100;
    const baseSensitivity = 0.15;
    const sensitivity = baseSensitivity * zoomFactor;

    let newX = this.currentX + deltaX * sensitivity;
    let newY = this.currentY + deltaY * sensitivity;

    // Clamp values between 0 and 100
    newX = Math.max(0, Math.min(100, newX));
    newY = Math.max(0, Math.min(100, newY));

    // Update both object-position and transform-origin together
    this.el.style.objectPosition = `${newX}% ${newY}%`;
    this.el.style.transformOrigin = `${newX}% ${newY}%`;

    // Update start position for continuous dragging
    this.startX = clientX;
    this.startY = clientY;
    this.currentX = newX;
    this.currentY = newY;
  },

  onMouseUp() {
    if (!this.isDragging) return;
    this.isDragging = false;
    this.el.style.cursor = "move";
    this.savePosition();
  },

  onTouchEnd() {
    if (!this.isDragging) return;
    this.isDragging = false;
    this.savePosition();
  },

  savePosition() {
    const position = `${this.currentX.toFixed(1)}% ${this.currentY.toFixed(1)}%`;
    const targetSelector = this.el.dataset.target;
    this.pushEventTo(targetSelector, "update_position", { position });
  },
};
