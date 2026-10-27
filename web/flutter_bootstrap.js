{{flutter_js}}
{{flutter_build_config}}

// Eigener Bootstrap nur, um den Ladebildschirm aus index.html zu entfernen,
// sobald die App läuft.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    document.getElementById('loading')?.remove();
  },
});
