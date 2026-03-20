const fs = require('fs');
const path = require('path');

function detect(cwd) {
  const result = {
    framework: null,
    language: null,
    styling: null,
    testRunner: null,
    e2eRunner: null,
    stateManagement: null,
    packageManager: null,
    commands: { test: null, lint: null, typeCheck: null, dev: null },
    projectMaturity: 'new', // new | established
    existingFiles: [],
  };

  // Detect package manager
  if (fs.existsSync(path.join(cwd, 'pnpm-lock.yaml'))) {
    result.packageManager = 'pnpm';
  } else if (fs.existsSync(path.join(cwd, 'yarn.lock'))) {
    result.packageManager = 'yarn';
  } else if (fs.existsSync(path.join(cwd, 'bun.lockb'))) {
    result.packageManager = 'bun';
  } else {
    result.packageManager = 'npm';
  }

  // Read package.json
  const pkgPath = path.join(cwd, 'package.json');
  let pkg = null;
  if (fs.existsSync(pkgPath)) {
    try {
      pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    } catch (e) {
      // malformed package.json, proceed without it
    }
  }

  if (pkg) {
    const allDeps = {
      ...(pkg.dependencies || {}),
      ...(pkg.devDependencies || {}),
    };

    // Framework detection
    if (allDeps['next']) result.framework = 'next';
    else if (allDeps['nuxt']) result.framework = 'nuxt';
    else if (allDeps['vue']) result.framework = 'vue';
    else if (allDeps['svelte'] || allDeps['@sveltejs/kit']) result.framework = 'svelte';
    else if (allDeps['react']) result.framework = 'react';

    // Language detection
    if (allDeps['typescript'] || fs.existsSync(path.join(cwd, 'tsconfig.json'))) {
      result.language = 'typescript';
    } else {
      result.language = 'javascript';
    }

    // Styling detection
    if (allDeps['tailwindcss']) result.styling = 'tailwindcss';
    else if (allDeps['styled-components']) result.styling = 'styled-components';
    else if (allDeps['@emotion/react']) result.styling = 'emotion';
    else if (allDeps['sass'] || allDeps['node-sass']) result.styling = 'sass';
    else result.styling = 'css';

    // Test runner detection
    if (allDeps['vitest']) result.testRunner = 'vitest';
    else if (allDeps['jest']) result.testRunner = 'jest';
    else if (allDeps['mocha']) result.testRunner = 'mocha';

    // E2E runner detection
    if (allDeps['playwright'] || allDeps['@playwright/test']) result.e2eRunner = 'playwright';
    else if (allDeps['cypress']) result.e2eRunner = 'cypress';

    // State management detection
    if (allDeps['zustand']) result.stateManagement = 'zustand';
    else if (allDeps['@reduxjs/toolkit'] || allDeps['redux']) result.stateManagement = 'redux';
    else if (allDeps['jotai']) result.stateManagement = 'jotai';
    else if (allDeps['recoil']) result.stateManagement = 'recoil';
    else if (allDeps['mobx']) result.stateManagement = 'mobx';
    else if (allDeps['pinia']) result.stateManagement = 'pinia';

    // Commands from scripts
    const scripts = pkg.scripts || {};
    const pm = result.packageManager;
    const run = pm === 'npm' ? 'npm run' : pm;

    if (scripts.test) result.commands.test = `${run} test`;
    if (scripts.lint) result.commands.lint = `${run} lint`;
    if (scripts.dev) result.commands.dev = `${run} dev`;
    else if (scripts.start) result.commands.dev = `${run} start`;

    // Type check command
    if (result.language === 'typescript') {
      if (scripts.typecheck) result.commands.typeCheck = `${run} typecheck`;
      else if (scripts['type-check']) result.commands.typeCheck = `${run} type-check`;
      else result.commands.typeCheck = 'npx tsc --noEmit';
    }
  }

  // Project maturity — count source files
  const srcDir = path.join(cwd, 'src');
  if (fs.existsSync(srcDir)) {
    const count = countFiles(srcDir);
    result.projectMaturity = count > 10 ? 'established' : 'new';
  }

  // Check for existing pipeline files (to warn before overwriting)
  const pipelineFiles = [
    'CLAUDE.md', 'GEMINI.md', 'AGENTS.md', 'CONTEXT.md',
    'pipeline.config.json',
    'scripts/dev-loop.sh', 'scripts/setup.sh', 'scripts/generate-context.sh',
  ];
  result.existingFiles = pipelineFiles.filter(f => fs.existsSync(path.join(cwd, f)));

  return result;
}

function countFiles(dir) {
  let count = 0;
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
      if (entry.isFile()) count++;
      else if (entry.isDirectory()) count += countFiles(path.join(dir, entry.name));
    }
  } catch (e) {
    // permission error or similar, skip
  }
  return count;
}

module.exports = { detect };
