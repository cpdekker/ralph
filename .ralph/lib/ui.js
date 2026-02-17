// Ralph Wiggum - Standalone UI Module (portable)
// Self-contained — no dependency on the npm package's lib/utils/colors.js
// Simpsons-inspired color palette with helpers for consistent CLI output

// ═══════════════════════════════════════════════════════════════════════════════
// ANSI CODES
// ═══════════════════════════════════════════════════════════════════════════════

const codes = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  white: '\x1b[37m',
};

// ═══════════════════════════════════════════════════════════════════════════════
// SIMPSONS THEME — semantic color roles
// ═══════════════════════════════════════════════════════════════════════════════

const theme = {
  brand:     '\x1b[33m',       // Simpsons Yellow — branding, titles
  primary:   '\x1b[34m',       // Marge Blue — info, prompts
  success:   '\x1b[32m',       // Springfield Green — checkmarks, success
  error:     '\x1b[31m',       // Bart Red — errors, failures
  warning:   '\x1b[33m',       // Homer Orange/Yellow — warnings
  accent:    '\x1b[35m',       // Krusty Magenta — headers, emphasis
  muted:     '\x1b[2m',        // Dim — hints, secondary text
  highlight: '\x1b[1;37m',     // Bright White — emphasis in dim context
};

// ═══════════════════════════════════════════════════════════════════════════════
// CORE HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

const c = (color, text) => `${codes[color] || ''}${text}${codes.reset}`;

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, '');
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

function success(msg) { console.log(`${theme.success}  \u2713 ${msg}${codes.reset}`); }
function warn(msg) { console.log(`${theme.warning}  \u26A0 ${msg}${codes.reset}`); }
function error(msg) { console.log(`${theme.error}  \u2717 ${msg}${codes.reset}`); }
function info(msg) { console.log(`${theme.muted}    ${msg}${codes.reset}`); }
function dim(msg) { console.log(`${theme.muted}${msg}${codes.reset}`); }

function step(n, total, desc) {
  console.log('');
  console.log(`${theme.primary}  [${n}/${total}] ${desc}${codes.reset}`);
  console.log(`${theme.muted}  ${'─'.repeat(40)}${codes.reset}`);
}

function header(msg) {
  console.log('');
  console.log(`${theme.accent}  ${msg}${codes.reset}`);
  console.log(`${theme.muted}  ${'─'.repeat(Math.max(stripAnsi(msg).length, 35))}${codes.reset}`);
  console.log('');
}

