# Fetch recipes for /inbox

One recipe per link type. Each one fills the bundle (URL, meta title and description, text,
transcript or images, and the `fetch:` line). On any failure, keep what you have and say in the
`fetch:` line what is missing.

`UNSTABLE` = `github:NixOS/nixpkgs/nixos-unstable`. Video tools come from there, because this
laptop's system `nixpkgs` is 25.05, whose yt-dlp is a year old and breaks on TikTok and
Instagram.

`'<url>'` below is the shared URL, already checked in SKILL.md step 2, and always inside single
quotes. TikTok links carry `&`, which unquoted would background the command.

## Which recipe

The issue's `kind:` line is `<platform>-<type>`. Pick by platform, and let the type refine it:

| kind starts with | Recipe |
|---|---|
| `github-repo` | GitHub repo |
| `x-post` | X post |
| `tiktok-video`, `tiktok-short-link` (after resolving) | TikTok video |
| `tiktok-slideshow` | TikTok video, last paragraph |
| `instagram-` | Instagram |
| `youtube-`, `bilibili-video` | Video platforms |
| `reddit-`, `linkedin-` | Reddit, LinkedIn |
| `xiaohongshu-`, `douyin-`, `weibo-`, `wechat-`, `zhihu-`, `kuaishou-`, `douban-`, `toutiao-`, `line-`, `kakao-`, `naver-` | Asian platforms |
| `web-page`, and any other platform (`substack-`, `medium-`, `facebook-`, `threads-`, `bluesky-`, `pinterest-`, `telegram-`, `twitch-`, …) | Website or article |
| `image-file`, `audio-file`, `video-file` | Picture, audio or video file |
| `diagram-` (excalidraw, drawio, figma, miro, …) | Website or article, then the diagram note |
| `text` | no fetch: judge the text, `fetch: text only` |

An unrecognised host always falls through to Website or article. A recipe that gets nothing is
not an error: judge on the sharer's own text and say so in the `fetch:` line.

## GitHub repo (`github.com/<owner>/<repo>`)

```sh
gh repo view <owner>/<repo> --json description,stargazerCount,licenseInfo,pushedAt,isArchived
gh api repos/<owner>/<repo>/readme --jq .content | base64 -d
git clone --depth 1 https://github.com/<owner>/<repo> <scratch>/repo
just -f ~/Projects/claude-env/justfile vet <scratch>/repo
```

`fetch: repo gh+readme+vet`

## Website or article (and anything not listed below)

`defuddle parse '<url>' --md` if defuddle is on PATH. Otherwise, or when it returns little:

```sh
curl -sL -H 'DNT: 1' 'https://r.jina.ai/<url>'
```

Jina only for public URLs. `fetch: web defuddle | web jina | web meta only`

## Picture, audio or video file (`image-file`, `audio-file`, `video-file`)

Where the file is depends on the issue:

- **A `file:` line** (uploaded from a phone): the file is `~/Projects/crew-vault/<file value>`,
  already pulled in step 1. Use it only when the value starts with `inbox-files/` and holds no
  `..`; otherwise close the issue `unsafe` with "malformed file path". Copy it into scratch.
- **A `url:` line** (a direct link): download it into scratch with a size cap:

```sh
curl -sL --max-filesize 50000000 -o <scratch>/file '<url>'
```

Then look at it. A picture: Read the file and describe what it shows (diagram, screenshot,
photo, text in it). Audio or video: transcribe with the TikTok recipe's whisper command (for
video, first `ffmpeg -i <scratch>/file -vn -ac 1 -ar 16000 <scratch>/a.wav`).
`fetch: image viewed | audio whisper | video whisper | file download failed`

A picture or recording with no words and no context is thin: judge what it shows, and say in the
verdict that the sharer's own words were missing.

## Diagram link (`diagram-*`)

