# Church TV OS: Pricing and Costs

Prepared 2026-10-23 for Keith Sparrow. Companion workbook: `marketing/02-pricing-cost-model.xlsx` (live formulas, all assumptions on the `Assumptions` tab).
Nothing in code, Stripe or Supabase was changed.

Legend: **Verified** = read on the vendor's own page on 2026-10-23. **Estimate** = my assumption (editable in the workbook). **Unverified** = third-party listing or not confirmable. Prices are USD unless marked CAD.

Note on the workbook: LibreOffice was not available on this machine, so the file has formulas but no cached values until opened in Excel or Numbers (it recalculates on open). I mirrored the formulas in Python to produce the numbers in this report; they should match.

---

## 1. What exists today (from the code)

| Area | What the code does | Where |
|---|---|---|
| Modules | `kids`, `signage`, `slides` in `modules` table. Slides inserted with `available = false` (hidden until ready). Trial grants every module that is `available`. | `20261021000001_slides_module.sql`, `20261020000002_trial_and_default_room.sql` |
| Entitlements | One row per (organization, module): `status` (trialing / active / past_due / canceled), `tv_limit`, free-text `plan` ('internal' = free), `grace_ends_at`, `current_period_end`. Edited only by platform admin (audited) in the Admin console. | `20261013000001_foundation.sql`, `dashboard/src/admin/ChurchDetail.tsx` |
| "Is a module live" | `entitlement_live()`: active = live; trialing = live until `current_period_end` (live forever if null); past_due = live until `grace_ends_at`; canceled = not live. Suspended church = nothing live. | `20261021000003_admin_console.sql` |
| TV limit | `tv_limit(org)` = **MAX** of `tv_limit` across live modules (not a sum, not per module). `claim_screen` refuses pairing when the church's total screens >= limit ("Your plan allows N TV(s)"). Checked only at pairing time. | foundation + admin_console migrations |
| Trial | `create_organization` gives every available module `status='trialing'`, `tv_limit=2`, `plan='trial'`, 30 days, no card. Banner warns the owner as it ends ("Your free trial has ended. Contact support"). Expiry really ends access (module not live). | `20261020000002`, `TrialBanner.tsx` |
| Grace period | Column exists and is honoured, but **nothing sets it automatically** (no Stripe). Admin sets it by hand. No default length. | `ChurchDetail.tsx` |
| Billing | **No Stripe code anywhere** (only mentions in HANDOFF and NEXT-BUILD). Pricing page says "We have not set the numbers yet", per module + per TV. Forward Church is on `internal`, 50 TVs. | `website/src/pages/pricing.html` |
| Storage handling | Public bucket `media`; every media row stores `size_bytes`; `media_storage_by_module()` powers library headers ("N files, X used"); admin console lists `storage_bytes` per church. **No quota, no per-plan limit, no upload check on entitlement or size** beyond Supabase's global file-size limit (UI hint assumes the 50 MB free-plan cap; audio hint "under about 20 MB"). | `20261013000002`, `MediaPage.tsx` |
| Org deletion | Admin "delete church" removes database rows. I found no code that removes the church's files from the storage bucket (verify; orphans keep costing money). | `ChurchDetail.tsx` |
| TV polling | `device_state` RPC every **30 s** when paired (5 s while unpaired). A second loop, `device_poll_commands`, every **5 s idle / 2 s while something is on screen**, plus `device_report_status` on change and every 15 s. Both update `screens.last_seen_at` on **every call**. | `tv-app/.../TvSync.kt`, `20261022000001_remote_control.sql` |
| TV media cache | Downloads each file once, serves offline, prunes files no longer scheduled. No free-disk check, no size cap (Fire TV sticks have about 8 GB). | `MediaCache.kt`, `TvSync.kt` |
| Other cost-bearing pieces | Edge Function `notify-offline` (pg_cron every 5 min, 8,640 invocations a month, APNs push, no email), experimental NDI (Android licence unconfirmed), PDF/PPTX import runs in the browser (no server cost). | `supabase/functions/notify-offline`, `NDI-CONTRACT.md` |

---

## 2. Current infrastructure and platform pricing

