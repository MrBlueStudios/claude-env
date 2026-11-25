# Fetch recipes for /inbox

One recipe per link type. Each one fills the bundle (URL, meta title and description, text,
transcript or images, and the `fetch:` line). On any failure, keep what you have and say in the
`fetch:` line what is missing.

`UNSTABLE` = `github:NixOS/nixpkgs/nixos-unstable`. Video tools come from there, because this
laptop's system `nixpkgs` is 25.05, whose yt-dlp is a year old and breaks on TikTok and
Instagram.

## GitHub repo (`github.com/<owner>/<repo>`)

```sh
gh repo view <owner>/<repo> --json description,stargazerCount,licenseInfo,pushedAt,isArchived
gh api repos/<owner>/<repo>/readme --jq .content | base64 -d
git clone --depth 1 https://github.com/<owner>/<repo> <scratch>/repo
just -f ~/Projects/claude-env/justfile vet <scratch>/repo
```

`fetch: repo gh+readme+vet`

## Website or article (and anything not listed below)

`defuddle parse <url> --md` if defuddle is on PATH. Otherwise, or when it returns little:

```sh
curl -sL -H "DNT: 1" "https://r.jina.ai/<url>"
```

Jina only for public URLs. `fetch: web defuddle | web jina | web meta only`

## X post (`x.com`, `twitter.com`)

```sh
curl -s "https://publish.x.com/oembed?url=<url>&omit_script=1"
```

The post text is inside the `html` blockquote. Text only: no thread, no media.
`fetch: x oembed`

## Reddit, LinkedIn

The page's meta tags plus Jina Reader. Reddit's `.json` endpoints are dead (403). When both are
blocked: `fetch: <site> link only`, and judge on the title and the sharer's text.

## TikTok video (`tiktok.com/…/video/…`, `vm.tiktok.com/…`)

```sh
nix run UNSTABLE#yt-dlp -- --write-info-json --skip-download -o '<scratch>/%(id)s' <url>
nix run UNSTABLE#yt-dlp -- -x --audio-format mp3 -o '<scratch>/%(id)s.%(ext)s' <url>
nix run UNSTABLE#whisper-ctranslate2 -- --model small --compute_type int8 \
  --output_format txt --output_dir <scratch> <scratch>/<id>.mp3
```

The caption is `description` in the `.info.json`; the transcript is the `.txt`.
`fetch: tiktok yt-dlp+whisper`

A `/photo/` URL (a slideshow) is out of scope for v0. Judge the caption from the page meta and
write `fetch: tiktok slideshow caption only`.

## Instagram reel or post (`instagram.com/reel/…`, `/p/…`)

Climb the levels in order, stopping at the first that gives content. Record the level in the
`fetch:` line, because these counts decide whether a throwaway account is ever worth it.

- **L1. yt-dlp, logged out.** The TikTok commands with the Instagram URL. Add
  `--ignore-no-formats-error` (image carousels). `fetch: instagram L1 yt-dlp+whisper`
- **L2. The public page, logged out.** Read the caption from `og:description` on the reel
  page, or from `https://www.instagram.com/reel/<id>/embed/captioned/`. Judge on the caption
  alone. `fetch: instagram L2 caption only, no transcript`
- **L3. Wait.** If L1 and L2 got nothing and the issue is under 24 hours old (by `createdAt`),
  add the label `retry` and post no comment. A later run tries again.
  `fetch: instagram L3 retrying`
- **L4. Ask, without blocking.** Past 24 hours, add `needs-you`, remove `inbox`/`retry`, and
  post exactly:

  > Instagram blocked this one. Paste the caption or attach the video if you want it judged.

  `fetch: instagram L4 needs-you`

Never use cookies, a logged-in browser, or any Instagram account.
