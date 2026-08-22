/* ClipMate landing page — small progressive enhancements only.
   The page is fully readable with JavaScript disabled; everything here is optional. */

(function () {
  "use strict";

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Reveal sections as they scroll into view. If IntersectionObserver is missing
     or the visitor prefers reduced motion, show everything immediately instead. */
  var revealables = document.querySelectorAll(".reveal");

  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealables.forEach(function (el) { el.classList.add("visible"); });
  } else {
    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("visible");
          observer.unobserve(entry.target); // reveal once, then stop watching
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    revealables.forEach(function (el) { observer.observe(el); });

    /* Safety net. IntersectionObserver exists in some environments but never
       delivers a callback (certain webviews, headless renderers, link-preview
       crawlers). Without this the page would sit there blank, so reveal whatever
       is still hidden a moment after load and disconnect. */
    window.addEventListener("load", function () {
      window.setTimeout(function () {
        var stillHidden = document.querySelectorAll(".reveal:not(.visible)");
        if (!stillHidden.length) return;
        observer.disconnect();
        stillHidden.forEach(function (el) { el.classList.add("visible"); });
      }, 1200);
    });
  }

  /* Fetch the newest release tag so the version chip cannot go stale.
     Silently left as-is if the request fails — offline, rate-limited, whatever. */
  var chip = document.querySelector(".chip");
  if (chip && "fetch" in window) {
    fetch("https://api.github.com/repos/ganeshparajuli11/clipmate/releases/latest", {
      headers: { Accept: "application/vnd.github+json" }
    })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !data.tag_name) return;
        var version = String(data.tag_name).replace(/^v/, "").replace(/\.0$/, "");
        chip.innerHTML =
          '<span class="dot"></span> v' + version + " &middot; macOS 13 Ventura or later";
      })
      .catch(function () { /* keep the hardcoded version */ });
  }
})();
