#!/usr/bin/env python3
"""Static site builder for churchtvos.com (standard library only).
  python3 website/tools/build.py          -> writes website/dist/
Pages live in src/pages/*.html (a small front-matter comment + the page body). The shared header, footer,
JSON-LD, sitemap and robots.txt are generated here. Static files (css, images, fonts, icons) are copied from static/."""
import os, re, json, shutil, struct, html, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.normpath(os.path.join(HERE, ".."))
SRC, STATIC, DIST = (os.path.join(SITE, p) for p in ("src/pages", "static", "dist"))

# ---- Things Keith may want to change in one place -------------------------------------------------
DOMAIN = "https://churchtvos.com"
APP = "https://app.churchtvos.com"
CONTACT = "support@churchtvos.com"
SITE_NAME = "Church TV OS"
DEFAULT_DESC = "Church TV OS runs the screens at your church: kids-room curriculum, lobby signage and Sunday slides, scheduled from the web and controlled from your phone."
# ----------------------------------------------------------------------------------------------------

NAV = [("/features/", "Features"), ("/how-it-works/", "How it works"), ("/for-churches/", "For churches"),
       ("/pricing/", "Pricing"), ("/support/", "Support")]

PAGES = {  # source file -> URL path
    "index.html": "/", "features.html": "/features/", "how-it-works.html": "/how-it-works/",
    "for-churches.html": "/for-churches/", "pricing.html": "/pricing/", "support.html": "/support/",
    "404.html": "/404.html",
}

def png_size(name):
    with open(os.path.join(STATIC, "assets", "img", name + ".png"), "rb") as f:
        d = f.read(24)
    return struct.unpack(">II", d[16:24])

def pic(m):
    eager = m.group(1) == "!"
    parts = m.group(2).split("|")
    name, alt = parts[0], parts[1]
    w, h = png_size(name)
    load = 'fetchpriority="high" decoding="async"' if eager else 'loading="lazy" decoding="async"'
    return (f'<picture><source srcset="/assets/img/{name}.webp" type="image/webp">'
            f'<img src="/assets/img/{name}.png" width="{w}" height="{h}" alt="{html.escape(alt, quote=True)}" {load}></picture>')

def parse(src):
    m = re.match(r"\s*<!--(.*?)-->\s*(.*)", src, re.S)
    meta = {}
    for line in m.group(1).strip().splitlines():
        k, v = line.split(":", 1); meta[k.strip()] = v.strip()
    return meta, m.group(2)

def header(path):
    cur = ' aria-current="page"'
    links = "".join(f'<a href="{p}"{cur if path == p else ""}>{t}</a>' for p, t in NAV)
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="site-header"><div class="wrap">
<a class="brand" href="/"><img src="/assets/img/logo-mark.png" width="36" height="36" alt="">Church TV OS</a>
<button class="menu-btn" type="button" aria-expanded="false" aria-controls="nav">Menu</button>
<nav class="nav" id="nav" aria-label="Main">{links}<a class="btn sm" href="{APP}">Free trial</a></nav>
</div></header>'''

def footer():
    return f'''<footer class="site-footer"><div class="wrap">
