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

// `sudo -E` can't be used to hand the environment to the setup script: sudo-rs, the default
// `sudo` since Ubuntu 25.10 (and so on `ubuntu-latest` = 26.04), ignores it and runs the command
// with a reset environment. Instead run the script via `env` (as the command, so no SETENV
// permission is needed), which works the same with sudo-rs and the original sudo.
// Only what the script reads is passed: the action's inputs plus the runner/workflow variables.
const passEnv = Object.entries(env)
  .filter(([key]) => /^(INPUT_|GITHUB_|RUNNER_)/.test(key) && !key.includes('='))
  .map(([key, value]) => `${key}=${value}`);

const result = spawnSync('sudo', ['env', ...passEnv, path.join(actionPath, 'setup-alpine.sh')], {
  cwd: actionPath,
  env,
  stdio: 'inherit',
});

if (result.error) {
  console.error(`setup-alpine: failed to start setup script: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
