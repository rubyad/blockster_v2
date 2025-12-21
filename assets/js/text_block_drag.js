// Text Block Drag and Resize Hook for repositioning and resizing text overlays
export const TextBlockDragResize = {
  mounted() {
    this.isDragging = false;
    this.isResizing = false;
    this.startX = 0;
    this.startY = 0;
    this.currentX = 50;
    this.currentY = 50;
    this.startWidth = 0;
    this.startHeight = 0;

    // Parse initial position from style (left: X%; top: Y%)
    const style = this.el.style;
    if (style.left && style.top) {
      const leftMatch = style.left.match(/(\d+(?:\.\d+)?)/);
      const topMatch = style.top.match(/(\d+(?:\.\d+)?)/);
      if (leftMatch) this.currentX = parseFloat(leftMatch[1]);
      if (topMatch) this.currentY = parseFloat(topMatch[1]);
    }

    this.el.addEventListener("mousedown", this.onMouseDown.bind(this));
    this.el.addEventListener("touchstart", this.onTouchStart.bind(this), { passive: false });

    this.boundMouseMove = this.onMouseMove.bind(this);
    this.boundMouseUp = this.onMouseUp.bind(this);
    this.boundTouchMove = this.onTouchMove.bind(this);
    this.boundTouchEnd = this.onTouchEnd.bind(this);

    document.addEventListener("mousemove", this.boundMouseMove);
    document.addEventListener("mouseup", this.boundMouseUp);
    document.addEventListener("touchmove", this.boundTouchMove, { passive: false });
    document.addEventListener("touchend", this.boundTouchEnd);

    // Prevent default drag behavior
    this.el.addEventListener("dragstart", (e) => e.preventDefault());
  },

  destroyed() {
    document.removeEventListener("mousemove", this.boundMouseMove);
    document.removeEventListener("mouseup", this.boundMouseUp);
    document.removeEventListener("touchmove", this.boundTouchMove);
    document.removeEventListener("touchend", this.boundTouchEnd);
  },

  onMouseDown(e) {
    // Check if clicking on resize handle
    if (e.target.closest('[data-resize-handle]')) {
      this.isResizing = true;
      this.startX = e.clientX;
      this.startY = e.clientY;
      this.startWidth = this.el.offsetWidth;
      this.startHeight = this.el.offsetHeight;
      e.preventDefault();
      e.stopPropagation();
      return;
    }

    // Don't start drag if clicking on form inputs or buttons inside the block
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' ||
        e.target.tagName === 'BUTTON' || e.target.tagName === 'A' ||
        e.target.closest('form')) {
      return;
    }

    this.isDragging = true;
    this.startX = e.clientX;
    this.startY = e.clientY;
    this.el.style.cursor = "grabbing";
    e.preventDefault();
  },

  onTouchStart(e) {
    // Check if touching on resize handle
    if (e.target.closest('[data-resize-handle]')) {
      if (e.touches.length === 1) {
        this.isResizing = true;
        this.startX = e.touches[0].clientX;
        this.startY = e.touches[0].clientY;
        this.startWidth = this.el.offsetWidth;
        this.startHeight = this.el.offsetHeight;
        e.preventDefault();
      }
      return;
    }

    // Don't start drag if touching on form inputs or buttons
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' ||
        e.target.tagName === 'BUTTON' || e.target.tagName === 'A' ||
        e.target.closest('form')) {
      return;
    }

    if (e.touches.length === 1) {
      this.isDragging = true;
      this.startX = e.touches[0].clientX;
      this.startY = e.touches[0].clientY;
      e.preventDefault();
    }
  },

  onMouseMove(e) {
    if (this.isResizing) {
      this.updateSize(e.clientX, e.clientY);
    } else if (this.isDragging) {
      this.updatePosition(e.clientX, e.clientY);
    }
  },

  onTouchMove(e) {
    if (e.touches.length !== 1) return;

    if (this.isResizing) {
      this.updateSize(e.touches[0].clientX, e.touches[0].clientY);
      e.preventDefault();
    } else if (this.isDragging) {
      this.updatePosition(e.touches[0].clientX, e.touches[0].clientY);
      e.preventDefault();
    }
  },

  updatePosition(clientX, clientY) {
    // Get the parent container dimensions
    const parent = this.el.parentElement;
    if (!parent) return;

    const parentRect = parent.getBoundingClientRect();

    // Calculate delta as percentage of parent dimensions
    const deltaX = clientX - this.startX;
    const deltaY = clientY - this.startY;

    // Convert pixel delta to percentage
    const deltaXPercent = (deltaX / parentRect.width) * 100;
    const deltaYPercent = (deltaY / parentRect.height) * 100;

    let newX = this.currentX + deltaXPercent;
    let newY = this.currentY + deltaYPercent;

    // Clamp values between 5 and 95 to keep text block visible
    newX = Math.max(5, Math.min(95, newX));
    newY = Math.max(5, Math.min(95, newY));

    // Update position using left/top
    this.el.style.left = `${newX}%`;
    this.el.style.top = `${newY}%`;

    // Update start position for continuous dragging
    this.startX = clientX;
    this.startY = clientY;
    this.currentX = newX;
    this.currentY = newY;
  },

  updateSize(clientX, clientY) {
    const deltaX = clientX - this.startX;
    const deltaY = clientY - this.startY;

    // Calculate new dimensions with minimum sizes
    const newWidth = Math.max(150, this.startWidth + deltaX);
    const newHeight = Math.max(50, this.startHeight + deltaY);

    this.el.style.width = `${newWidth}px`;
    this.el.style.height = `${newHeight}px`;
  },

  onMouseUp() {
    if (this.isResizing) {
      this.isResizing = false;
      this.saveSize();
    } else if (this.isDragging) {
      this.isDragging = false;
      this.el.style.cursor = "move";
      this.savePosition();
    }
  },

  onTouchEnd() {
    if (this.isResizing) {
      this.isResizing = false;
      this.saveSize();
    } else if (this.isDragging) {
      this.isDragging = false;
      this.savePosition();
    }
  },

  savePosition() {
    const position = `${this.currentX.toFixed(1)}% ${this.currentY.toFixed(1)}%`;
    const targetSelector = this.el.dataset.target;
    this.pushEventTo(targetSelector, "update_overlay_position", { position });
  },

  saveSize() {
    const width = this.el.offsetWidth.toString();
    const height = this.el.offsetHeight.toString();
    const targetSelector = this.el.dataset.target;
    this.pushEventTo(targetSelector, "update_overlay_size", { width, height });
  },
};

