// Ralph Wiggum - UI & Theming Module
// Simpsons-inspired color palette with helpers for consistent CLI output

const path = require('path');

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

function debug(msg) {
  if (process.env.RALPH_DEBUG === '1') {
    console.log(`${theme.muted}  [debug] ${msg}${codes.reset}`);
  }
}

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

function box(lines) {
  const stripped = lines.map(l => stripAnsi(l));
  const maxLen = Math.max(...stripped.map(s => s.length), 0);
  const w = maxLen + 2;

  console.log(`${theme.muted}  ┌${'─'.repeat(w)}┐${codes.reset}`);
  for (let i = 0; i < lines.length; i++) {
    const pad = w - 2 - stripped[i].length;
    console.log(`${theme.muted}  │${codes.reset} ${lines[i]}${' '.repeat(Math.max(pad, 0))} ${theme.muted}│${codes.reset}`);
  }
  console.log(`${theme.muted}  └${'─'.repeat(w)}┘${codes.reset}`);
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
  let version = '0.0.0';
  try {
    const pkg = require(path.resolve(__dirname, '../../package.json'));
    version = pkg.version;
  } catch {}

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
  if (config.insights) configLines.push(`${theme.muted}  insights${codes.reset}    ${config.insights}`);

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
  afterPlan: 'Next: run "ralph build <spec>" to start implementing the plan.',
  afterBuild: 'Next: run "ralph review <spec>" to review the implementation.',
  afterReview: 'Next: run "ralph review-fix <spec>" to fix review issues.',
  afterFull: 'Check the branch for results: git fetch origin && git checkout ralph/<spec>',
  noSpecs: 'Create a spec with: ralph spec <feature-name>',
  envMissing: 'Run "ralph init" to configure credentials.',
  backgroundMode: 'Press Enter for commands (status, steer, pause). Ctrl+C to stop.',
  interactiveShortcuts: 'Tip: Use "ralph <mode> <spec> -y" to skip prompts.',
  dockerMissing: 'Install Docker: https://docs.docker.com/get-docker/',
};

function hint(key) {
  const msg = hints[key];
  if (msg) {
    console.log(`${theme.muted}  Tip: ${msg}${codes.reset}`);
  }
}

function showPostRunHints(mode) {
  const map = {
    plan: 'afterPlan',
    build: 'afterBuild',
    review: 'afterReview',
    'review-fix': 'afterReview',
    full: 'afterFull',
  };
  const key = map[mode];
  if (key) {
    console.log('');
    hint(key);
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
  debug,
  step,
  header,
  separator,
  box,
  createSpinner,
  printRalph,
  startupBanner,
  hints,
  hint,
  showPostRunHints,
  RALPH_ASCII,
};
