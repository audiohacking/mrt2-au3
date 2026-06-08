/**
 * Fork-specific accent palette (mrt2-au3).
 * Upstream Magenta RT uses cyan #71fade; we use a soft violet for controls.
 */

/** Primary accent: toggles, knobs, sliders, keyboard highlights, bank dots */
export const FORK_ACCENT = '#9B7EDE';

/** Slightly lifted accent for small filled indicators */
export const FORK_ACCENT_BRIGHT = '#B39DFF';

/** Prompt / surface node palette — same hues as upstream, reordered so violet leads */
export const FORK_PROMPT_COLORS = [
  '#B39DFF', // violet (fork accent family)
  '#FF4C8D', // rose
  '#FFC23C', // yellow
  '#7FB2FF', // light blue
  '#AE5CFF', // lavender
  '#7C89FF', // periwinkle
  '#FF70F9', // pink
  '#81D5FA', // sky blue
];
