# churchtvos.com marketing site

Static, no framework. Plain HTML and CSS, about 20 lines of JavaScript (the mobile menu). The app itself lives in `../dashboard/` (app.churchtvos.com); this folder is only the public site.

## Structure
```
website/
  src/pages/*.html     one file per page: a front-matter comment (title, description) plus the page body
  static/              copied as-is into dist/: assets/site.css, site.js, fonts, images, icons, og-image.jpg, _headers
  tools/build.py       assembles dist/ (header, footer, canonical, Open Graph, JSON-LD, sitemap.xml, robots.txt) and checks internal links
  tools/build_assets.py  regenerates images, icons, OG image and the Lato woff2 subsets from the repo's brand/ and screenshot folders
  netlify.toml         build command and publish dir; redirects /help/*, /privacy, /terms to app.churchtvos.com
  dist/                build output (git-ignored)
```
Pages: Home `/`, Features, How it works, For churches, Pricing, Support, 404. Privacy, Terms, Help and Delete account are linked to the existing pages on app.churchtvos.com so there is one source of truth.

## Edit
- Copy and layout: edit `src/pages/<page>.html`, then `python3 website/tools/build.py` and open `dist/`. Preview with `python3 -m http.server 8080 --directory website/dist`.
- Images in a page: `{{pic:name|alt text}}` (lazy) or `{{pic!:name|alt text}}` (above the fold). `name` is a file in `static/assets/img/` (a .webp and .png pair; sizes are read automatically).
- Variables in pages: `{{APP}}` (https://app.churchtvos.com) and `{{CONTACT}}`. Change the contact address once, in `CONTACT` at the top of `tools/build.py`. It is `support@churchtvos.com`.
- FAQ: `<details><summary>Q</summary><div>A</div></details>` on the home page is also emitted as FAQPage structured data.
- Colours and fonts: variables at the top of `static/assets/site.css`. Colours come from the app icon; the font is Lato (the Forward set for now), subset to Latin and self-hosted.
- New screenshots: add the source file to `tools/build_assets.py` (needs Pillow, plus fonttools and brotli for fonts) and run it.
- New page: add `src/pages/x.html`, then add it to `PAGES` (and `NAV` if it goes in the menu) in `tools/build.py`.
- Sample content in the screenshots is the demo church ("Grace Community Church"). Re-capture before launch if you want your own.

## Deploy (Netlify)
- Draft/preview only: `cd website && python3 tools/build.py && npx netlify-cli deploy --dir dist --site <site id>` (no `--prod`). A draft site `churchtvos-site` (https://churchtvos-site.netlify.app, project id b1a3666c-0c64-4949-bf46-babb40b1827f, team Sparrownest) exists. Nothing has been deployed to production.
- Production later: connect the repo to the site with base directory `website` (build command and publish dir come from `netlify.toml`), or run `npx netlify-cli deploy --prod --dir dist --site <id>`.
- New Netlify teams may switch on **Visitor access / Team protection**, which hides the site behind a Netlify login. Turn it off under Project configuration, Access & security, Visitor access, or the public cannot see the site.
- `/help/*` on this site redirects to the app's help pages. Old links keep working.

## Point churchtvos.com at it (GoDaddy DNS) - not done yet
Add the domain in Netlify (Project configuration, Domain management, Add a domain: `churchtvos.com`, and add `www.churchtvos.com`; set the primary to `churchtvos.com`). Then at GoDaddy (DNS, Manage DNS for churchtvos.com):

| Type | Name | Value | Notes |
|---|---|---|---|
| A | `@` | `75.2.60.5` | Netlify load balancer, the value Netlify's docs give for apex domains. Confirm in Netlify's domain panel before saving. |
| CNAME | `www` | `churchtvos-site.netlify.app` | |
| CNAME | `app` | `churchtvos-app.netlify.app` | already exists for the app; leave it alone |

Delete any existing GoDaddy "parked" A record for `@` and the default `www` CNAME first (a name can only have one). Leave MX/TXT (email) records alone. If you use `hello@churchtvos.com`, set up that mailbox or a forward separately; it is unrelated to the site's DNS. After DNS settles, press "Verify DNS" in Netlify and enable the free HTTPS certificate. Optionally switch to Netlify DNS later by changing the nameservers, but the records above avoid that.

## Before launch checklist
- Confirm the contact address (`CONTACT` in build.py) exists and receives mail.
- Re-read the claims on Pricing (free trial wording), and the app availability wording (Fire TV in review, Apple apps in beta) and update when store listings go live.
- The sitemap/canonicals already point at https://churchtvos.com.
- Support, delete-account and the Help Center footers on app.churchtvos.com still show keith@sparrownest.com; consider switching them to the new address.
