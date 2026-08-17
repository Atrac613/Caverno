# Caverno 1.3.17+29

## What's New

### Composer Controls

- Added a single composer chip for selecting the model and reasoning effort.
- Added suggested composer shortcut buttons after each turn.
- Moved the context usage ring below the composer for a clearer layout.

### Skills and SSH

- Added a prebuilt skill catalog when adding a skill.
- Added SSH host connections using a key and the user's `ssh_config`.

### Release Distribution

- Added signing configuration for iOS App Store and macOS Developer ID releases.

## Bug Fixes

- Showed the start-in selector only before a thread runs.
- Kept the tool loop accurate about what it actually ran and changed.
- Kept loaded skills visible for the remainder of the turn.
- Prevented claim notices from deleting the answer they annotate.
- Routed background job observation to the process handler and kept background jobs alive after the turn that started them.

## Performance and Maintenance

- Raised the `process_wait` floor to match the cost of a polling operation.
- Updated `serious_python_darwin` to `4.5.1`.

## Technical Details

- Version: `1.3.17+29`
- Platforms: iOS, macOS
- Source: Git history through commit `54284f3`
