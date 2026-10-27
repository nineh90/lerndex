{{flutter_js}}
{{flutter_build_config}}

// Eigener Bootstrap: entfernt den Ladebildschirm aus index.html, sobald die
// App läuft, und lädt Ersatzschriften (Emojis, Symbole) aus web/fonts statt
// von fonts.gstatic.com.
const config = {
  fontFallbackBaseUrl: "fonts/",
};

_flutter.loader.load({
  config,
  onEntrypointLoaded: async function (engineInitializer) {
    // Mit eigenem onEntrypointLoaded reicht Flutter die config nicht selbst
    // an die Engine weiter.
    const appRunner = await engineInitializer.initializeEngine(config);
    await appRunner.runApp();
    document.getElementById('loading')?.remove();
  },
});
