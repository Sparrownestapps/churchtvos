# Church TV OS marketing materials: index

Written 2026-10-23. Nothing here has been posted, sent, published, deployed, signed up for or paid for. `website/` was not touched.
**Read first:** `00-FACTS-AND-PLACEHOLDERS.md` (what we can and cannot claim, and the placeholder list). Strategy: `../03-marketing-strategy.md`. Research: `../01-market-research.md`.

Priorities follow the research ranking: (1) Facebook groups, (2) SEO/comparison and tutorial content (no brand names), (3) founding-church pilot, (4) podcast and newsletter pitches, then store listings, ads and the rest.

| File | What it is | When to use | Needs Keith |
|---|---|---|---|
| `00-FACTS-AND-PLACEHOLDERS.md` | Claims register, do-not-claim list, voice rules, placeholder glossary | Before using anything | Decide the placeholders |
| **01 Launch** | | | |
| `01-launch/launch-email.md` | Launch-day email (5 subject lines, CASL footer), plus the day-before note to beta churches | Launch morning, to the consenting waitlist only | Store links, real status, postal address, unsubscribe link, founding line |
| `01-launch/launch-blog-post.md` | ~1,000-word launch post with SEO title and meta | Launch day, on the site | Confirm Forward Church story, add screenshots |
| `01-launch/press-release.md` | Press-style release, boilerplate, and a one-to-one pitch wrapper | Day of launch, to church-tech outlets | Approve the draft quotes (they are his), launch date |
| **02 Landing and waitlist** | | | |
| `02-landing-and-waitlist/launch-landing-page.html` | Standalone launch page (fonts and images embedded, light and dark, mobile-friendly). Not deployed. Placeholders highlighted in yellow | Review in a browser, then host it | Store links, form action (double opt-in), prices, testimonial, postal address |
| `02-landing-and-waitlist/waitlist-and-coming-soon-copy.md` | LG and Samsung "coming soon" page copy, form fields and CASL consent text, confirmation email, reply bank, "now live" announcement | When you build the waitlist | Real status of LG/Samsung, hardware wording |
| **03 Social** | | | |
| `03-social/30-day-content-calendar.md` | 30 days by channel (Facebook groups, Facebook page, Instagram, LinkedIn, X, Reddit), admin DM text, reply bank | From launch day | Real photos, numbers, quotes; the Sunday checklist PDF still has to be written; ask group admins first |
| `03-social/hashtags-and-caption-variants.md` | Hashtag sets, short/medium/long captions for the three core posts, CTAs, alt text | Alongside the calendar | None |
| **04 Video** | | | |
| `04-video/hero-demo-scripts.md` | 75s, 30s and 15s scripts, hook variants, export checklist | Recording week | Record; the Wi-Fi-off shot only if he actually tests it |
| `04-video/youtube-tutorial-outlines.md` | Pair a TV, first kids room, first signage loop (chapters, honest notes) | Record in that order | Record with a fresh test church |
| `04-video/shot-lists-and-storyboards.md` | Shot lists, text storyboards, Reels ideas, thumbnails | Shoot day | Gear, location |
| **05 Email** | | | |
| `05-email-sequences/email-sequences.md` | Waitlist nurture, trial onboarding, trial-ending, founding-church offer, referral | Load into the email tool | Pricing, trial length, grace period, offer terms, tool choice |
| **06 Store listings** | | | |
| `06-store-listings/store-listings.md` | Amazon, Google Play and Roku copy, keywords, what's new, a reconciliation table against `store/*.md` | At the next store submission or listing edit | Confirm what's in the shipped build; Roku limits; Roku device test first |
| **07 Ads** | | | |
| `07-ads/google-ads.md` | 4 campaigns, keywords and negatives, 4 responsive search ads (character counts checked) | Only after onboarding and analytics work | Budget decision, consent/tracking setup |
| `07-ads/meta-ads.md` | 7 ad variants, 7 audience ideas, lead-form text, checklist | Same | Same; a real photo for the founder ad |
| **08 Graphics** | | | |
| `08-graphics/out/*.png` | 13 PNGs: launch cards (1080x1080 and 1920x1080), social cards (1080x1080, 1080x1350), OG 1200x630, banner 1500x500, platform badge strip (dark and light), Kids/Signage/Slides feature cards | Social, ads, press kit, email | Eyeball them once |
| `08-graphics/make_graphics.py` (+ `fonts/`) | Regenerates them: edit the copy and re-run | When messaging changes | None |
| **09 Sales** | | | |
| `09-sales/church-tv-os-flyer.pdf` | One-page letter flyer with QR code (to churchtvos.com with UTM) | Print and PDF handout | Fill the pricing/offer placeholders in the CTA bar, then re-run (`09-sales/flyer.py` regenerates it) |
| `09-sales/pitch-deck-outline.md` | 10-slide outline plus appendix and speaker notes | Before any demo | None |
| `09-sales/church-tv-os-pitch-deck.pptx` | 10-slide deck from the outline with demo screens and notes | Demos | Replace placeholders; check slides 2 to 10 in PowerPoint (only slide 1 was rendered here) |
| `09-sales/faq.md` | Public FAQ, with honest limits | Site, email, store links | Trial, price, cancellation, support hours |
| `09-sales/objection-handling.md` | Internal objection sheet and discovery questions | Calls, DMs | "What if you disappear?" answer |
| `09-sales/comparison-sheet.md` | Part A: public comparison by category. Part B: internal brand evidence (do not publish) | Part A on the site once verified | Verify every cell marked VERIFY; decide on named comparisons (legal) |
| `09-sales/case-study-template.md` | Interview questions, metrics table, layout | After the beta | Real Forward Church numbers, permissions, leadership note |
| `09-sales/press-kit.md` | Press-kit page content, assets table, boilerplate | Site /press | Headshot, legal entity line, quotes |
| **10 Outreach** | | | |
| `10-outreach/outreach-templates.md` | Podcast, newsletter, YouTuber, kids-network, partner, integrator, affiliate, LinkedIn templates | One personalised message at a time | Personalise every first line |
| `10-outreach/referral-programme.md` | Programme rules, page copy, share text, disclosure | When billing and credits exist | Reward terms, cap, terms page |

