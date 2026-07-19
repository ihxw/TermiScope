(function () {
  const terminals = new Map();

  function getTheme(theme) {
    return theme || {
      background: '#1e1e1e',
      foreground: '#cccccc',
      cursor: '#ffffff',
      selectionBackground: '#cccccc',
      selectionForeground: '#1e1e1e'
    };
  }

  window.termiScopeTerminal = {
    create(id, options) {
      const element = document.getElementById(id);
      if (!element) {
        console.warn('[TermiScopeTerminal] container not found', id);
        return false;
      }
      if (!window.Terminal) {
        console.warn('[TermiScopeTerminal] xterm.js not loaded');
        return false;
      }
      this.dispose(id);
      element.style.width = '100%';
      element.style.height = '100%';
      element.style.minHeight = '120px';
      element.style.overflow = 'hidden';
      element.style.background = options.theme?.background || '#1e1e1e';

      const fitAddon = new window.FitAddon.FitAddon();
      const webLinksAddon = new window.WebLinksAddon.WebLinksAddon();
      const term = new window.Terminal({
        cursorBlink: true,
        cursorStyle: 'block',
        cursorInactiveStyle: 'outline',
        fontFamily: options.fontFamily || "'TermiScope Mono', monospace",
        fontSize: options.fontSize || 14,
        lineHeight: 1,
        letterSpacing: 0,
        scrollback: 3000,
        scrollOnUserInput: true,
        theme: getTheme(options.theme)
      });

      term.loadAddon(fitAddon);
      term.loadAddon(webLinksAddon);
      term.open(element);
      term.refresh(0, term.rows - 1);
      term.focus();

      const resize = () => {
        try {
          fitAddon.fit();
          if (options.onResize) {
            options.onResize(term.cols, term.rows);
          }
        } catch (_) {}
      };

      const resizeObserver = new ResizeObserver(() => {
        requestAnimationFrame(resize);
      });
      resizeObserver.observe(element);
      window.addEventListener('resize', resize);

      const dataDisposable = term.onData((data) => {
        if (options.onData) options.onData(data);
      });

      terminals.set(id, {
        term,
        fitAddon,
        resizeObserver,
        dataDisposable,
        resize
      });

      requestAnimationFrame(resize);
      return true;
    },

    write(id, data) {
      const item = terminals.get(id);
      if (!item || !data) return;
      item.term.write(data);
    },

    update(id, options) {
      const item = terminals.get(id);
      if (!item) return;
      item.term.options.fontFamily = options.fontFamily || item.term.options.fontFamily;
      item.term.options.fontSize = options.fontSize || item.term.options.fontSize;
      item.term.options.theme = getTheme(options.theme);
      requestAnimationFrame(item.resize);
    },

    focus(id) {
      terminals.get(id)?.term.focus();
    },

    getSelection(id) {
      return terminals.get(id)?.term.getSelection() || '';
    },

    clearSelection(id) {
      terminals.get(id)?.term.clearSelection();
    },

    selectAll(id) {
      terminals.get(id)?.term.selectAll();
    },

    dispose(id) {
      const item = terminals.get(id);
      if (!item) return;
      item.resizeObserver.disconnect();
      window.removeEventListener('resize', item.resize);
      item.dataDisposable.dispose();
      item.term.dispose();
      terminals.delete(id);
    }
  };
})();
