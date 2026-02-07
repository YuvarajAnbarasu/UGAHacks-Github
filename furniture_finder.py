import re
import time
import concurrent.futures
from dataclasses import dataclass
from typing import Optional
from urllib.parse import quote_plus, urlparse, urlunparse

try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options as ChromeOptions
    from selenium.webdriver.chrome.service import Service as ChromeService
except ImportError as e:
    print(f"ERROR: {e}")
    print("Run: pip install selenium")
    exit(1)

try:
    from webdriver_manager.chrome import ChromeDriverManager
    HAS_WDM = True
except ImportError:
    HAS_WDM = False

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("ERROR: BeautifulSoup not installed")
    print("Run: pip install beautifulsoup4")
    exit(1)

MAX_PARALLEL_BROWSERS = 5
SEARCH_POOL_SIZE = 10  # Always check 10 products to find best match

@dataclass
class ScrapedProduct:
    name: str
    image_url: str
    link: str
    color: Optional[str] = None
    scraped_width: Optional[float] = None
    scraped_depth: Optional[float] = None
    scraped_height: Optional[float] = None
    distance_score: float = float('inf')

def clean_url(url: str) -> str:
    try:
        parsed = urlparse(url)
        return urlunparse((parsed.scheme, parsed.netloc, parsed.path, '', '', ''))
    except:
        return url

def calculate_distance(target_w, target_d, target_h, actual_w, actual_d, actual_h):
    """Calculate 3D Euclidean distance between target and actual dimensions"""
    if actual_w is None or actual_d is None or actual_h is None:
        return float('inf')
    
    w_diff = (target_w - actual_w) ** 2
    d_diff = (target_d - actual_d) ** 2
    h_diff = (target_h - actual_h) ** 2
    
    return (w_diff + d_diff + h_diff) ** 0.5

def create_driver():
    opts = ChromeOptions()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--window-size=1920,1080")
    opts.add_argument("--log-level=3")
    opts.page_load_strategy = 'eager'
    
    try:
        return webdriver.Chrome(options=opts)
    except:
        if HAS_WDM:
            try:
                service = ChromeService(ChromeDriverManager().install())
                return webdriver.Chrome(service=service, options=opts)
            except:
                pass
    return None

def extract_color(text: str) -> Optional[str]:
    """Extract color from product page text"""
    color_patterns = [
        r'(?:Color|Colour):\s*([A-Za-z\s]+?)(?:\n|<|,|\.|$)',
        r'Available in:\s*([A-Za-z\s]+?)(?:\n|<|,|\.|$)',
        r'(?:Finish|Shade):\s*([A-Za-z\s]+?)(?:\n|<|,|\.|$)',
    ]
    
    for pattern in color_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            color = match.group(1).strip()
            if len(color) > 2 and len(color) < 30:
                return color
    
    return None

def extract_dimensions_from_text(text: str) -> dict:
    """Extract W x D x H dimensions (IKEA standard format)"""
    dims = {"width": None, "depth": None, "height": None}
    if not text:
        return dims
    
    # Look for dimension patterns: WxDxH
    patterns = [
        r'(\d+(?:\.\d+)?)\s*(?:"|cm|in)?\s*[xX×]\s*(\d+(?:\.\d+)?)\s*(?:"|cm|in)?\s*[xX×]\s*(\d+(?:\.\d+)?)\s*(?:"|cm|in)?',
        r'Width[:\s]+(\d+(?:\.\d+)?)',
        r'Depth[:\s]+(\d+(?:\.\d+)?)',
        r'Height[:\s]+(\d+(?:\.\d+)?)',
    ]
    
    triplet_match = re.search(patterns[0], text)
    if triplet_match:
        dims["width"] = float(triplet_match.group(1))
        dims["depth"] = float(triplet_match.group(2))
        dims["height"] = float(triplet_match.group(3))
        return dims
    
    width_match = re.search(patterns[1], text, re.IGNORECASE)
    depth_match = re.search(patterns[2], text, re.IGNORECASE)
    height_match = re.search(patterns[3], text, re.IGNORECASE)
    
    if width_match:
        dims["width"] = float(width_match.group(1))
    if depth_match:
        dims["depth"] = float(depth_match.group(1))
    if height_match:
        dims["height"] = float(height_match.group(1))
    
    return dims