## Open items needing Keith (in order of importance)

1. **Pricing, trial length, founding offer.** Everything uses `[PRICE]`, `[TRIAL DAYS]`, `[FOUNDING OFFER]`. Strategy deadline: 2026-12-04.
2. **Confirm the platform status** (Fire TV, Google TV and Roku really live; real store links). Roku has never run on a real device: do the device test before telling anyone it works.
3. **Written note from Forward Church leadership** that Church TV OS is yours and Forward is a customer. Needed before the case study, the "built at Forward Church" lines on ads, the press kit, and the Forward Church photos.
4. **Real proof:** Forward Church numbers (rooms, TVs, setup minutes before and after), one volunteer quote, a photo of the back of a TV, beta-church quotes with written permission. No `[TESTIMONIAL]` goes live empty.
5. **Postal address and unsubscribe mechanism** for CASL and CAN-SPAM footers, and a waitlist form with an **unticked** consent box and double opt-in.
6. **Founder anecdotes.** A few lines say things like "I've lived some version of that Sunday" and "what works for us". They are plausible but are Keith's to confirm or change. Search for `CONFIRM`.
7. **Write the Sunday screen checklist** (one page). The Facebook calendar, the kids-network email and the Day 10 post all lean on it.
8. **Decide on the iPhone/Mac messaging.** The website still calls the apps "beta" and invites people to join. The research and the coordinator say APPS-PLAN is planning only. Marketing here says "run it from your phone" (the web dashboard remote, which works in a phone browser) and "iPhone and Mac apps: coming soon". The website copy needs aligning separately.
9. **Named comparisons.** Playlister is not named anywhere public. If you want "alternative" SEO pages that name a brand, that is a legal and tone decision; the safe version is category language.
10. **Facebook groups:** DM the admins before posting anywhere; verify subreddit names and rules before Reddit posts.
11. **LG/Samsung:** confirm the current status wording before the coming-soon page goes up.
12. **Store badges:** the graphics use plain text chips, not logos. Add each store's official badge from its brand kit if you want logos.
13. **QA gaps:** the pitch deck was built and its first slide rendered, but no LibreOffice was available to render the rest. The landing page was opened in a browser pane but not checked at every width. The flyer was rendered and checked.
