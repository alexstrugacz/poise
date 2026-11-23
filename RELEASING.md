# Releasing Poise

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in [Resources/Info.plist](Resources/Info.plist). Keep the bundle identifier so Poise can read existing preferences.
2. Push to `main` and check that the build passes.
3. Tag that commit with the matching version and push the tag. For example, for version 1.0.3:

   ```sh
   git tag v1.0.3
   git push origin v1.0.3
   ```

GitHub Actions tests and builds the tagged source before publishing a [GitHub release](https://github.com/alexstrugacz/poise/releases). `bash scripts/update.sh` builds that release locally.

If a tag push doesn't start a build, open the [release workflow](https://github.com/alexstrugacz/poise/actions/workflows/release.yml), select **Run workflow**, and enter the existing tag.
