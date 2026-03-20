const fs = require('fs');
const path = require('path');

const MAX_FILE_COUNT = 5000; // Cap to avoid blocking on monorepos

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
  // Note: if multiple lockfiles exist (e.g. after migration), first match wins.
  // The user can correct this during the interactive confirmation step.
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

    // Framework detection (ordered by specificity — meta-frameworks before base frameworks)
    if (allDeps['next']) result.framework = 'next';
    else if (allDeps['@remix-run/react'] || allDeps['remix']) result.framework = 'remix';
    else if (allDeps['nuxt']) result.framework = 'nuxt';
    else if (allDeps['astro']) result.framework = 'astro';
    else if (allDeps['vue']) result.framework = 'vue';
    else if (allDeps['svelte'] || allDeps['@sveltejs/kit']) result.framework = 'svelte';
    else if (allDeps['solid-js']) result.framework = 'solid';
    else if (allDeps['@angular/core']) result.framework = 'angular';
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
    else if (allDeps['@vanilla-extract/css']) result.styling = 'vanilla-extract';
    else if (allDeps['unocss']) result.styling = 'unocss';
    else if (allDeps['sass'] || allDeps['node-sass']) result.styling = 'sass';
    else if (hasCSSModules(cwd)) result.styling = 'css-modules';
    else result.styling = 'css';

    // Test runner detection
    if (allDeps['vitest']) result.testRunner = 'vitest';
    else if (allDeps['jest']) result.testRunner = 'jest';
    else if (allDeps['mocha']) result.testRunner = 'mocha';

    // E2E runner detection
    if (allDeps['playwright'] || allDeps['@playwright/test']) result.e2eRunner = 'playwright';
    else if (allDeps['cypress']) result.e2eRunner = 'cypress';

    // State management detection
    if (allDeps['@tanstack/react-query']) result.stateManagement = 'react-query';
    else if (allDeps['zustand']) result.stateManagement = 'zustand';
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

  // Project maturity — count source files across common directory names
  const sourceDirs = ['src', 'app', 'pages', 'lib', 'components'];
  let totalFiles = 0;
  for (const dir of sourceDirs) {
    const fullDir = path.join(cwd, dir);
    if (fs.existsSync(fullDir)) {
      totalFiles += countFiles(fullDir, MAX_FILE_COUNT - totalFiles);
      if (totalFiles >= MAX_FILE_COUNT) break;
    }
  }
  result.projectMaturity = totalFiles > 10 ? 'established' : 'new';

  // Check for existing pipeline files (to warn before overwriting)
  const pipelineFiles = [
    'CLAUDE.md', 'GEMINI.md', 'AGENTS.md', 'CONTEXT.md',
    'pipeline/config.json',
    'pipeline/scripts/dev-loop.sh', 'pipeline/scripts/setup.sh', 'pipeline/scripts/generate-context.sh',
  ];
  result.existingFiles = pipelineFiles.filter(f => fs.existsSync(path.join(cwd, f)));

  return result;
}

function countFiles(dir, remaining) {
  let count = 0;
  if (remaining <= 0) return count;
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
      if (entry.isFile()) {
        count++;
        if (count >= remaining) return count;
      } else if (entry.isDirectory()) {
        count += countFiles(path.join(dir, entry.name), remaining - count);
        if (count >= remaining) return count;
      }
    }
  } catch (e) {
    // permission error or similar, skip
  }
  return count;
}

/**
 * Check if the project uses CSS Modules by looking for .module.css files in src/
 */
function hasCSSModules(cwd) {
  const srcDir = path.join(cwd, 'src');
  if (!fs.existsSync(srcDir)) return false;
  try {
    return findFileWithPattern(srcDir, /\.module\.css$/, 3);
  } catch (e) {
    return false;
  }
}

function findFileWithPattern(dir, pattern, maxDepth) {
  if (maxDepth <= 0) return false;
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
      if (entry.isFile() && pattern.test(entry.name)) return true;
      if (entry.isDirectory() && findFileWithPattern(path.join(dir, entry.name), pattern, maxDepth - 1)) return true;
    }
  } catch (e) {
    // skip
  }
  return false;
}

module.exports = { detect };