| Item | Plan / unit | Price | Status |
|---|---|---|---|
| Supabase Free | 500 MB DB, 1 GB storage, 5 GB egress, 50 MB max file, pauses after 1 week idle | $0 | Verified. **Not viable in production** (pausing, 50 MB cap, 1 GB) |
| Supabase Pro | 8 GB DB, 100 GB storage, 250 GB egress, 250 GB cached egress, 100k MAU, 2M edge invocations, 500 realtime connections, 5M realtime messages; $10 compute credit | $25/mo | Verified |
| Supabase overages | Egress $0.09/GB, cached egress $0.03/GB, storage $0.0213/GB-mo, DB $0.125/GB, MAU $0.00325, edge $2 per million, realtime $10 per 1,000 connections and $2.50 per million messages | | Verified |
| Supabase compute add-ons | Micro $10 (covered by credit), Small $15, Medium $60, Large $110 (2 dedicated vCPU), XL $210 (4 vCPU) | per mo | Verified. 2XL ($410) and 4XL ($960) are from memory: **unverified** |
| Supabase image transformations | 100 origin images included on Pro, then $5 per 1,000 | | Verified; not used by the app today |
| Supabase Team | Adds SOC2, SSO, longer logs | from $599/mo | Verified. Not needed |
| Supabase max file upload | Page says Pro/Team 500 GB; flagged odd. Free 50 MB | | Verified on page, but confirm the setting in the dashboard |
| Netlify | Free $0 (300 credits), Personal $9 (1,000), Pro $20 (3,000, unlimited members). Credit model: 20 credits per GB bandwidth, 15 per production deploy, 10 per GB-hour compute, 2 per 10,000 requests | per mo | Verified. Whether commercial use on Free is allowed is **not stated** on the page: use Personal or Pro once you charge |
| Cloudflare R2 | $0.015/GB-mo standard ($0.01 infrequent access), Class A $4.50/M, Class B $0.36/M, **egress free**, 10 GB / 1M A / 10M B free per month | | Verified |
| Stripe Canada | 2.9% + CA$0.30 domestic cards; +0.8% international; +2% currency conversion; Billing 0.7% of recurring volume (pay as you go); Tax Basic 0.5% per transaction where registered; disputes CA$15; standard payouts free | | Verified |
| Stripe US cards | Same structure applies to US cards on a Canadian account (international + conversion if you settle in CAD) | | Estimate: hold a USD balance or price in USD to limit FX |
| Resend (email) | Free 3,000/mo (100/day); Pro $20 for 50k; $35 for 100k | | Verified. App sends no email today (alerts are APNs). Supabase Auth emails use built-in SMTP, which is rate-limited: plan a custom SMTP (Resend free) before launch |
| Sentry | Developer free (5k errors), Team $26 annual / $29 monthly (50k) | | Verified |
| Apple Developer Program | US$99/yr | | Verified in project docs/known rate; Canadian price not checked |
| Google Play | US$25 one time | | Known rate, not re-fetched |
| Amazon Appstore, Roku | Free | | Per HANDOFF; not re-fetched |
| Domain | about $20/yr | | Estimate |
| NDI | Free SDK terms say products may be sold on Android stores if they link to ndi.video; a community post disagrees; Advanced SDK is royalty-based, no public price | | **Unverified**: email sdk@ndi.video before shipping NDI. Keep it off for customers until confirmed |
| Tax (Canada) | Register for GST/HST once worldwide taxable revenue passes CA$30,000 in four quarters (small supplier rule), charge 13% HST to Ontario customers, 5% GST elsewhere (provincial rules vary). SaaS sold to US customers is generally zero-rated for GST/HST; US state sales-tax thresholds apply later | | From general knowledge, **verify with an accountant**. Stripe Tax Basic (0.5%) can calculate and collect |

---

## 3. What drives the cost: the key findings

