// Build-time entry for the Full-edition svg-pan-zoom module.
// The upstream distribution is UMD; wrapping it produces one ESM file that the
// preview can import lazily after a diagram has rendered successfully.
import svgPanZoom from "svg-pan-zoom";

export default svgPanZoom;
