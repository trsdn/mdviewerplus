// Build-time entry for the shared marked-footnote extension.
// Emitted as a classic script that assigns a single global so the render page
// can keep loading it inline under the nonce-only script-src policy.
import markedFootnote from "marked-footnote";

globalThis.markedFootnote = markedFootnote;
