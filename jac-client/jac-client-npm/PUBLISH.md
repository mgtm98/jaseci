# How to Publish jac-client to npm

This guide explains how to publish the `jac-client` npm package.

## Prerequisites

1. **npm account**: You need an npm account. Create one at [npmjs.com](https://www.npmjs.com/signup)
2. **npm CLI**: Make sure you have npm installed (comes with Node.js)
3. **Login**: You must be logged in to npm

## Step 1: Login to npm

```bash
npm login
```

Enter your npm username, password, and email when prompted. If you have 2FA enabled, you'll need to enter the OTP code.

To verify you're logged in:
```bash
npm whoami
```

## Step 2: Verify Package Configuration

Before publishing, make sure your `package.json` is correct:

- ✅ Package name is `jac-client`
- ✅ Version number is correct (e.g., `0.1.0`)
- ✅ All required fields are filled (description, author, license, etc.)

## Step 3: Test the Package Locally (Optional but Recommended)

Test the package locally before publishing:

```bash
# In the jac-client-npm directory
npm link

# In another project where you want to test
npm link jac-client
```

Then test importing and using the functions in your test project.

## Step 4: Build/Prepare (if needed)

Currently, the package doesn't require a build step since it's plain JavaScript. However, if you add build steps later:

```bash
npm run build  # If you add a build script
```

## Step 5: Check What Will Be Published

Verify which files will be included in the package:

```bash
npm pack --dry-run
```

This shows you what files will be included. The `files` field in `package.json` controls this.

## Step 6: Publish to npm

### For First Time Publishing

```bash
npm publish
```

### For Updates (Version Bump Required)

Before publishing updates, you need to bump the version:

**Option 1: Manual version bump**
```bash
# Edit package.json to increment version (e.g., 0.1.0 -> 0.1.1)
npm publish
```

**Option 2: Use npm version command**
```bash
# Patch version (0.1.0 -> 0.1.1)
npm version patch
npm publish

# Minor version (0.1.0 -> 0.2.0)
npm version minor
npm publish

# Major version (0.1.0 -> 1.0.0)
npm version major
npm publish
```

## Step 7: Verify Publication

After publishing, verify the package is available:

1. Visit: `https://www.npmjs.com/package/jac-client`
2. Or check via CLI:
   ```bash
   npm view jac-client
   ```

## Publishing to a Different Registry

### Publish to GitHub Packages

If you want to publish to GitHub Packages instead:

1. Update `package.json`:
   ```json
   {
     "publishConfig": {
       "registry": "https://npm.pkg.github.com"
     }
   }
   ```

2. Login to GitHub Packages:
   ```bash
   npm login --registry=https://npm.pkg.github.com
   ```

3. Publish:
   ```bash
   npm publish
   ```

### Publish to a Private Registry

For a private npm registry:

1. Configure registry in `.npmrc`:
   ```
   registry=https://your-registry.com
   ```

2. Login and publish as usual.

## Troubleshooting

### Error: "You do not have permission to publish"

- Make sure you're logged in: `npm whoami`
- Check if the package name is already taken: `npm view jac-client`
- If taken, you'll need to use a scoped package name like `@your-org/jac-client`

### Error: "Package name too similar"

npm may reject names that are too similar to existing packages. Consider:
- Using a scoped package: `@jac-client/runtime`
- Adding a suffix: `jac-client-runtime`

### Error: "Version already exists"

You're trying to publish a version that already exists. Bump the version number first.

### Unpublishing (if needed)

⚠️ **Warning**: Unpublishing can break projects that depend on your package. Only do this if absolutely necessary and within 72 hours of publishing.

```bash
npm unpublish jac-client@0.1.0  # Unpublish specific version
npm unpublish jac-client --force # Unpublish entire package (dangerous!)
```

## Best Practices

1. **Versioning**: Follow [Semantic Versioning](https://semver.org/)
   - MAJOR.MINOR.PATCH (e.g., 1.2.3)
   - MAJOR: Breaking changes
   - MINOR: New features (backward compatible)
   - PATCH: Bug fixes

2. **Testing**: Always test locally before publishing

3. **Changelog**: Consider maintaining a CHANGELOG.md file

4. **Git Tags**: Tag releases in git:
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

5. **README**: Keep README.md up to date with usage examples

## Quick Reference

```bash
# Login
npm login

# Check current user
npm whoami

# Preview what will be published
npm pack --dry-run

# Bump version and publish
npm version patch && npm publish

# View published package
npm view jac-client

# Install the published package
npm install jac-client
```

## Next Steps After Publishing

1. Update the main jac-client README to mention the npm package
2. Add installation instructions to documentation
3. Consider setting up CI/CD to automate publishing on releases
4. Monitor the package for issues and user feedback

