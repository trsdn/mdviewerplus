// Build-time entry for the Full-edition highlight.js module.
// Bundled to a single ESM file so the preview can import it lazily from the
// bundle-only module scheme without a package resolver at runtime.
import hljs from "highlight.js/lib/common";

export default hljs;