function separator() {
  console.log(`${theme.muted}  ${'─'.repeat(50)}${codes.reset}`);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPINNER
// ═══════════════════════════════════════════════════════════════════════════════

function createSpinner(message) {
  // Homer's donut being eaten — Simpsons-themed spinner
  const frames = ['(O)', '(O)', '(C)', '(c)', '(.)', '( )', '( )', '(o)'];
  let i = 0;
  const startTime = Date.now();

  const interval = setInterval(() => {
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    const minutes = Math.floor(elapsed / 60);
    const seconds = elapsed % 60;
    const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
    process.stdout.write(`\r  ${theme.brand}${frames[i]}${codes.reset} ${message} ${theme.muted}(${timeStr})${codes.reset}`);
    i = (i + 1) % frames.length;
  }, 200);

  return {
    stop: (ok = true) => {
      clearInterval(interval);
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      const minutes = Math.floor(elapsed / 60);
      const seconds = elapsed % 60;
      const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
      process.stdout.write('\r' + ' '.repeat(80) + '\r');
      if (ok) {
        console.log(`  ${theme.success}\u2713${codes.reset} ${message} ${theme.muted}(${timeStr})${codes.reset}`);
      } else {
        console.log(`  ${theme.error}\u2717${codes.reset} ${message} ${theme.muted}(${timeStr})${codes.reset}`);
      }
    },
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// ASCII ART RALPH WIGGUM
// ═══════════════════════════════════════════════════════════════════════════════

const RALPH_ASCII = [
  "⠀⠀⠀⠀⠀⠀⣀⣤⣶⡶⢛⠟⡿⠻⢻⢿⢶⢦⣄⡀",
  "⠀⠀⠀⢀⣠⡾⡫⢊⠌⡐⢡⠊⢰⠁⡎⠘⡄⢢⠙⡛⡷⢤⡀",
  "⠀⠀⢠⢪⢋⡞⢠⠃⡜⠀⠎⠀⠉⠀⠃⠀⠃⠀⠃⠙⠘⠊⢻⠦",
  "⠀⠀⢇⡇⡜⠀⠜⠀⠁⠀⢀⠔⠉⠉⠑⠄⠀⠀⡰⠊⠉⠑⡄⡇",
  "⠀⠀⡸⠧⠄⠀⠀⠀⠀⠀⠘⡀⠾⠀⠀⣸⠀⠀⢧⠀⠛⠀⠌⡇",
  "⠀⠘⡇⠀⠀⠀⠀⠀⠀⠀⠀⠙⠒⠒⠚⠁⠈⠉⠲⡍⠒⠈⠀⡇",
  "⠀⠀⠈⠲⣆⠀⠀⠀⠀⠀⠀⠀⠀⣠⠖⠉⡹⠤⠶⠁⠀⠀⠀⠈⢦",
  "⠀⠀⠀⠀⠈⣦⡀⠀⠀⠀⠀⠧⣴⠁⠀⠘⠓⢲⣄⣀⣀⣀⡤⠔⠃",
  "⠀⠀⠀⠀⣜⠀⠈⠓⠦⢄⣀⣀⣸⠀⠀⠀⠀⠁⢈⢇⣼⡁",
  "⠀⠀⢠⠒⠛⠲⣄⠀⠀⠀⣠⠏⠀⠉⠲⣤⠀⢸⠋⢻⣤⡛⣄",
  "⠀⠀⢡⠀⠀⠀⠀⠉⢲⠾⠁⠀⠀⠀⠀⠈⢳⡾⣤⠟⠁⠹⣿⢆",
  "⠀⢀⠼⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠃⠀⠀⠀⠀⠀⠈⣧",
  "⠀⡏⠀⠘⢦⡀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⠀⠀⢸⣧",
  "⢰⣄⠀⠀⠀⠉⠳⠦⣤⣤⡤⠴⠖⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢯⣆",
  "⢸⣉⠉⠓⠲⢦⣤⣄⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⣠⣼⢹⡄",
  "⠘⡍⠙⠒⠶⢤⣄⣈⣉⡉⠉⠙⠛⠛⠛⠛⠛⠛⢻⠉⠉⠉⢙⣏⣁⣸⠇⡇",
  "⠀⢣⠀⠀⠀⠀⠀⠀⠉⠉⠉⠙⠛⠛⠛⠛⠛⠛⠛⠒⠒⠒⠋⠉⠀⠸⠚⢇",
  "⠀⠀⢧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⠇⢤⣨⠇",
  "⠀⠀⠀⢧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣤⢻⡀⣸",
  "⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⠛⠉⠁",
  "⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⢠⢄⣀⣤⠤⠴⠒⠀⠀⠀⠀⢸",
  "⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠘⡆",
  "⠀⠀⠀⡎⠀⠀⠀⠀⠀⠀⠀⠀⢷⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⡇",
  "⠀⠀⢀⡷⢤⣤⣀⣀⣀⣀⣠⠤⠾⣤⣀⡘⠛⠶⠶⠶⠶⠖⠒⠋⠙⠓⠲⢤⣀",
  "⠀⠀⠘⠧⣀⡀⠈⠉⠉⠁⠀⠀⠀⠀⠈⠙⠳⣤⣄⣀⣀⣀⠀⠀⠀⠀⠀⢀⣈⡇",
  "⠀⠀⠀⠀⠀⠉⠛⠲⠤⠤⢤⣤⣄⣀⣀⣀⣀⡸⠇⠀⠀⠀⠉⠉⠉⠉⠉⠉⠁",
];

function printRalph() {
  for (const line of RALPH_ASCII) {
    console.log(`${theme.brand}  ${line}${codes.reset}`);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STARTUP BANNER
// ═══════════════════════════════════════════════════════════════════════════════

function startupBanner(config = {}) {
  const version = config.version || '0.0.0';

  console.log('');

  // Build config lines
  const configLines = [];
  configLines.push(`${theme.brand}Ralph Wiggum${codes.reset} ${theme.muted}v${version}${codes.reset}`);
  configLines.push('');
  if (config.cwd) configLines.push(`${theme.muted}  cwd${codes.reset}        ${config.cwd}`);
  if (config.spec) configLines.push(`${theme.muted}  spec${codes.reset}       ${config.spec}`);
  if (config.mode) configLines.push(`${theme.muted}  mode${codes.reset}       ${config.mode}`);
  if (config.iterations) configLines.push(`${theme.muted}  iterations${codes.reset}  ${config.iterations}`);
  if (config.verbose !== undefined) configLines.push(`${theme.muted}  verbose${codes.reset}     ${config.verbose}`);
  if (config.background !== undefined) configLines.push(`${theme.muted}  background${codes.reset}  ${config.background}`);
  if (config.branch) configLines.push(`${theme.muted}  branch${codes.reset}      ${config.branch}`);
  if (config.docker) configLines.push(`${theme.muted}  docker${codes.reset}      ${config.docker}`);

  // Use head portion (first 10 lines) for compact banner display
  const bannerArt = RALPH_ASCII.slice(0, 10);
  const artWidth = Math.max(...bannerArt.map(l => l.length)) + 2;

  // Print Ralph head side-by-side with config
  const maxLines = Math.max(bannerArt.length, configLines.length);

  for (let i = 0; i < maxLines; i++) {
    const artLine = i < bannerArt.length ? bannerArt[i].padEnd(artWidth) : ' '.repeat(artWidth);
    const cfgLine = i < configLines.length ? configLines[i] : '';
    console.log(`${theme.brand}  ${artLine}${codes.reset}${cfgLine}`);
  }

  separator();
  console.log('');
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTEXTUAL HINTS
// ═══════════════════════════════════════════════════════════════════════════════

const hints = {
  afterPlan: 'Next: run your spec through build mode to start implementing.',
  afterBuild: 'Next: run review mode to check the implementation.',
  afterReview: 'Next: run review-fix to address review issues.',
  noSpecs: 'Create a spec in .ralph/specs/<name>.md or use spec mode.',
  envMissing: 'Copy .ralph/.env.example to .ralph/.env and add your credentials.',
  backgroundMode: 'Ctrl+C stops Ralph. Container logs: docker logs -f <container>.',
};

function hint(key) {
  const msg = hints[key];
  if (msg) {
    console.log(`${theme.muted}  Tip: ${msg}${codes.reset}`);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

module.exports = {
  codes,
  theme,
  c,
  stripAnsi,
  success,
  warn,
  error,
  info,
  dim,
  step,
  header,
  separator,
  createSpinner,
  printRalph,
  startupBanner,
  hints,
  hint,
  RALPH_ASCII,
};
