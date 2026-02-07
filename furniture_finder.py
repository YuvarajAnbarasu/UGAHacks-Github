import streamlit as st
import re
import time
import platform
import concurrent.futures
from dataclasses import dataclass, field
from typing import Optional
from urllib.parse import urlparse, quote_plus, urlunparse

# ─── Imports ───
HAS_SELENIUM = False
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options as ChromeOptions
    from selenium.webdriver.chrome.service import Service as ChromeService
    HAS_SELENIUM = True
except ImportError:
    pass

HAS_WDM = False
try:
    from webdriver_manager.chrome import ChromeDriverManager
    HAS_WDM = True
except ImportError:
    pass

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

# ─── Config ───
DIMENSION_TOLERANCE = 4
MAX_PARALLEL_BROWSERS = 5  # Opens 5 Chrome instances at once for speed

# ─── Data Models ───
@dataclass
class UserInput:
    room_type: str
    furniture_type: str
    height: int
    width: int
    depth: int
    unit: str

@dataclass
class DimensionRange:
    height_min: int
    height_max: int
    width_min: int
    width_max: int
    depth_min: int
    depth_max: int

@dataclass
class ScrapedProduct:
    name: str
    image_url: str
    price: str
    link: str
    source: str = "IKEA"
    scraped_height: Optional[float] = None
    scraped_width: Optional[float] = None
    scraped_depth: Optional[float] = None
    fit_reasons: list[str] = field(default_factory=list)

# ─── Helper Functions ───
def clean_url(url: str) -> str:
    try:
        parsed = urlparse(url)
        return urlunparse((parsed.scheme, parsed.netloc, parsed.path, '', '', ''))
    except: return url

# ─── Driver Creation ───
def create_driver():
    opts = ChromeOptions()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--window-size=1920,1080")
    opts.add_argument("--log-level=3")
    opts.page_load_strategy = 'eager'  # Don't wait for full load
    
    try:
        return webdriver.Chrome(options=opts)
    except:
        if HAS_WDM:
            try:
                service = ChromeService(ChromeDriverManager().install())
                return webdriver.Chrome(service=service, options=opts)
            except: pass
    return None

# ─── Scraping Logic ───
def extract_dimensions_from_text(text: str) -> dict:
    dims = {"height": None, "width": None, "depth": None}
    if not text: return dims
    
    # Generic HxWxD regex
    triplet = re.findall(r'(\d+(?:\.\d+)?)[^0-9a-z]*[xX][^0-9a-z]*(\d+(?:\.\d+)?)[^0-9a-z]*[xX][^0-9a-z]*(\d+(?:\.\d+)?)', text)
    if triplet:
        vals = sorted([float(x) for x in triplet[0]])
        dims["depth"], dims["height"], dims["width"] = vals[0], vals[1], vals[2]
    return dims

def fetch_search_results(query, max_items):
    """Phase 1: Get list of product links from search page"""
    driver = create_driver()
    if not driver: return []
    
    links = []
    try:
        q = quote_plus(query)
        url = f"https://www.ikea.com/us/en/search/?q={q}"
        driver.get(url)
        time.sleep(1.0) # Short wait for JS
        
        soup = BeautifulSoup(driver.page_source, "html.parser")
        seen_urls = set()
        
        for a in soup.find_all('a', href=True):
            href = a['href']
            # IKEA product pattern
            if "ikea.com" in href and "/p/" in href:
                if href.startswith('/'): href = "https://www.ikea.com" + href
                clean = clean_url(href)
                
                if clean in seen_urls: continue
                seen_urls.add(clean)
                
                title = a.get_text(strip=True)
                links.append({"url": clean, "title": title if len(title) > 3 else "IKEA Item"})
                
                if len(links) >= max_items: break
    except Exception as e:
        print(f"Search error: {e}")
    finally:
        driver.quit()
        
    return links

def fetch_product_details(link_data):
    """Phase 2: Worker function to scrape a single product page"""
    driver = create_driver()
    if not driver: return None
    
    product = None
    try:
        driver.get(link_data["url"])
        time.sleep(0.5) # Minimal wait due to eager loading
        
        page_source = driver.page_source
        
        # Extract Price
        price_match = re.search(r'\$[\d,]+\.?\d*', page_source)
        price = price_match.group(0) if price_match else "?"
        
        # Extract Image
        image_url = ""
        og_img = BeautifulSoup(page_source, "html.parser").find("meta", property="og:image")
        if og_img and og_img.get("content"): image_url = og_img["content"]
        
        # Extract Dimensions
        dims = extract_dimensions_from_text(page_source)
        
        product = ScrapedProduct(
            name=link_data["title"],
            image_url=image_url,
            price=price,
            link=link_data["url"],
            scraped_height=dims["height"],
            scraped_width=dims["width"],
            scraped_depth=dims["depth"]
        )
    except Exception as e:
        print(f"Product error {link_data['url']}: {e}")
    finally:
        driver.quit()
        
    return product

