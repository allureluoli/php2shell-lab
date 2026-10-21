# Repository metadata (copy-paste for GitHub)

## About / description (pick one)

**Balanced (recommended):**
```
php2shell (CVE-2026-109618/619) differential lab: ASAN builds of PHP 8.4.26 vs 8.4.27, one two-request trigger, automatic crash/no-crash verdict. Reproduces the fixed state-corruption bug — not RCE.
```

**Technical:**
```
Source-built PHP 8.4.26 vs 8.4.27 under ASAN. Pre-RINIT OOM leaves a stale serialize context; the next request reuses it. Differential harness, evidence logs, and hands-on verdicts on every circulating php2shell PoC.
```

**Defensive:**
```
Verify the php2shell fixes yourself: 8.4.26 crashes, 8.4.27 doesn't, same request. Differential harness + recorded evidence + an honest review of what the public PoCs actually do.
```

**Chinese:**
```
php2shell（CVE-2026-109618/619）差分复现：ASAN 编译 PHP 8.4.26 与 8.4.27，同一触发序列自动判定崩/不崩；附流传 PoC 的逐个实测定性（非 RCE）。
```

## Topics

```
php, security-research, php2shell, cve-2026-109618, cve-2026-109619, addresssanitizer, differential-testing, vulnerability-reproduction, session-upload-progress, lab
```

## Social preview

Upload `assets/social-preview.png` (1280×640) in *Settings → Social preview*.
If it is missing, render it from `assets/demo.svg`:

```bash
magick -background '#0d1117' assets/demo.svg -resize 1280x640 assets/social-preview.png
```

## First release

`v1.0.0` — "differential reproduction + PoC review". Attach nothing; the source
is the artifact.
