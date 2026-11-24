{{flutter_js}}
{{flutter_build_config}}

(() => {
  const startup = document.getElementById('nodeql-startup');
  const status = document.getElementById('nodeql-startup-status');
  const progress = document.getElementById('nodeql-startup-progress');
  const retry = document.getElementById('nodeql-startup-retry');
  let ready = false;
  let failed = false;

  retry.addEventListener('click', () => window.location.reload());
  const slowTimer = window.setTimeout(() => {
    status.textContent = 'The demo is still loading. You can wait or reload.';
    retry.hidden = false;
  }, 10000);

  function showStartupError(error) {
    if (ready || failed) return;
    failed = true;
    window.clearTimeout(slowTimer);
    status.textContent = 'The demo could not start. Reload to try again.';
    progress.hidden = true;
    retry.hidden = false;
    console.error('NodeQL startup failed', error);
  }

  const startupEvents = new AbortController();
  const options = { signal: startupEvents.signal };
  window.addEventListener('flutter-first-frame', () => {
    ready = true;
    window.clearTimeout(slowTimer);
    startupEvents.abort();
    startup.remove();
  }, options);

  window.addEventListener('error', (event) => {
    if (event.target instanceof HTMLScriptElement || event instanceof ErrorEvent) {
      showStartupError(event.error || event.target.src || event.message);
    }
  }, { ...options, capture: true });
  window.addEventListener('unhandledrejection', (event) => {
    showStartupError(event.reason);
  }, options);

  _flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
      } catch (error) {
        showStartupError(error);
      }
    },
  }).catch(showStartupError);
})();