// Keep the old TextBlockDrag for backwards compatibility
export const TextBlockDrag = TextBlockDragResize;

// Admin Controls Drag Hook for repositioning the admin control panel
export const AdminControlsDrag = {
  mounted() {
    this.isDragging = false;
    this.startX = 0;
    this.startY = 0;
    this.currentX = null;  // null means use CSS default
    this.currentY = null;

    // Find the closest positioned parent (relative, absolute, or fixed)
    // This handles nested structures like shop component's .inner-wrapper
    this.parent = this.findPositionedParent();

    // Get the drag handle element
    this.dragHandle = this.el.querySelector('[data-drag-handle]');
    const handleEl = this.dragHandle || this.el;

    handleEl.addEventListener("mousedown", this.onMouseDown.bind(this));
    handleEl.addEventListener("touchstart", this.onTouchStart.bind(this), { passive: false });

    this.boundMouseMove = this.onMouseMove.bind(this);
    this.boundMouseUp = this.onMouseUp.bind(this);
    this.boundTouchMove = this.onTouchMove.bind(this);
    this.boundTouchEnd = this.onTouchEnd.bind(this);

    document.addEventListener("mousemove", this.boundMouseMove);
    document.addEventListener("mouseup", this.boundMouseUp);
    document.addEventListener("touchmove", this.boundTouchMove, { passive: false });
    document.addEventListener("touchend", this.boundTouchEnd);

    // Prevent default drag behavior
    this.el.addEventListener("dragstart", (e) => e.preventDefault());

    // Load saved position from localStorage
    this.loadPosition();

    // Ensure z-index and pointer-events are set even if no saved position
    this.applyPosition();
  },

  findPositionedParent() {
    // Walk up the DOM tree to find the nearest positioned ancestor
    let parent = this.el.parentElement;
    while (parent && parent !== document.body) {
      const style = window.getComputedStyle(parent);
      const position = style.getPropertyValue('position');
      if (position === 'relative' || position === 'absolute' || position === 'fixed') {
        return parent;
      }
      parent = parent.parentElement;
    }
    // Fallback to section or parent
    return this.el.closest('section') || this.el.parentElement;
  },

  destroyed() {
    document.removeEventListener("mousemove", this.boundMouseMove);
    document.removeEventListener("mouseup", this.boundMouseUp);
    document.removeEventListener("touchmove", this.boundTouchMove);
    document.removeEventListener("touchend", this.boundTouchEnd);
  },

  updated() {
    // Re-apply position after LiveView patches the DOM
    // This ensures the position is maintained after other elements are dragged
    this.applyPosition();
  },

  loadPosition() {
    const savedPos = localStorage.getItem(`admin-controls-${this.el.id}`);
    if (savedPos) {
      try {
        const { x, y } = JSON.parse(savedPos);
        this.currentX = x;
        this.currentY = y;
        this.applyPosition();
      } catch (e) {
        // Ignore parse errors, use CSS default position
      }
    }
    // If no saved position, leave currentX/currentY as null
    // and don't call applyPosition - let CSS handle default positioning
  },

  savePosition() {
    const pos = {
      x: this.currentX,
      y: this.currentY
    };
    localStorage.setItem(`admin-controls-${this.el.id}`, JSON.stringify(pos));
  },

  applyPosition() {
    // Only apply position if we have actual values
    if (this.currentX !== null && this.currentY !== null) {
      // Use percentage-based positioning relative to parent
      this.el.style.left = `${this.currentX}%`;
      this.el.style.top = `${this.currentY}%`;
      this.el.style.right = 'auto';
      this.el.style.bottom = 'auto';
      this.el.style.transform = 'none';
    }
    // Always ensure pointer events work on all children and z-index is high
    this.el.style.pointerEvents = 'auto';
    this.el.style.zIndex = '50';
  },

  onMouseDown(e) {
    // Don't start drag if clicking on interactive elements
    const target = e.target;
    if (target.tagName === 'BUTTON' || target.tagName === 'INPUT' ||
        target.tagName === 'LABEL' || target.tagName === 'SVG' ||
        target.tagName === 'svg' || target.tagName === 'path' ||
        target.tagName === 'PATH' ||
        target.closest('button') || target.closest('label') ||
        target.closest('svg')) {
      // Let the event bubble up to the button
      return;
    }

    this.isDragging = true;
    this.startX = e.clientX;
    this.startY = e.clientY;

    this.el.style.cursor = "grabbing";
    e.preventDefault();
  },

  onTouchStart(e) {
    // Don't start drag if touching on interactive elements
    const target = e.target;
    if (target.tagName === 'BUTTON' || target.tagName === 'INPUT' ||
        target.tagName === 'LABEL' || target.tagName === 'SVG' ||
        target.tagName === 'svg' || target.tagName === 'path' ||
        target.tagName === 'PATH' ||
        target.closest('button') || target.closest('label') ||
        target.closest('svg')) {
      // Let the event bubble up to the button
      return;
    }

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
    if (!this.parent) return;

    const parentRect = this.parent.getBoundingClientRect();
    const elRect = this.el.getBoundingClientRect();

    // If this is the first drag (no saved position), calculate current position from DOM
    if (this.currentX === null || this.currentY === null) {
      // Calculate current position as percentage of parent
      const offsetX = elRect.left - parentRect.left;
      const offsetY = elRect.top - parentRect.top;
      this.currentX = (offsetX / parentRect.width) * 100;
      this.currentY = (offsetY / parentRect.height) * 100;
    }

    // Calculate delta as percentage of parent dimensions
    const deltaX = clientX - this.startX;
    const deltaY = clientY - this.startY;

    const deltaXPercent = (deltaX / parentRect.width) * 100;
    const deltaYPercent = (deltaY / parentRect.height) * 100;

    let newX = this.currentX + deltaXPercent;
    let newY = this.currentY + deltaYPercent;

    // Calculate element size as percentage of parent
    const elWidthPercent = (elRect.width / parentRect.width) * 100;
    const elHeightPercent = (elRect.height / parentRect.height) * 100;

    // Clamp to keep element within parent bounds
    newX = Math.max(0, Math.min(100 - elWidthPercent, newX));
    newY = Math.max(0, Math.min(100 - elHeightPercent, newY));

    // Update position
    this.el.style.left = `${newX}%`;
    this.el.style.top = `${newY}%`;
    this.el.style.right = 'auto';
    this.el.style.bottom = 'auto';

    // Update tracking for continuous drag
    this.startX = clientX;
    this.startY = clientY;
    this.currentX = newX;
    this.currentY = newY;
  },

  onMouseUp() {
    if (!this.isDragging) return;
    this.isDragging = false;
    this.el.style.cursor = "grab";
    this.savePosition();
  },

  onTouchEnd() {
    if (!this.isDragging) return;
    this.isDragging = false;
    this.savePosition();
  },
};