1. **Polling is the real scaling driver, not video.** Each TV makes about 86,400 `device_state` calls a month (30 s) and about 518,000 remote-command calls a month (5 s idle), each of which writes `screens.last_seen_at`. At 1,000 churches (3,000 TVs) that is an average of about 700 requests/s, 2.5x that on a Sunday morning (about 1,750/s), and about 600 row updates a second on a 3,000-row table. The *egress* of polling (about 3 TB/mo) costs only about $270/mo; the *compute* needed to take the load is what grows: Medium by about 100 TVs, Large by about 300-400 TVs, and past XL at about 1,000 churches. My per-tier capacities are estimates: load test before relying on them.
2. **Video storage is cheap per GB, but only if it stays small.** Supabase storage is $0.0213/GB-mo, so a 60 GB library costs about $1.28/mo. The risk is a minority of heavy churches (250 GB+ libraries with 6+ TVs), costing $10-$15/mo in storage plus egress each. That is manageable if a plan covers it.
3. **Egress is mostly media pushed to TVs**, not polling at small scale. New media x TVs x re-downloads. Egress passes the free 250 GB at about 130 churches.
4. **Stripe is the largest single variable cost** (about 5.6% of revenue with Billing + Tax + FX allowances, plus $0.30 per charge). It is larger than all of Supabase until about 250 churches.
5. **Gross margin is high at every scale above about 30 churches** (84-90%). The risk is not margin, it is unbounded per-church cost without limits and the engineering fix for polling.

### Cost model (monthly, USD; base-case assumptions)

Assumptions: 3 TVs per church; 4 GB typical library, 60 GB for the 10% heavy churches (average 9.6 GB/church); 1.5 GB new media per church per month x 3 TVs x 1.3 re-download; 8 KB compressed `device_state`; 5 s remote poll; blended price from the mix in section 5 (about $34.19/church after the annual discount); fixed costs about $116/mo (Netlify Pro $20, Sentry $26, mailbox $10, misc $50, Apple + domain amortised $10).

| Line | 10 churches | 50 churches | 250 churches | 1,000 churches |
|---|---|---|---|---|
| TVs | 30 | 150 | 750 | 3,000 |
| Peak requests/sec (Sunday) | 18 | 88 | 438 | 1,750 |
| Stored media (GB) | 96 | 480 | 2,400 | 9,600 |
| Egress per month (GB), media + polling | 99 | 493 | 2,464 | 9,857 |
| Database (GB, 60 MB/church) | 0.6 | 3 | 15 | 60 |
| **Revenue (MRR)** | **$342** | **$1,710** | **$8,548** | **$34,191** |
| Supabase Pro base | $25 | $25 | $25 | $25 |
| Compute add-on net of $10 credit (tier) | $0 (Micro) | $5 (Small) | $100 (Large) | $400 (2XL, unverified price) |
| Egress overage | $0 | $22 | $199 | $865 |
| Storage overage | $0 | $8 | $49 | $202 |
| Database overage | $0 | $0 | $1 | $7 |
| Stripe (Billing + Tax + FX + $0.30) | $19 | $95 | $477 | $1,906 |
| Fixed (Netlify, Sentry, mailbox, misc, Apple, domain) | $116 | $116 | $116 | $116 |
| **Total cost** | **$160** | **$271** | **$967** | **$3,521** |
| **Gross profit** | **$182** | **$1,438** | **$7,581** | **$30,670** |
| **Gross margin** | **53%** | **84%** | **89%** | **90%** |
| Infra cost per church (ex Stripe) | $14.09 | $3.52 | $1.96 | $1.61 |
| Infra cost per TV (ex Stripe) | $4.70 | $1.17 | $0.65 | $0.54 |
| Marginal cost per GB stored | $0.0213 | $0.0213 | $0.0213 | $0.0213 |
| Marginal cost per GB egress | $0 (free allowance) | $0.09 | $0.09 | $0.09 (0.03 if cached rate applies) |

At 10 churches the fixed $116 dominates; that stage is about validation, not margin. These figures exclude your time, support, incorporation, accountant, insurance, and hardware.

### When Supabase must be upgraded

