import asyncio, os
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as pw:
        b=await pw.chromium.launch(channel='chrome')
        pg=await b.new_page(device_scale_factor=1)
        await pg.goto('file://'+os.path.abspath('art.html')); await pg.evaluate("document.fonts.ready")
        os.makedirs('out',exist_ok=True)
        for n in ['capsule','header','hero','logo','icon']:
            w,h=await pg.evaluate(f"show('{n}')"); await pg.set_viewport_size({'width':w,'height':h}); await pg.wait_for_timeout(150)
            await pg.screenshot(path=f'out/{n}.png',omit_background=True,clip={'x':0,'y':0,'width':w,'height':h})
        await b.close()
asyncio.run(main())
