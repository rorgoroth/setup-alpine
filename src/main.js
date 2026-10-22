const { spawnSync } = require('node:child_process');
const path = require('node:path');

if (process.platform !== 'linux' || process.arch !== 'x64') {
  console.log(
    `::error title=setup-alpine::Only x86_64 Linux runners are supported, ` +
    `but this runner is ${process.platform}/${process.arch}.`
  );
  process.exit(1);
}

// The runner exposes inputs as INPUT_<NAME> with hyphens preserved (e.g. INPUT_APK-TOOLS-URL),
// which can't be referenced from Bash, so rename hyphens to underscores.
const env = {};
for (const [key, value] of Object.entries(process.env)) {
  env[key.startsWith('INPUT_') ? key.replaceAll('-', '_') : key] = value;
}

const actionPath = path.resolve(__dirname, '..');

const result = spawnSync('sudo', ['-E', path.join(actionPath, 'setup-alpine.sh')], {
  cwd: actionPath,
  env,
  stdio: 'inherit',
});

if (result.error) {
  console.error(`setup-alpine: failed to start setup script: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