| Trigger | When | Action |
|---|---|---|
| Free tier is unusable for paying customers (pauses, 50 MB file cap, 1 GB) | **Before the first paying church, or the first video upload over 50 MB** | Move to Pro ($25) now. Forward Church's own production use justifies it already |
| Compute: Micro is fine to about 40 req/s peak | about 30-60 TVs (10-20 churches) at current polling | Small ($15) |
| Compute: Medium | about 100+ TVs, roughly 30-60 churches | Medium ($60) |
| Compute: Large | about 250 req/s peak, roughly 150-250 churches | Large ($110). **Or fix polling first** (section 6) |
| Egress passes 250 GB | about 130 churches (media + polling) | Overage $0.09/GB, about $200/mo at 250 churches. Cheap; do not engineer around it yet |
| Storage passes 100 GB | about 10-25 churches, or one heavy church | $0.0213/GB, trivial; consider R2 only for heavy video (section 7) |
| Database passes 8 GB | about 130 churches at 60 MB each | $0.125/GB, trivial. Prune `screen_commands`, `screen_status`, audit rows |
| Team plan ($599) | Not before compliance (SOC2) or SSO is a customer demand | Skip |

### Polling load sensitivity (1,000 churches, 3,000 TVs)

| Remote poll interval | Peak req/s | Compute tier / net add-on | Polling egress GB/mo |
|---|---|---|---|
| 2 s (while playing) | 4,000 | beyond 4XL | 4,406 |
| 5 s (today, idle) | 1,750 | 2XL, $400 | 3,007 |
| 10 s | 1,000 | XL, $200 | 2,540 |
| 15 s | 750 | XL, $200 | 2,385 |
| 30 s | 500 | Large, $100 | 2,229 |
| Realtime (websocket per TV) | about 0 polling | 3,000 connections cost about $25/mo (500 included, $10 per 1,000) | tiny |

The largest saving is not in the dollars shown but in not having to run (and tune) a $400/mo database that takes 600 writes a second.

---

## 4. Competitor benchmarks

| Product | Price per screen per month | Notes | Confidence |
|---|---|---|---|
| Yodeck | Free (1 screen); $8 Basic, $12 Premium, $16 Enterprise | 30-day trial, 5 screens; "unlimited" storage subject to fair use; free player with annual plan | Verified |
| OptiSigns | Free; $10 / $9 annual Standard; $12.50 / $11.25 Pro; $15 / $13.50 Pro Plus; $30 Engage; $45 Enterprise (25-screen minimum) | Free tier 1 GB with logo; paid tiers say unlimited storage | Verified |
| ScreenCloud | $20 Core, $30 Pro, billed annually; monthly costs more; annual save "up to 16%" | 14-day trial, unlimited storage, hardware discounts | Verified |
| Playlister (church kids rooms) | about $17-$25 Lite/Pro on annual; $19.99-$29.99 monthly; some listings show Business $45-$55 | Apple TV based; 30-day trial; no free tier | Unverified (vendor site unreachable; reviews and Capterra) |
| ProPresenter | $29/mo Standard, $59/mo Campus (or $289 / $649 per year) per seat | Computer software, not a TV network | Unverified (Capterra) |
| Proclaim (Logos) | from $29 per user per month | | Unverified (Capterra) |
| Church-signage tools (Kitcast etc.) | from about $7 per screen | Multi-campus; roughly $21-60/mo for three screens | Unverified (blog) |

**Reading the market:** Generic signage tops out at $8-$15 per screen with a free tier; church-specific kids-room tools charge about $20-$30 per screen. Church TV OS bundles all three (Kids + Signage + Slides) and runs on $30-$60 Fire TV sticks, so the best fit is **$6-$10 per TV effective on packs, with a clear entry price near $15**: far below Playlister, comparable to Yodeck, but with the church workflow built in.

---

## 5. Recommended pricing

### Principles
- Sell **plans (packs of TVs with all modules)**, not a matrix of modules x TVs. Churches think "we have 4 TVs", not "3 modules x 4 TVs". Keep per-module entitlements underneath for flexibility and for an à-la-carte "Lite".
- **Price per church size via TV count** (what the code already enforces), with a storage allowance as the second axis. Church-size tiers by attendance are harder to audit and invite arguments.
- All churches are non-profits, so do not run a separate "nonprofit discount". Make the standard price the church price and say so. Offer free/discounted use only through founding and mission rules.
- Charge **annual with two months free** (about 17% off): it cuts Stripe's $0.30 charges, churn and failed payments. Church budgets are annual.
- **Price in USD and CAD** with separate charm prices (not FX conversion); include HST on Canadian invoices.

### Price list (monthly, ex-tax)

