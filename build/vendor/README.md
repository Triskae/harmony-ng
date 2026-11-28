# Vendored sources

Third-party sources the firmware build needs, kept in the repository so that a build and the
test suite never download them. Each one is the upstream publication, unchanged.

## BearSSL

| | |
|---|---|
| Folder | `build/vendor/bearssl/` |
| Upstream | https://bearssl.org/git/BearSSL |
| Commit | `7bea48e5e850ab4cafbe68d3765cdaba13a86d6f` (2026-04-06) |
| Git tree of that commit | `a8f933a27b14eaf3a348fe9b294bf4262dbb216c` |
| Licence | MIT (`bearssl/LICENSE.txt`) |

The folder is `git archive` of that commit: every file, mode and line ending as upstream has it
(`.gitattributes` turns off line ending conversion for it). `tests/test_build_downloads.sh`
checks that its git tree is the tree above. `build/fetch_bearssl.sh` copies it into
`build/tmp/bearssl` for the builds; `BEARSSL_FETCH=1` clones upstream instead.

The commit is part of the plugin ABI (see `build/fetch_bearssl.sh`). To move to another commit:

```bash
git clone https://bearssl.org/git/BearSSL /tmp/bearssl
git -C /tmp/bearssl rev-parse <commit>^{tree}     # the new tree id
rm -rf build/vendor/bearssl && mkdir build/vendor/bearssl
git -C /tmp/bearssl archive <commit> | tar -x -C build/vendor/bearssl
git add -f build/vendor/bearssl                   # -f: BearSSL's own .gitignore hides build/.do_not_remove
```

then change `BEARSSL_COMMIT` and `BEARSSL_TREE` in `build/fetch_bearssl.sh`, the SONAME in
`build/compile_all.sh`, and the table above.
