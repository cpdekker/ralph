// ANSI color helpers
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

const c = (color, text) => `${codes[color]}${text}${codes.reset}`;

function success(msg) { console.log(c('green', `  ✓ ${msg}`)); }
function warn(msg) { console.log(c('yellow', `  ⚠ ${msg}`)); }
function error(msg) { console.log(c('red', `  ✗ ${msg}`)); }
function info(msg) { console.log(c('dim', `    ${msg}`)); }
function step(n, total, desc) {
  console.log('');
  console.log(c('cyan', `  [${n}/${total}] ${desc}`));
  console.log(c('dim', '  ' + '─'.repeat(40)));
}

function createSpinner(message) {
  const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  let i = 0;
  const startTime = Date.now();

  const interval = setInterval(() => {
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    const minutes = Math.floor(elapsed / 60);
    const seconds = elapsed % 60;
    const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
    process.stdout.write(`\r  ${c('cyan', frames[i])} ${message} ${c('dim', `(${timeStr})`)}`);
    i = (i + 1) % frames.length;
  }, 80);

  return {
    stop: (ok = true) => {
      clearInterval(interval);
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      const minutes = Math.floor(elapsed / 60);
      const seconds = elapsed % 60;
      const timeStr = minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
      process.stdout.write('\r' + ' '.repeat(80) + '\r');
      if (ok) {
        console.log(`  ${c('green', '✓')} ${message} ${c('dim', `(${timeStr})`)}`);
      } else {
        console.log(`  ${c('red', '✗')} ${message} ${c('dim', `(${timeStr})`)}`);
      }
    },
  };
}

module.exports = { c, codes, success, warn, error, info, step, createSpinner };