| Plan | TVs | Modules | Storage included | USD / mo | USD / yr (2 months free) | CAD / mo | USD per TV |
|---|---|---|---|---|---|---|---|
| **Lite** | 1 | any one of Kids, Signage, Slides | 5 GB | $9 | $90 | $12 | $9.00 |
| **Solo** | 1 | all three | 10 GB | $15 | $150 | $19 | $15.00 |
| **Church** (headline plan) | 4 | all three | 50 GB | $39 | $390 | $49 | $9.75 |
| **Campus** | 10 | all three | 150 GB | $79 | $790 | $99 | $7.90 |
| **Network** (multi-site) | 25 | all three + priority support | 500 GB | $149 | $1,490 | $189 | $5.96 |
| Extra TV | +1 | | | $6 | $60 | $8 | |
| Extra storage | +100 GB | | | $5 | $50 | $7 | |
| Enterprise / over 25 TVs | custom | | | quote | | | |

Compared with Playlister at $20-$30 per screen, a 4-TV church pays $39 instead of $80-$120. Do not discount further: it signals a toy and leaves no room for support.

### Trial, free tier and early adopters

| Offer | Recommendation |
|---|---|
| Trial | Keep 30 days, no card, 2 TVs, all modules (as built). Add a "extend 30 days" admin action and a 5 GB trial storage cap |
| Free forever | **No** general free tier (support burden, cost leakage). Exceptions by admin: Forward Church (`internal`), and a "Sunday Starter" give-away for tiny churches only at your discretion via the `plan` column |
| Founding members | First 50 churches: **40% off for life with annual prepay** (Church plan $23.40/mo; $234/yr), in exchange for a testimonial and feedback call. Cap it, keep the end date visible. Margin remains above 80% |
| Referral | One free month for referrer and referred |
| Annual billing | 2 months free; default the checkout toggle to annual |
| Hardware | Do not resell sticks. Recommend Fire TV Stick 4K; mention the Amazon Signage program separately |
| Regions | Same USD list worldwide; CAD price list for Canada; consider 20-30% lower "partner pricing" for lower-income regions by request, not publicly |

### Blended revenue assumption used in the model

Mix of churches: Lite 20%, Solo 30%, Church 30%, Campus 15%, Network 5%. List ARPA $37.30; after 50% annual take-up at 16.7% discount, **$34.19 per church per month**, 4.45 TVs per church on average (the model uses 3 TVs/church for load, which is conservative against revenue: lowering revenue or raising TVs moves both).

### Margin by scenario (from section 3)

| Churches | MRR | Total cost | Gross profit | Margin |
|---|---|---|---|---|
| 10 | $342 | $160 | $182 | 53% |
| 50 | $1,710 | $271 | $1,438 | 84% |
| 250 | $8,548 | $967 | $7,581 | 89% |
| 1,000 | $34,191 | $3,521 | $30,670 | 90% |

At founding pricing (40% off), 50 churches on the Church plan: $1,170 MRR against about $270 cost, still about 75% margin before Stripe changes.

---

## 6. Do we need to price for storage? Direct answer

**Yes: set a storage allowance in each plan, but do not meter it per GB.** Storage itself is cheap ($0.0213/GB-mo, a 50 GB library costs about $1). The reason to cap is (a) unbounded abuse by a heavy-video church, (b) the egress it creates when new TVs or cache clears re-download, and (c) Fire TV sticks cannot hold more than about 8 GB anyway, so a church rarely benefits from libraries beyond what plays.

| Plan | Storage included | Per-file limit | Overage / fair use |
|---|---|---|---|
| Lite | 5 GB | 500 MB | Upgrade prompt; hard stop at 120% |
| Solo | 10 GB | 500 MB | Same |
| Church | 50 GB | 1 GB | Soft warning at 80%; extra 100 GB for $5/mo |
| Campus | 150 GB | 2 GB | Same |
| Network | 500 GB | 2 GB | Extra 100 GB for $5/mo; fair-use review above 1 TB |
| Trial | 5 GB | 500 MB | Hard stop |