Diagram tools render in the browser, so the page text is thin. Fetch it as a website for the
title and description, add the page's `og:image` (`curl -sL '<url>' | rg -o 'og:image" content="[^"]+'`)
and view that image. `fetch: diagram meta+og:image | diagram meta only`

## X post (`x.com`, `twitter.com`)

```sh
curl -sG --data-urlencode 'url=<url>' -d omit_script=1 https://publish.x.com/oembed
```

The post text is inside the `html` blockquote. Text only: no thread, no media.
`fetch: x oembed`

## Reddit, LinkedIn

The page's meta tags plus Jina Reader. Reddit's `.json` endpoints are dead (403). When both are
blocked: `fetch: <site> link only`, and judge on the title and the sharer's text.

## TikTok video (`tiktok.com/…/video/…`, `vm.tiktok.com/…`)

```sh
nix run UNSTABLE#yt-dlp -- --write-info-json --skip-download -o '<scratch>/%(id)s' '<url>'
nix run UNSTABLE#yt-dlp -- -x --audio-format mp3 -o '<scratch>/%(id)s.%(ext)s' '<url>'
nix run UNSTABLE#whisper-ctranslate2 -- --model small --compute_type int8 \
  --output_format txt --output_dir <scratch> <scratch>/<id>.mp3
```

The caption is `description` in the `.info.json`; the transcript is the `.txt`.
`fetch: tiktok yt-dlp+whisper`

A `/photo/` URL (a slideshow) is out of scope for v0. Judge the caption from the page meta and
write `fetch: tiktok slideshow caption only`.

## Video platforms (`youtube-*`, `bilibili-video`)

yt-dlp has extractors for both. Captions first, because they are cheap and exact:

```sh
nix run UNSTABLE#yt-dlp -- --write-info-json --write-auto-subs --sub-langs 'en.*,zh.*' --skip-download -o '<scratch>/%(id)s' '<url>'
```

Read the `description` and the `.vtt` subtitles. With no subtitles, take the TikTok video's audio
and whisper path (its `--model small` handles Mandarin; add `--language zh` when the title is
Chinese). `fetch: youtube captions | youtube yt-dlp+whisper | bilibili yt-dlp`

## Asian platforms (Xiaohongshu, Douyin, Weibo, WeChat, Zhihu, Kuaishou, Douban, Toutiao, LINE, Kakao, Naver)

**Start from the share text.** These apps put the caption in the share itself, for example
`【标题 - 用户 | 小红书】` (Xiaohongshu) or `看看【某人的作品】…` (Douyin), and that is often all
there is to judge. Then try, in order, and stop at the first that returns content:

1. The resolved page's meta tags (`og:title`, `og:description`) and Jina Reader, as for a website.
2. For Naver and Kakao video links, and Weibo, Douyin and Kuaishou videos: the TikTok video
   commands (yt-dlp). UNVERIFIED for these platforms: they change often and some demand a login,
   which this inbox never uses.
   **Measured 2026-11-26, Weibo** (`video.weibo.com/show?fid=…`): page meta redirects to Sina's
   visitor login wall and returns nothing, Jina returns page chrome with no caption, and yt-dlp
   works logged out (its own anonymous guest session, no account cookies) and returns caption,
   uploader, duration and view count. For Weibo, start with yt-dlp.
   **Measured 2026-11-26, the others, logged out:** Xiaohongshu (`xhslink.cn`) redirects to a
   rednote.com login page, so meta and Jina return nothing. Douyin returns only page chrome and
   yt-dlp answers 403 "fresh cookies needed". LinkedIn profiles hit an auth wall (HTTP 999). For
   these, judge the sharer's own text if it carries a caption.
   **Measured 2026-11-28:** Bilibili works logged out with yt-dlp (the Video platforms recipe):
   title, uploader, description and duration; subtitles were absent on the video tried, so expect
   the whisper path. Zhihu is walled: the page answers 403, Jina lands on a login and CAPTCHA
   page (`安全验证`), and there is no oEmbed. Treat Zhihu like Xiaohongshu. WeChat is still
   unmeasured (no public sample link).
   **A login wall is not a verdict.** With no caption in the share, set `needs-you` (remove
   `inbox` and `retry`) and post exactly: `<Platform> needs a login to show this one. Describe it in one
   sentence if you want it judged.` (the share page shows a box for it), and
   write `fetch: <platform> login wall, needs-you`. Do not wait 24 hours first: a login wall does
   not clear by itself.

`fetch: <platform> share text only | <platform> meta | <platform> yt-dlp+whisper`. Judge Chinese,
Japanese and Korean text as it stands, and write the verdict comment in English.

## Instagram reel or post (`instagram.com/reel/…`, `/p/…`)

Climb the levels in order, stopping at the first that gives content. Record the level in the
`fetch:` line, because these counts decide whether a throwaway account is ever worth it.

- **Measured 2026-11-26:** L1 worked on 3 of 3 distinct links (two reels with transcripts, one
  carousel caption), so no throwaway account is needed yet.
- **L1. yt-dlp, logged out.** The TikTok commands with the Instagram URL. Add
  `--ignore-no-formats-error` (image carousels). `fetch: instagram L1 yt-dlp+whisper`
- **L2. The public page, logged out.** Read the caption from the reel page's `og:description`,
  or from the embed page when that is empty:

  ```sh
  curl -sL -A 'Mozilla/5.0' '<url>' | grep -o '<meta property="og:description"[^>]*>'
  curl -sL -A 'Mozilla/5.0' 'https://www.instagram.com/reel/<id>/embed/captioned/' \
    | grep -o '<div class="Caption"[^<]*<[^>]*>[^<]*'
  ```

  Judge on the caption alone. `fetch: instagram L2 caption only, no transcript`
- **L3. Wait.** If L1 and L2 got nothing and the issue is under 24 hours old (by `createdAt`),
  add the label `retry` and post no comment. A later run tries again.
  `fetch: instagram L3 retrying`
- **L4. Ask, without blocking.** Past 24 hours, add `needs-you`, remove `inbox`/`retry`, and
  post exactly:

  > Instagram blocked this one. Paste the caption or attach the video if you want it judged.

  `fetch: instagram L4 needs-you`

`instagram-post` (a photo or carousel) has no video, so go straight to L2; `instagram-story`
always needs a login, so judge the link and the sharer's text: `fetch: instagram story link only`.

Never use cookies, a logged-in browser, or any Instagram account.
