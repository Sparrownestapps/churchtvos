# Meta (Facebook and Instagram) ad variants and audiences

**Status:** drafts only. Nothing is set up or spent. Do not run until: first-run onboarding works, the launch landing page is live, `trial_started` and `tv_paired` events exist, and the privacy policy plus store data-safety answers are updated for the Meta pixel (strategy 03 section 10).
**Rules:** no competitor names; no fake testimonials; no photos of identifiable children; no "grow your church" or fear copy; no price until decided; honest limits kept in the landing page. Meta's special ad categories do not apply to software, but keep targeting by religious belief off: target by **job titles and interests in church administration and kids ministry**, not by "Christian" belief alone (Meta restricts or flags sensitive-category targeting; VERIFY current policy). Meta may treat Christianity-interest targeting as sensitive: lean on job title and ministry-role interests.
**Budget:** $100 per month retargeting at the $500 tier; prospecting only after the waitlist passes 100 (lookalike source).

## Audience ideas

| # | Audience | Targeting idea | Notes |
|---|---|---|---|
| 1 | Retargeting: site visitors, 30 days | Pixel audience on churchtvos.com, excluding trial starters | Cheapest, warmest. Start here. |
| 2 | Retargeting: video viewers 50%+ | People who watched the hero video | |
| 3 | Job titles | "Children's pastor", "Kids ministry director", "Church administrator", "Technical director (church)", "Worship pastor", "Executive pastor" | Job-title fields are self-reported; reach is small, quality high. |
| 4 | Interests (ministry roles) | Children's ministry, Church administration, Church music, Church production, Digital signage | Not "Christianity" alone. |
| 5 | Lookalike 1% from waitlist | Needs 100+ emails with consent (Meta custom-audience list uploads need lawful basis; use hashed upload only with consent) | Wait until list exists. |
| 6 | Geographic wedges | Ontario and Canadian denominational regions (PAOC, Baptist, Alliance, CRC, EFC contacts) | Strong for a Canadian founder; trust is local. |
| 7 | Lookalike from trial starters who paired a TV | After 50+ | Best quality, later. |

Placements: Facebook feed, Instagram feed and Reels, Stories. Exclude Audience Network at first. Optimisation event: `ViewContent` → `Lead` (waitlist) → `trial_started` as volume allows.

## Ad variants

Each variant: primary text (125 characters shows before "see more"; keep the hook inside it), headline (about 40), description (about 30), CTA button, creative. The image/video creatives named are in `../08-graphics/out/` or `../04-video/`.

### V1: The Sunday scene (video 15s or the hero 30s) · audience 3, 4
* **Primary text:** "Ten to nine on a Sunday, and the countdown video is on a laptop in the car. There's a calmer way to run your kids rooms: a Fire TV, Google TV or Roku on each TV, scheduled Thursday, run from your phone."
* **Headline:** Run your church screens from your phone
* **Description:** Free trial. No card to look around.
* **CTA:** Learn more · **Creative:** 15s cut · **Landing:** hero page (UTM `utm_content=meta_v1`)

### V2: Volunteer-proof (image or Reel) · audience 3
* **Primary text:** "A volunteer who's afraid of the nursery TV is a volunteer you might lose. Church TV OS gives them one job: Next. They can run the room. They can't break it."
* **Headline:** Your volunteers can't break it
* **Description:** Operator role. Free trial.
* **CTA:** Learn more · **Creative:** `feature-kids-1080x1080.png` · UTM `meta_v2`

### V3: Use the TV you have · audience 1, 4
* **Primary text:** "You already own a TV that sits idle five days a week. Church TV OS runs lobby signs Monday to Saturday and kids content on Sunday morning, from a Fire TV, Google TV or Roku."
* **Headline:** The TVs you already own, working all week
* **Description:** Live on Fire TV, Google TV, Roku.
* **CTA:** Sign up · **Creative:** `social-usetv-1080x1080.png` · UTM `meta_v3`

### V4: Set it Thursday · audience 1, 2
* **Primary text:** "Schedule each room on Thursday. The TV downloads it ahead of time and keeps playing if the Wi-Fi drops. Sunday's job is pressing Next."
* **Headline:** Set it Thursday. Forget it Sunday.
* **Description:** Try it free.
* **CTA:** Learn more · **Creative:** `social-thursday-1080x1350.png` · UTM `meta_v4`

### V5: Honest launch (retargeting) · audience 1
* **Primary text:** "It's live on Fire TV, Google TV and Roku. LG and Samsung are coming soon, and I'll tell you the day they're ready. Start a free trial and pair a TV tonight."
* **Headline:** Church TV OS is live
* **Description:** LG and Samsung coming soon.
* **CTA:** Start trial (use "Sign up" if unavailable) · **Creative:** `badge-strip-live-and-soon-1600x300.png` plus `launch-announcement-1080x1080.png` · UTM `meta_v5`

### V6: Slides for small rooms · audience 4
* **Primary text:** "Song lyrics and slides for a chapel or a youth room, without a laptop in the booth. Import a PDF or PowerPoint, pick a theme, press Next from your phone."
* **Headline:** Church slides without a laptop
* **Description:** Not a main-stage rig. Great for small rooms.
* **CTA:** Learn more · **Creative:** `feature-slides-1080x1080.png` · UTM `meta_v6`

### V7: Founder (carousel or single image) · audience 6
* **Primary text:** "I'm a worship pastor in Cambridge, Ontario. I built Church TV OS to run our kids rooms from a Fire stick. Now it's open to any church. Try it free."
* **Headline:** Built by a worship pastor
* **Description:** Made at a real church.
* **CTA:** Learn more · **Creative:** a real photo of Keith with a TV (no children) `[needs photo]` · UTM `meta_v7`
* **Check:** needs the written note from Forward Church leadership before using the church name in the image or copy.

### Lead-form variant (waitlist for LG and Samsung)
* **Primary text:** "Church TV OS is coming to LG and Samsung TVs. Tell me which TV you've got and I'll send one email when it's ready."
* **Form:** email (required) + consent checkbox unticked + TV platform (multiple choice). Match the CASL consent text from `../02-landing-and-waitlist/waitlist-and-coming-soon-copy.md`. A Meta lead form's built-in "I agree" is not the same as the CASL consent wording: add a custom question with the full consent text.
* **Thank-you:** "Check your inbox to confirm. While you wait, you can try Church TV OS free on Fire TV, Google TV or Roku."

## Testing plan
* 3 variants × 2 audiences, $5 to $10 a day each for 5 days; kill anything with a CTR under 0.5% or cost per trial over $60.
* Keep the winning primary text, test creatives next.
* Refresh creative every 3 weeks (fatigue).
* Comment moderation: reply to every question the same day; hide nothing except spam.

## Compliance checklist (before turning on)
- [ ] Privacy policy updated for the Meta pixel; store data-safety answers updated.
- [ ] Cookie consent handled where the pixel is used.
- [ ] No competitor names, logos or claims.
- [ ] No children's faces. Screens only.
- [ ] Every claim matches `../00-FACTS-AND-PLACEHOLDERS.md`.
- [ ] Landing page URLs carry UTMs and contain no personal data.