def fetch_search_results(query, max_items):
    """Phase 1: Get list of product links from search page"""
    driver = create_driver()
    if not driver:
        return []
    
    links = []
    try:
        q = quote_plus(query)
        url = f"https://www.ikea.com/us/en/search/?q={q}"
        driver.get(url)
        time.sleep(1.5)
        
        soup = BeautifulSoup(driver.page_source, "html.parser")
        seen_urls = set()
        
        for a in soup.find_all('a', href=True):
            href = a['href']
            if "ikea.com" in href and "/p/" in href:
                if href.startswith('/'):
                    href = "https://www.ikea.com" + href
                clean = clean_url(href)
                
                if clean in seen_urls:
                    continue
                seen_urls.add(clean)
                
                title = a.get_text(strip=True)
                links.append({
                    "url": clean,
                    "title": title if len(title) > 3 else "IKEA Item"
                })
                
                if len(links) >= max_items:
                    break
    except Exception as e:
        print(f"Search error: {e}")
    finally:
        driver.quit()
    
    return links

def fetch_product_details(link_data, target_w, target_d, target_h):
    """Phase 2: Worker function to scrape a single product page"""
    driver = create_driver()
    if not driver:
        return None
    
    product = None
    try:
        driver.get(link_data["url"])
        time.sleep(0.5)
        page_source = driver.page_source
        soup = BeautifulSoup(page_source, "html.parser")

        image_url = ""
        og_img = soup.find("meta", property="og:image")
        if og_img and og_img.get("content"):
            image_url = og_img["content"]

        color = extract_color(page_source)
        
        dims = extract_dimensions_from_text(page_source)
        
        distance = calculate_distance(
            target_w, target_d, target_h,
            dims["width"], dims["depth"], dims["height"]
        )
        
        product = ScrapedProduct(
            name=link_data["title"],
            image_url=image_url,
            link=link_data["url"],
            color=color,
            scraped_width=dims["width"],
            scraped_depth=dims["depth"],
            scraped_height=dims["height"],
            distance_score=distance
        )
    except Exception as e:
        print(f"Product error: {e}")
    finally:
        driver.quit()
    
    return product

def find_ikea_match(item: str, color: str, width: float, depth: float, height: float):
    """
    Find the closest IKEA product match.
    
    Args:
        item: Item type (e.g., 'bookshelf', 'coffee table')
        color: Color preference (e.g., 'white', 'black')
        width: Width in inches (W in W x D x H)
        depth: Depth in inches (D in W x D x H)
        height: Height in inches (H in W x D x H)
    
    Returns:
        dict with 'image_url' and 'link', or None if no match found
    """

    search_term = f"{color} {item}".strip()

    links = fetch_search_results(search_term, max_items=SEARCH_POOL_SIZE)
    
    if not links:
        return None

    products = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_PARALLEL_BROWSERS) as executor:
        futures = [
            executor.submit(fetch_product_details, link, width, depth, height)
            for link in links
        ]
        
        for future in concurrent.futures.as_completed(futures):
            p = future.result()
            if p and p.scraped_width is not None:
                products.append(p)
    
    if not products:
        return None

    best_match = min(products, key=lambda p: p.distance_score)
    
    return {
        "image_url": best_match.image_url,
        "link": best_match.link
    }

if __name__ == "__main__":
    result = find_ikea_match(
        item="bookshelf",
        color="white",
        width=30.0,
        depth=15.0,
        height=60.0
    )
    
    if result:
        print(result["image_url"])
        print(result["link"])
    else:
        print("No match found")