# ─── Filtering ───
def filter_products(products, constraints):
    perfect, possible = [], []
    for p in products:
        h_fit = constraints.height_min <= (p.scraped_height or -1) <= constraints.height_max
        w_fit = constraints.width_min <= (p.scraped_width or -1) <= constraints.width_max
        d_fit = constraints.depth_min <= (p.scraped_depth or -1) <= constraints.depth_max
        
        if h_fit and w_fit and d_fit:
            p.fit_reasons = ["✓ Verified Dimensions"]
            perfect.append(p)
        else:
            p.fit_reasons = ["? Check website for dimensions"]
            possible.append(p)
    return perfect, possible

def render_card(p: ScrapedProduct):
    st.markdown(f"""
    <div style="border:1px solid #ddd;border-radius:8px;padding:10px;margin-bottom:10px;background-color:#1E1E1E;">
        <img src="{p.image_url}" style="width:100%;height:180px;object-fit:cover;border-radius:4px;">
        <h4 style="margin:10px 0 5px 0;font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{p.name}</h4>
        <div style="font-weight:bold;color:#4CAF50;font-size:18px;">{p.price}</div>
        <div style="color:#aaa;font-size:12px">Dimensions: {p.scraped_height or '?'} x {p.scraped_width or '?'} x {p.scraped_depth or '?'}</div>
        <a href="{p.link}" target="_blank" style="display:block;width:100%;text-align:center;background-color:#0051ba;color:white;padding:8px;margin-top:8px;border-radius:4px;text-decoration:none;">View on IKEA</a>
    </div>
    """, unsafe_allow_html=True)

# ─── UI ───
def main():
    st.set_page_config(page_title="IKEA Turbo", page_icon="⚡", layout="wide")
    st.title("⚡ IKEA Turbo Finder")
    
    with st.sidebar:
        st.markdown("### Status")
        st.write(f"**OS:** {platform.system()}")
        if HAS_SELENIUM: st.success("✅ Selenium Ready")
        else: st.error("❌ Selenium Missing")

    c1, c2, c3 = st.columns(3)
    with c1: room = st.selectbox("Room", ["Living Room", "Bedroom", "Studio", "Dining Room", "Home Office"])
    with c2: item = st.selectbox("Item", ["Sofa", "Coffee Table", "Bookshelf", "TV Stand", "Dining Table", "Desk"])
    with c3: unit = st.selectbox("Unit", ["Inches", "CM"])
    
    c4, c5, c6 = st.columns(3)
    with c4: w = st.number_input("Width", 10, 200, 60)
    with c5: d = st.number_input("Depth", 10, 200, 30)
    with c6: h = st.number_input("Height", 10, 200, 30)

    if st.button("🚀 Fast Search", type="primary"):
        unit_short = '"' if unit == "Inches" else "cm"
        search_term = f"{item} {w}{unit_short}"
        
        constraints = DimensionRange(
            height_min=h - DIMENSION_TOLERANCE, height_max=h + DIMENSION_TOLERANCE,
            width_min=w - DIMENSION_TOLERANCE, width_max=w + DIMENSION_TOLERANCE,
            depth_min=d - DIMENSION_TOLERANCE, depth_max=d + DIMENSION_TOLERANCE,
        )
        
        progress_bar = st.progress(0)
        status = st.empty()
        
        # 1. Search Phase
        status.write("🔍 Searching IKEA catalog...")
        links = fetch_search_results(search_term, max_items=6)
        
        if not links:
            st.warning("No products found in initial search.")
            return

        # 2. Parallel Scraping Phase
        status.write(f"⚡ Visiting {len(links)} product pages simultaneously...")
        progress_bar.progress(20)
        
        full_products = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_PARALLEL_BROWSERS) as executor:
            future_to_link = {executor.submit(fetch_product_details, link): link for link in links}
            
            completed = 0
            for future in concurrent.futures.as_completed(future_to_link):
                p = future.result()
                if p: full_products.append(p)
                completed += 1
                progress_bar.progress(20 + int((completed/len(links))*80))
        
        status.empty()
        progress_bar.empty()
        
        perfect, possible = filter_products(full_products, constraints)
        
        if perfect:
            st.success(f"Found {len(perfect)} perfect fits!")
            cols = st.columns(3)
            for i, p in enumerate(perfect):
                with cols[i % 3]: render_card(p)
        
        if possible:
            st.info(f"Found {len(possible)} potential matches")
            cols = st.columns(3)
            for i, p in enumerate(possible):
                with cols[i % 3]: render_card(p)

if __name__ == "__main__":
    main()
