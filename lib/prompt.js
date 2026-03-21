const { prompt } = require('enquirer');

async function confirmDetection(detected) {
  const techStack = [
    detected.framework,
    detected.language,
    detected.testRunner,
    detected.e2eRunner,
    detected.styling,
    detected.stateManagement,
  ].filter(Boolean);

  console.log('\n  Detected tech stack:');
  console.log(`    ${techStack.join(', ') || '(nothing detected — is there a package.json?)'}`);
  console.log('');

  const { correct } = await prompt({
    type: 'confirm',
    name: 'correct',
    message: 'Is the detected tech stack correct?',
    initial: true,
  });

  let config = { ...detected };

  if (!correct) {
    config = await askTechStack(detected);
  }

  // Confirm commands
  console.log('\n  Detected commands:');
  if (config.commands.test) console.log(`    Test:       ${config.commands.test}`);
  if (config.commands.lint) console.log(`    Lint:       ${config.commands.lint}`);
  if (config.commands.typeCheck) console.log(`    Type check: ${config.commands.typeCheck}`);
  if (config.commands.dev) console.log(`    Dev server: ${config.commands.dev}`);
  console.log('');

  const { commandsCorrect } = await prompt({
    type: 'confirm',
    name: 'commandsCorrect',
    message: 'Are these commands correct?',
    initial: true,
  });

  if (!commandsCorrect) {
    config.commands = await askCommands(config);
  }

  // Ask for custom conventions
  const { conventions } = await prompt({
    type: 'input',
    name: 'conventions',
    message: 'Any additional team conventions? (press Enter to skip)',
  });
  config.customConventions = conventions || '';

  // Ask about project size (affects complexity thresholds)
  const { projectSize } = await prompt({
    type: 'select',
    name: 'projectSize',
    message: 'Feature size per pipeline run:',
    choices: [
      { name: 'small', message: 'Small (1-2 screens, 3 components, 250 lines)' },
      { name: 'medium', message: 'Medium (3-4 screens, 5 components, 500 lines)' },
      { name: 'large', message: 'Large (5-8 screens, 10 components, 1000 lines)' },
    ],
    initial: 'medium',
  });
  config.projectSize = projectSize;

  // Ask about model preferences
  console.log('\n  Model configuration (passed as --model to each CLI tool):');
  const models = await prompt([
    {
      type: 'input',
      name: 'claude',
      message: 'Claude model:',
      initial: 'sonnet',
    },
    {
      type: 'input',
      name: 'gemini',
      message: 'Gemini model:',
      initial: 'gemini-2.5-pro',
    },
    {
      type: 'input',
      name: 'qwen',
      message: 'Qwen model:',
      initial: 'qwen3-coder-plus',
    },
  ]);
  config.models = models;

  // Ask about bootstrapping
  if (config.projectMaturity === 'established') {
    const { bootstrap } = await prompt({
      type: 'confirm',
      name: 'bootstrap',
      message: 'Established codebase detected. Run doc bootstrap after setup? (scans codebase to generate docs/)',
      initial: true,
    });
    config.runBootstrap = bootstrap;
  } else {
    config.runBootstrap = false;
  }

  return config;
}

async function askTechStack(defaults) {
  const answers = await prompt([
    {
      type: 'select',
      name: 'framework',
      message: 'Framework:',
      choices: ['react', 'next', 'remix', 'vue', 'nuxt', 'svelte', 'solid', 'astro', 'angular', 'other'],
      initial: defaults.framework || 'react',
    },
    {
      type: 'select',
      name: 'language',
      message: 'Language:',
      choices: ['typescript', 'javascript'],
      initial: defaults.language || 'typescript',
    },
    {
      type: 'select',
      name: 'styling',
      message: 'Styling:',
      choices: ['tailwindcss', 'css', 'css-modules', 'sass', 'styled-components', 'emotion', 'vanilla-extract', 'unocss', 'other'],
      initial: defaults.styling || 'tailwindcss',
    },
    {
      type: 'select',
      name: 'testRunner',
      message: 'Test runner:',
      choices: ['vitest', 'jest', 'mocha', 'none'],
      initial: defaults.testRunner || 'vitest',
    },
    {
      type: 'select',
      name: 'e2eRunner',
      message: 'E2E test runner:',
      choices: ['playwright', 'cypress', 'none'],
      initial: defaults.e2eRunner || 'playwright',
    },
    {
      type: 'select',
      name: 'stateManagement',
      message: 'State management:',
      choices: ['react-query', 'zustand', 'redux', 'jotai', 'recoil', 'mobx', 'pinia', 'none'],
      initial: defaults.stateManagement || 'zustand',
    },
  ]);

  return {
    ...defaults,
    ...answers,
    stateManagement: answers.stateManagement === 'none' ? null : answers.stateManagement,
    testRunner: answers.testRunner === 'none' ? null : answers.testRunner,
    e2eRunner: answers.e2eRunner === 'none' ? null : answers.e2eRunner,
  };
}

async function askCommands(config) {
  const pm = config.packageManager || 'npm';
  const run = pm === 'npm' ? 'npm run' : pm;

  const answers = await prompt([
    {
      type: 'input',
      name: 'test',
      message: 'Test command:',
      initial: config.commands.test || `${run} test`,
    },
    {
      type: 'input',
      name: 'lint',
      message: 'Lint command:',
      initial: config.commands.lint || `${run} lint`,
    },
    {
      type: 'input',
      name: 'typeCheck',
      message: 'Type check command:',
      initial: config.commands.typeCheck || 'npx tsc --noEmit',
    },
    {
      type: 'input',
      name: 'dev',
      message: 'Dev server command:',
      initial: config.commands.dev || `${run} dev`,
    },
  ]);

  return answers;
}

module.exports = { confirmDetection };
