{{flutter_js}}
{{flutter_build_config}}

// Use the renderer served by Flutter locally, including during debug runs.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
