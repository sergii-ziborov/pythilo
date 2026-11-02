# Pythilo Git core

Official libgit2 1.9.7 source, pinned by `upstream-manifest.json`, taken from
Crabrix's native Git core with its 211-source Apple build profile: SecureTransport,
collision-detecting SHA-1, system zlib and iconv. COPYING holds GPLv2 and the
upstream linking exception; dependency notices keep their original terms. SSH,
hooks and the command-line tools are not part of this build.

`Sources/PythiloGit` is Pythilo's own service. Unlike Crabrix, which keeps Git data
outside its text-only project snapshots, it works on an ordinary worktree with a
real `.git` folder, so a project copied to a computer is a normal repository.
Credentials are transient inputs; the app keeps them in the Keychain.
