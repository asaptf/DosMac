#!/usr/bin/env python3
"""Build the GitHub Pages site from the project's privacy/support documents."""
import argparse
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
from string import Template
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT / 'build/website')
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or output in (ROOT / 'website', ROOT / 'docs'):
    raise SystemExit('Choose a separate generated output directory')
config = json.loads((ROOT / 'website/site.json').read_text())
template = Template((ROOT / 'website/templates/page.html').read_text())


def link_target(target):
    parts = urlsplit(target)
    if parts.scheme:
        if parts.scheme not in ('https', 'http', 'mailto'):
            raise ValueError('Unsupported link scheme')
        return target
    path = parts.path
    if path.endswith('.md'):
        name = Path(path).name
        if name in ('privacy.md', 'support.md'):
            path = '../' + name[:-3] + '/'
        elif name == 'README.md':
            path = config['repository'] + '/blob/main/README.md'
        else:
            path = config['repository'] + '/blob/main/docs/' + name
    return urlunsplit(('', '', path, parts.query, parts.fragment))


def inline(value):
    chunks, start = [], 0
    for match in re.finditer(r'`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)', value):
        chunks.append(html.escape(value[start:match.start()]))
        if match.group(1) is not None:
            chunks.append('<code>' + html.escape(match.group(1)) + '</code>')
        else:
            chunks.append('<a href="' + html.escape(link_target(match.group(3)), quote=True) + '">' + html.escape(match.group(2)) + '</a>')
        start = match.end()
    chunks.append(html.escape(value[start:]))
    return ''.join(chunks)


def document(path):
    blocks, paragraph, headings = [], [], []
    def flush():
        if paragraph:
            text = ' '.join(paragraph)
            style = ' class="updated"' if text.startswith('Last updated:') else ''
            blocks.append('<p' + style + '>' + inline(text) + '</p>')
            paragraph.clear()
    for line in path.read_text().splitlines():
        heading = re.match(r'^(#{1,3})\s+(.+)$', line)
        if heading:
            flush()
            level, title = len(heading[1]), heading[2]
            if level == 1:
                continue
            anchor = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')
            blocks.append(f'<h{level} id="{anchor}">' + inline(title) + f'</h{level}>')
            if level == 2:
                headings.append((anchor, title))
        elif not line.strip():
            flush()
        else:
            paragraph.append(line.strip())
    flush()
    return '\n'.join(blocks), headings


def render(route, title, description, content, page_class=''):
    base = '..' if route else '.'
    destination = output / route
    destination.mkdir(parents=True, exist_ok=True)
    source = template.substitute(
        title=html.escape(title, quote=True), description=html.escape(description, quote=True),
        canonical=html.escape(config['url'] + (route + '/' if route else ''), quote=True),
        base=base, content=content, page_class=page_class,
        nav_home='aria-current="page"' if not route else '',
        nav_privacy='aria-current="page"' if route == 'privacy' else '',
        nav_support='aria-current="page"' if route == 'support' else '')
    (destination / 'index.html').write_text(source)


(output / 'assets').mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / 'website/assets/site.css', output / 'assets/site.css')
shutil.copy2(ROOT / 'Sources/DosMacApp/Resources/Assets.xcassets/AppIcon.appiconset/mac-128@2x.png', output / 'assets/icon.png')
render('', 'DosMac — Your classic workspace', 'A retro PC workspace for Mac. Privacy, support and the open-source DosMac project.', (ROOT / 'website/home.html').read_text())
for route, title, description in [
    ('privacy', 'Privacy policy', 'How DosMac handles local files, guest computers, external services and your privacy.'),
    ('support', 'Support', 'Documentation, troubleshooting and support for DosMac.'),
]:
    body, headings = document(ROOT / 'docs' / (route + '.md'))
    toc = ''
    if headings:
        entries = ''.join(f'<li><a href="#{anchor}">{html.escape(text)}</a></li>' for anchor, text in headings)
        toc = '<aside class="toc" aria-label="On this page"><p>On this page</p><ul>' + entries + '</ul></aside>'
    content = '<div class="document-wrap"><header class="document-header"><p class="eyebrow">DosMac / ' + title + '</p><h1>' + title + '</h1></header><div class="document-grid">' + toc + '<article class="document-body">' + body + '</article></div></div>'
    render(route, title + ' — DosMac', description, content, route + '-page')
(output / '.nojekyll').write_text('')
(output / 'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: ' + config['url'] + 'sitemap.xml\n')
urls = ''.join('<url><loc>' + html.escape(config['url'] + path) + '</loc></url>' for path in ['', 'privacy/', 'support/'])
(output / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + urls + '</urlset>\n')
# A real static fallback, with an absolute project URL at arbitrary missing paths.
not_found = template.substitute(title='Page not found — DosMac', description='Return to the DosMac project site.', canonical=config['url'], base=config['url'].rstrip('/'), page_class='', content='<section class="not-found wrap"><p class="eyebrow">404</p><h1>Page not found.</h1><p>The page may have moved. Visit the overview, privacy policy or support page using the navigation above.</p></section>', nav_home='', nav_privacy='', nav_support='')
(output / '404.html').write_text(not_found)


class PageCheck(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.h1, self.main = set(), [], 0, 0
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if 'id' in values:
            if values['id'] in self.ids: raise ValueError('Duplicate HTML id')
            self.ids.add(values['id'])
        self.h1 += tag == 'h1'
        self.main += tag == 'main'
        for key in ('href', 'src'):
            if key in values: self.links.append(values[key])
        if tag in ('script', 'form'): raise ValueError('Unexpected script or form in the static privacy site')


for page in output.rglob('*.html'):
    check = PageCheck()
    check.feed(page.read_text())
    if check.h1 != 1 or check.main != 1: raise ValueError('Expected one h1 and one main per page')
    for target in check.links:
        parts = urlsplit(target)
        if parts.scheme or parts.netloc: continue
        if parts.path:
            path = (page.parent / parts.path).resolve()
            if path.is_dir(): path /= 'index.html'
            if not path.is_relative_to(output) or not path.is_file(): raise ValueError('Broken local link: ' + target)
        elif parts.fragment and parts.fragment not in check.ids:
            raise ValueError('Broken page anchor: ' + target)
print('Built and checked 4 static pages:', output)
