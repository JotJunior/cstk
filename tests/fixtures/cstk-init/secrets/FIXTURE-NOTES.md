# Fixture notes

The symlink that escapes the project root (Scenario 17) is NOT versioned: the test
creates it at runtime with `ln -s <outside-dir> link-out`, so the repository never
contains a link to a path outside itself.
