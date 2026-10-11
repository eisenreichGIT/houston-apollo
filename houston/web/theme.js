// Apply the saved appearance before the page draws (no flash of the wrong theme).
try { var t = localStorage.getItem("houstonTheme"); if (t === "light" || t === "dark" || t === "system") document.documentElement.dataset.theme = t; } catch (e) {}
