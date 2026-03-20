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
      choices: ['react', 'next', 'vue', 'nuxt', 'svelte', 'other'],
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
      choices: ['tailwindcss', 'css', 'sass', 'styled-components', 'emotion', 'other'],
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
      choices: ['zustand', 'redux', 'jotai', 'recoil', 'mobx', 'pinia', 'none'],
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
