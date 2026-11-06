# Engine source delivery

The store candidate contains independently licensed native components. The project's Apache-2.0 license does not relicense those components.

`collect-engine-sources.py` uses the bundled native component inventory and exact installed recipes to collect upstream archives, resources and patches with their expected hashes. `collect-source-notices.py` copies readable notices into the app before signing. `package-engine-sources.py` assembles the verified archives, recipes, firmware source/configuration, QEMouse source, display-agent source and build scripts without guest disks or signing credentials.

Example, after candidate export:

```sh
python3 scripts/package-engine-sources.py \
  --sources build/store-sources \
  --app /absolute/path/to/exported/DosMac.app \
  --output build/DosMac-source-evidence.tar.gz
```

The archive's index records member hashes and the project revision. Rehash its members before publishing it. Keep the source download available alongside the corresponding distributed build; record its public URL and the package hash in the release notes and in-app source information. Source packages contain no DOS/Windows installation media or product keys.

For native builds, use the included exact Homebrew recipes in an isolated build environment, retaining their versioned upstream inputs and patch locations. The recipes specify build commands and dependencies; source collection does not reproduce the toolchain or establish bit-identical binaries. Use the included `build-win9x-bios.py` for the custom firmware, the QEMouse upstream Makefile/readme with Open Watcom for that driver, and `build-guest-agent.py` for the original display agent. Use `build-store-candidate.sh` in a checkout of the recorded DosMac revision to assemble and sign the host app.

Before distributing a binary, check that its component versions and recipe hashes match the source inventory, the firmware source/configuration matches its build manifest, and the actual component terms and source-delivery requirements have been satisfied. The current evidence archive retains the collector's open complete-source review flags. It is a review artifact, not a certification of App Store license compatibility or complete corresponding source.