Rules:
1. **Allowance, soft warning at 80%, block new uploads at 100% plus 10% buffer.** Never delete a church's existing media or stop playing what is already scheduled.
2. **Overage packs, not per-GB metering**: $5 per 100 GB (about 2.3x Supabase cost; fine). Offer as a Stripe add-on or auto-upgrade to the next plan.
3. **Fair use for egress**: state "normal use is replacing a few GB a month; sustained re-downloading of large libraries may be limited". Egress is where cost hides, but at the 250-church scale it is only about $200/mo.
4. **Recommend compression**: for Fire TV, 1080p H.264 at 6-8 Mbps (about 45-60 MB per minute) is plenty; a 10-minute curriculum video is about 450-600 MB, so a 52-week library is 25-30 GB. Add an upload-time warning and a link to a free compression how-to.
5. **Do not push video to YouTube** as the default: YouTube can already be played as an item (and has the portrait and black-screen limitations in HANDOFF), and curriculum producers' licences usually forbid public hosting. Offer "YouTube link" as a supported item for churches that host publicly, with no storage charge.
6. **R2 for heavy video: not yet.** Supabase Pro's 100 GB included plus $0.0213/GB is cheaper to operate than a second system, and uploads are already wired to Supabase with signed access. R2 (egress free, $0.015/GB) becomes worth it only if egress passes about 1-2 TB a month, or a Network-tier customer stores multiple TB. Plan it as a later "large library" feature with a bucket field per organization.
7. **Heavy user example** (250 GB stored, 6 TVs, 10 GB new media a month): Supabase about $5.33 storage + $7.02 egress = **$12.35/mo**; R2 would be about $3.60. On the Campus plan ($79 + $5 for 100 GB extra over 150 GB allowance = $84) the margin is still about 85% before Stripe. A heavy user is not dangerous if capped; the unlimited-upload case is.

---

## 7. Risks and recommended changes to the built structure (do not apply; a build agent should)

