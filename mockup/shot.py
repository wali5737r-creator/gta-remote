import sys
from playwright.sync_api import sync_playwright
name = sys.argv[1]
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width':920,'height':540})
    pg.goto(f'file:///home/hatch/workspace/gta-remote-app/mockup/{name}.html')
    pg.wait_for_timeout(400)
    pg.locator('.phone').screenshot(path=f'/home/hatch/workspace/gta-remote-app/mockup/{name}.png')
    b.close()
print('ok')