<div class="foot">
<div><a class="brand" href="/"><img src="/assets/img/logo-mark.png" width="36" height="36" alt="">Church TV OS</a>
<p>Screens for kids rooms, lobbies and sanctuaries, run from your phone.</p></div>
<div><h2>Product</h2><ul><li><a href="/features/">Features</a></li><li><a href="/how-it-works/">How it works</a></li><li><a href="/for-churches/">For churches</a></li><li><a href="/pricing/">Pricing</a></li></ul></div>
<div><h2>Support</h2><ul><li><a href="/support/">Support</a></li><li><a href="{APP}/help/">Help Center</a></li><li><a href="{APP}/delete-account.html">Delete your account</a></li><li><a href="mailto:{CONTACT}">{CONTACT}</a></li></ul></div>
<div><h2>Get started</h2><ul><li><a href="{APP}">Free trial</a></li><li><a href="{APP}">Sign in</a></li><li><a href="{APP}/privacy.html">Privacy</a></li><li><a href="{APP}/terms.html">Terms</a></li></ul></div>
</div>
<p class="legal">&copy; {datetime.date.today().year} Church TV OS. Made for church staff and volunteers.</p>
</div></footer>'''

def jsonld(path, body):
    out = []
    if path == "/":
        out.append({"@context": "https://schema.org", "@type": "Organization", "name": SITE_NAME, "url": DOMAIN + "/",
                    "logo": DOMAIN + "/icon-512.png", "description": DEFAULT_DESC})
        out.append({"@context": "https://schema.org", "@type": "WebSite", "name": SITE_NAME, "url": DOMAIN + "/"})
        out.append({"@context": "https://schema.org", "@type": "SoftwareApplication", "name": SITE_NAME,
                    "applicationCategory": "BusinessApplication",
                    "operatingSystem": "Web, Fire OS, Android TV, Google TV, iOS, iPadOS, macOS",
                    "description": "Manage kids-room curriculum, lobby signage and Sunday slides on church TVs, scheduled from the web and controlled from a phone.",
                    "url": DOMAIN + "/", "image": DOMAIN + "/og-image.jpg",
                    "publisher": {"@type": "Organization", "name": SITE_NAME, "url": DOMAIN + "/"}})
        qa = re.findall(r"<details>\s*<summary>(.*?)</summary>\s*<div>(.*?)</div>\s*</details>", body, re.S)
        if qa:
            strip = lambda s: html.unescape(re.sub(r"<[^>]+>", "", s)).strip()
            out.append({"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
                {"@type": "Question", "name": strip(q), "acceptedAnswer": {"@type": "Answer", "text": " ".join(strip(a).split())}} for q, a in qa]})
    elif path != "/404.html":
        crumbs = [("Home", "/"), (dict(NAV).get(path, "Page"), path)]
        out.append({"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "name": n, "item": DOMAIN + p} for i, (n, p) in enumerate(crumbs)]})
    return "".join(f'<script type="application/ld+json">{json.dumps(o, ensure_ascii=False)}</script>\n' for o in out)

def render(fn, path):
    meta, body = parse(open(os.path.join(SRC, fn), encoding="utf-8").read())
    body = re.sub(r"\{\{pic(!?):([^}]*)\}\}", pic, body)
    body = body.replace("{{APP}}", APP).replace("{{CONTACT}}", CONTACT)
    title = meta["title"] if path == "/" else f'{meta["title"]} | {SITE_NAME}'
    desc = meta.get("description", DEFAULT_DESC)
    canon = DOMAIN + path
    noindex = '<meta name="robots" content="noindex">\n' if path == "/404.html" else ""
    og = f'''<meta property="og:type" content="website"><meta property="og:site_name" content="{SITE_NAME}">
<meta property="og:title" content="{html.escape(title)}"><meta property="og:description" content="{html.escape(desc)}">
<meta property="og:url" content="{canon}"><meta property="og:image" content="{DOMAIN}/og-image.jpg">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Church TV OS: a TV showing a pairing code and a phone remote controlling the screen.">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{html.escape(title)}">
<meta name="twitter:description" content="{html.escape(desc)}"><meta name="twitter:image" content="{DOMAIN}/og-image.jpg">'''
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
{noindex}{"" if path == "/404.html" else f'<link rel="canonical" href="{canon}">'}
<meta name="theme-color" content="#1b2a4a">
<link rel="icon" href="/favicon.ico" sizes="48x48"><link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" href="/assets/fonts/lato-400.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/assets/fonts/lato-900.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/assets/site.css">
{og}
{jsonld(path, body)}<script>document.documentElement.classList.add("js")</script>
</head><body>
{header(path)}
<main id="main">
{body}
</main>
{footer()}
<script src="/assets/site.js" defer></script>
</body></html>
'''

def out_path(path):
    if path == "/": return os.path.join(DIST, "index.html")
    if path == "/404.html": return os.path.join(DIST, "404.html")
    return os.path.join(DIST, path.strip("/"), "index.html")

def main():
    if os.path.isdir(DIST): shutil.rmtree(DIST)
    shutil.copytree(STATIC, DIST)
    today = datetime.date.today().isoformat()
    urls = []
    for fn, path in PAGES.items():
        out = out_path(path)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out, "w", encoding="utf-8").write(render(fn, path))
        if path != "/404.html": urls.append(path)
    open(os.path.join(DIST, "sitemap.xml"), "w").write(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
        "".join(f"  <url><loc>{DOMAIN}{u}</loc><lastmod>{today}</lastmod></url>\n" for u in urls) + "</urlset>\n")
    open(os.path.join(DIST, "robots.txt"), "w").write(f"User-agent: *\nAllow: /\n\nSitemap: {DOMAIN}/sitemap.xml\n")
    # check internal links and anchors
    bad = 0
    for fn, path in PAGES.items():
        page = open(out_path(path)).read()
        for href in re.findall(r'(?:href|src|srcset)="(/[^"#?]*)', page):
            p = os.path.join(DIST, href.lstrip("/"))
            if not (os.path.exists(p) or os.path.exists(os.path.join(p, "index.html"))):
                print("BROKEN", path, href); bad += 1
    print(f"built {len(urls)} pages (+404) to {DIST}; broken internal links: {bad}")

if __name__ == "__main__":
    main()
