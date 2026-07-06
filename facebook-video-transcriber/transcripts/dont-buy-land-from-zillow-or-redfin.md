---
type: reference
scope: facebook-video-transcriber
purpose: Transcript + extracted info for a scraped Facebook Reel (real-estate / off-market land tip)
last_updated: 2026-07-06
source_url: https://fb.watch/Ia_XtRWKyH/
---

# Don't Buy Land From Zillow or Redfin — Facebook Reel

## Source

| Field | Value |
|-------|-------|
| **Original link** | `https://fb.watch/Ia_XtRWKyH/?mibextid=wwXIfr&fs=e` |
| **Platform** | Facebook Reel |
| **Format** | Vertical video, 720×1280, 30 fps |
| **Duration** | 32.5 seconds |
| **Audio** | AAC stereo — spoken English (Whisper confidence 100%) |
| **Captured** | 2026-07-06 |

> **Scrape note:** the `fb.watch` link is login-walled and could not be pulled directly from the
> automated environment (curl, yt-dlp, headless Chromium, and mbasic all bounced to a Facebook
> login redirect). The transcript and on-screen text below were produced from a manually
> downloaded copy of the video, using **ffmpeg** (audio + frame extraction) and
> **faster-whisper** (`base` model, speech-to-text).

## Creator / visual context

- On-camera: a man in a teal **"DPA Summit"** T-shirt and cap, filming himself outdoors next to an
  overgrown / vacant lot.
- The clip cuts between his talking-head footage and screen recordings of a city website and a
  county tax-assessor record.
- Worked example throughout uses **San Antonio, TX (Bexar County)**.

## Full transcript

> Never, ever, ever buy land on Zillow or Redfin. Instead, do this. Go to your local city website
> and look for the **code enforcement division**. Go to the records and find the list of properties
> that have been sent violations for overgrown grass, abatement, and boarding up the buildings.
> These are all properties that have been forgotten about. You can get these properties. Then go to
> the **county tax assessor** and search up that address. You'll find the owner's information and how
> much taxes they owe. Once you find the owner's information, you go to **truepeoplesearch.com** and
> search the owner and get their phone number. It's free. Call them and just make them a low offer —
> about half of what the tax value is. Do this again and again and again so someone says yes, and
> then close that sucker up. That's how you get property.

### Timestamped segments

```
[ 0.00 ->  2.28] Never, ever, ever buy land on Zillow or Redfin.
[ 2.28 ->  3.24] Instead, do this.
[ 3.24 ->  4.56] Go to your local city website
[ 4.56 ->  6.32] and look for the code enforcement division.
[ 6.32 ->  8.12] Go to the records and find the list of properties
[ 8.12 -> 10.28] that have been sent violations for overgrown grass,
[10.28 -> 11.80] abatement, and boarding up the buildings.
[11.80 -> 13.72] These are all properties that have been forgotten about.
[13.72 -> 14.72] You can get these properties,
[14.72 -> 16.64] then go to the county tax assessor
[16.64 -> 17.70] and search up that address.
[17.70 -> 19.00] You'll find the owner's information
[19.00 -> 20.24] and how much taxes they owe.
[20.24 -> 21.52] Once you find the owner's information,
[21.52 -> 22.96] you go to truepeoplesearch.com
[22.96 -> 24.56] and search the owner and get their phone number.
[24.56 -> 25.40] It's free.
[25.40 -> 26.28] Call them and just make them a low offer
[26.28 -> 27.80] about half of what the tax value is.
[27.80 -> 29.04] Do this again and again and again
[29.04 -> 31.20] so someone says yes and then close that sucker up.
[31.20 -> 32.52] That's how you get property.
```

## The method (5 steps)

1. **Skip Zillow / Redfin.** Instead, go to your **local city website** → **Code Enforcement Division**.
2. **Pull the violation records** — properties cited for *overgrown grass*, *abatement*, or
   *boarded-up buildings*. These are neglected / forgotten properties.
   *(On-screen example: San Antonio's "Vacant Buildings Program → Vacant Building Inventory".)*
3. **Go to the county tax assessor** and search that address to find the **owner's mailing
   information** and **how much property tax they owe**.
   *(On-screen example: a Bexar County / San Antonio tax record.)*
4. **Look the owner up on `truepeoplesearch.com`** (free) to get their **phone number**.
5. **Call and make a lowball offer** — roughly **half the assessed tax value**. Repeat across many
   owners until someone says yes, then close the deal.

## On-screen captions (from sampled frames)

- "DON'T BUY LAND FROM ZILLOW OR REDFIN"
- "violations for overgrown grass" *(over a San Antonio city website)*
- "you'll find the owner's information" *(over a Bexar County tax-assessor record)*
- "4. CALL 📞 — call them and just make them a low offer"

## Tools & resources named in the video

- **Local city website → Code Enforcement Division** (violation records)
- **County tax assessor** (owner info + taxes owed)
- **truepeoplesearch.com** (free owner phone-number lookup)

---

*Extracted with ffmpeg + faster-whisper. This document reproduces the video's claims for reference;
it is not financial, legal, or real-estate advice.*