// Button Drag Hook for repositioning buttons
export const ButtonDrag = {
  mounted() {
    this.isDragging = false;
    this.startX = 0;
    this.startY = 0;
    this.currentX = 50;
    this.currentY = 70;

    // Parse initial position from style (left: X%; top: Y%)
    const style = this.el.style;
    if (style.left && style.top) {
      const leftMatch = style.left.match(/(\d+(?:\.\d+)?)/);
      const topMatch = style.top.match(/(\d+(?:\.\d+)?)/);
      if (leftMatch) this.currentX = parseFloat(leftMatch[1]);
      if (topMatch) this.currentY = parseFloat(topMatch[1]);
    }

    this.el.addEventListener("mousedown", this.onMouseDown.bind(this));
    this.el.addEventListener("touchstart", this.onTouchStart.bind(this), { passive: false });

    this.boundMouseMove = this.onMouseMove.bind(this);
    this.boundMouseUp = this.onMouseUp.bind(this);
    this.boundTouchMove = this.onTouchMove.bind(this);
    this.boundTouchEnd = this.onTouchEnd.bind(this);

    document.addEventListener("mousemove", this.boundMouseMove);
    document.addEventListener("mouseup", this.boundMouseUp);
    document.addEventListener("touchmove", this.boundTouchMove, { passive: false });
    document.addEventListener("touchend", this.boundTouchEnd);

    // Prevent default link behavior while dragging
    this.el.addEventListener("click", (e) => {
      if (this.wasDragging) {
        e.preventDefault();
        this.wasDragging = false;
      }
    });

    // Prevent default drag behavior
    this.el.addEventListener("dragstart", (e) => e.preventDefault());
  },

  destroyed() {
    document.removeEventListener("mousemove", this.boundMouseMove);
    document.removeEventListener("mouseup", this.boundMouseUp);
    document.removeEventListener("touchmove", this.boundTouchMove);
    document.removeEventListener("touchend", this.boundTouchEnd);
  },

  onMouseDown(e) {
    this.isDragging = true;
    this.wasDragging = false;
    this.startX = e.clientX;
    this.startY = e.clientY;
    this.el.style.cursor = "grabbing";
    e.preventDefault();
  },

  onTouchStart(e) {
    if (e.touches.length === 1) {
      this.isDragging = true;
      this.wasDragging = false;
      this.startX = e.touches[0].clientX;
      this.startY = e.touches[0].clientY;
      e.preventDefault();
    }
  },

  onMouseMove(e) {
    if (!this.isDragging) return;
    this.wasDragging = true;
    this.updatePosition(e.clientX, e.clientY);
  },

  onTouchMove(e) {
    if (!this.isDragging || e.touches.length !== 1) return;
    this.wasDragging = true;
    this.updatePosition(e.touches[0].clientX, e.touches[0].clientY);
    e.preventDefault();
  },

  updatePosition(clientX, clientY) {
    // Get the parent container dimensions (the banner section)
    const parent = this.el.closest('section');
    if (!parent) return;

    const parentRect = parent.getBoundingClientRect();

    // Calculate delta as percentage of parent dimensions
    const deltaX = clientX - this.startX;
    const deltaY = clientY - this.startY;

    // Convert pixel delta to percentage
    const deltaXPercent = (deltaX / parentRect.width) * 100;
    const deltaYPercent = (deltaY / parentRect.height) * 100;

    let newX = this.currentX + deltaXPercent;
    let newY = this.currentY + deltaYPercent;

    // Clamp values between 5 and 95 to keep button visible
    newX = Math.max(5, Math.min(95, newX));
    newY = Math.max(5, Math.min(95, newY));

    // Update position using left/top
    this.el.style.left = `${newX}%`;
    this.el.style.top = `${newY}%`;

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
    if (this.wasDragging) {
      this.savePosition();
    }
  },

  onTouchEnd() {
    if (!this.isDragging) return;
    this.isDragging = false;
    if (this.wasDragging) {
      this.savePosition();
    }
  },

  savePosition() {
    const position = `${this.currentX.toFixed(1)}% ${this.currentY.toFixed(1)}%`;
    const targetSelector = this.el.dataset.target;
    this.pushEventTo(targetSelector, "update_button_position", { position });
  },
};
