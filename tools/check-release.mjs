import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, lstatSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const excludedDirectories = new Set(['.git', 'vendor', 'node_modules', '.dart_tool', 'build', 'Pods']);
function walk(directory) {
    return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const path = join(directory, entry.name);
        if (entry.isDirectory()) return excludedDirectories.has(entry.name) ? [] : walk(path);
        return [relative(root, path)];
    });
}

const files = existsSync(join(root, '.git'))
    ? execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean)
    : walk(root);
const issues = [];
const privateFile = /(?:\.sqlite(?:3)?(?:-.*)?|\.db(?:-.*)?|\.sql|\.dump|\.log|\.zip|\.tgz|\.tar(?:\.gz)?|\.bak|\.pem|\.crt|\.key|\.p8|\.p12|\.mobileprovision|\.jks|\.keystore|\.apk|\.aab|\.ipa)$/i;
const checks = [
    ['private key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
    ['GitHub access token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b/],
    ['AWS access key', /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/],
    ['machine-specific user path', /(?:^|[\s"'=:\x60])\/(?:Users|home)\/[A-Za-z0-9._-]+\//m],
    ['personal Apple signing team', /DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*;/],
];
for (const file of files) {
    const path = join(root, file);
    if (!existsSync(path)) continue;
    if (lstatSync(path).isSymbolicLink()) {
        issues.push(`${file}: symlink requires manual review`);
        continue;
    }
    const basename = file.split('/').at(-1);
    if (privateFile.test(file) || (basename.startsWith('.env') && basename !== '.env.example') ||
        /(?:^|\/)(?:auth\.json|local\.properties|key\.properties|development\.json|production\.json)$/.test(file)) {
        issues.push(`${file}: private/runtime file`);
        continue;
    }
    if (file.endsWith('tools/check-release.mjs')) continue;
    const bytes = readFileSync(path);
    if (bytes.includes(0)) continue;
    const text = bytes.toString('utf8');
    for (const [label, pattern] of checks) {
        if (pattern.test(text)) issues.push(`${file}: ${label}`);
    }
}
if (issues.length) {
    console.error(issues.join('\n'));
    process.exitCode = 1;
} else {
    console.log(`Release check passed: ${files.length} source files scanned.`);
}