| # | Risk or gap | Why it matters | Specific change (files / config) |
|---|---|---|---|
| 1 | **Polling writes**: every poll updates `screens.last_seen_at` (`device_state`, `device_poll_commands`, `device_report_status`) | 600+ writes/s at 3,000 TVs; table bloat, vacuum load, forces larger compute | In the three SQL functions change the update to `update screens set last_seen_at = now() where id = v_screen.id and last_seen_at < now() - interval '60 seconds'`. The 10-minute offline threshold in `claim_offline_alerts` is unaffected |
| 2 | **5 s / 2 s remote poll** (`TvSync.runRemote`) | Largest load driver (about 83% of requests) | Quick win: idle interval 15 s, 2 s only for 60 s after a remote session or command (add `screens.watch_until`, set when a phone opens the Remote). Better: Supabase Realtime broadcast channel per screen (3,000 TVs cost about $25/mo in connections). Ship in the next TV build |
| 3 | `device_state` payload size unknown, polled 86,400 times a month | At 8 KB compressed it is 0.7 GB per TV a month; at 40 KB it is 3.5 GB per TV (about 31 TB at 3,000 TVs, about $2,800/mo) | **Measure it.** Add an ETag / `version` argument so unchanged state returns a few bytes, or poll a tiny `state_version` function and fetch full state only when it changes. Ensure gzip is on |
| 4 | `tv_limit` is the MAX across modules, applied only at pairing; per-module per-TV pricing is not enforceable | A church paying for Kids 10 TVs can run Signage on all 10; downgrades leave extra TVs paired | If you sell packs (recommended), keep one org-level limit: add `organizations.plan_tv_limit` and have the Stripe webhook set it; keep per-module rows only as on/off flags. Also add a daily check or trigger to mark TVs beyond the limit "over limit" (pause, not delete) |
| 5 | **No storage quota** anywhere | One church can store terabytes | Add `entitlements.storage_gb_limit` (or org-level), plus a `check_upload_allowed(org, bytes)` RPC called by `MediaPage.tsx` before upload and a `before insert` trigger on `media` as backstop; use the existing `media_storage_by_module()` for the meter and 80% warning. Show usage in Settings |
| 6 | Supabase file size limit | Dashboard text says "50 MB on the free plan"; `supabase/config.toml` says 50 MiB | In the Supabase dashboard set the global upload limit (Storage settings) to about 2 GB on Pro and update the UI messages. Add a client-side per-plan file cap |
| 7 | **Trial abuse**: `create_organization` has no per-user or per-email limit | Unlimited free 30-day trials with 2 TVs | Limit to 1 trial org per user (count `memberships` where role=owner), require verified email, flag duplicate names. Optional: limit by email domain |
| 8 | **No grace/cancel lifecycle** | `grace_ends_at` is never set; `canceled` immediately stops the module; storage kept forever | Stripe webhook (Edge Function) sets: `invoice.payment_failed` -> `past_due`, `grace_ends_at = now() + 10 days` (Stripe retries on its own schedule); `customer.subscription.deleted` -> `canceled`. Add a 30-day read-only/export period, then archive media after 90 days (delete and email notice). Trial-end emails at day 25 and 30 |
| 9 | Church delete leaves files | Orphaned storage keeps billing | Extend the admin delete flow to list and remove `storage.objects` with the org prefix |
| 10 | Slides storage policies check only `kids`/`signage` | A Slides-only church may be unable to upload | Update the four `storage.objects` policies in `20261013000001_foundation.sql` to include `slides` (verify in a test) |
| 11 | **Stripe not built** | No revenue path | Products/prices per plan in USD and CAD with `lookup_key`s; Stripe Checkout + Customer Portal; Stripe Tax; webhook function writes `entitlements` and sets `plan` to the pack name; admin console keeps manual override (`internal`, founding) |
| 12 | Store rules | Apple/Google/Amazon: Fire TV store apps selling digital subscriptions in-app owe fees | Keep billing web-only; never show prices or "buy" in the TV or iOS apps (already the plan). Re-check Apple's B2B wording at submission |
| 13 | Supabase Auth email limits | Default SMTP is rate-limited for production sign-ups | Configure custom SMTP (Resend free) and set the Site URL (HANDOFF step) before launch |
| 14 | Public `media` bucket | Anyone with a URL can pull egress; no hotlink control | Acceptable at start (UUID paths). Set long `cacheControl` on uploads so downloads count as cached egress ($0.03/GB) where Supabase applies it (unverified) |
| 15 | Pricing page and copy | Page says numbers are not set | Replace with the price table; keep "no credit card trial"; add the storage allowance and fair-use line; add CAD toggle |
| 16 | NDI | Android licence unconfirmed | Keep `ndi_enabled` off for customers until NDI replies in writing; price as an add-on only if royalties apply |
| 17 | Fire TV disk space | `MediaCache` has no free-space check; 8 GB sticks fill silently | Add a pre-download space check and an in-app "storage full" status reported to the dashboard |
| 18 | Business | Revenue legally required registration, tax, terms | Register for GST/HST before passing CA$30,000; incorporate; Terms/Privacy already linked. Keith-owned, with a written note from Forward Church (HANDOFF item) |

---

## 8. Suggested launch order

1. Move to Supabase Pro and set the global upload limit now (needed for any real video).
2. Quick wins on load: items 1, 2 (idle 15 s) and 3 (ETag), and measure `device_state` size.
3. Build Stripe Checkout + webhook with the five plans, storage columns (item 5) and trial limit (item 7).
4. Open a founding-member round (first 50 churches at 40% off for life, annual prepay).
5. Revisit compute when the dashboard shows more than 100 TVs: a load test at 3 times the current TV count tells you whether Medium or Large is needed.
6. Revisit R2 only if egress passes about 1-2 TB/mo or storage passes about 2 TB.

---

## 9. Sources
- Supabase: https://supabase.com/pricing
- Netlify: https://www.netlify.com/pricing/
- Cloudflare R2: https://developers.cloudflare.com/r2/pricing/
- Stripe Canada: https://stripe.com/en-ca/pricing
- Resend: https://resend.com/pricing ; Sentry: https://sentry.io/pricing/
- Yodeck: https://www.yodeck.com/pricing/ ; OptiSigns: https://www.optisigns.com/pricing ; ScreenCloud: https://screencloud.com/pricing
- Playlister (review): https://learnofchrist.com/resources/playlister ; Capterra/GetApp listings (unverified)
- ProPresenter/Proclaim: Capterra listings (unverified)
- NDI licensing: https://docs.ndi.video/docs/sdk/licensing
