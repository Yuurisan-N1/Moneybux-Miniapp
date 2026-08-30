import sys
import json
import asyncio
import hmac
import hashlib
import random
import string
import re
import signal
import time
from urllib.parse import quote

import aiohttp
from bs4 import BeautifulSoup
from colorama import Fore, Style, init

from utils.banner import show_banner

init(autoreset=True)

MY_PROJECT = "Money Bux"

G = Fore.GREEN + Style.BRIGHT
Y = Fore.YELLOW + Style.BRIGHT
R = Fore.RED + Style.BRIGHT

BASE_URL = "https://money-bux.pro"
SECRET_KEY = "rAhET?)8–x6hx6^L"
REFERRAL_ID = "r_6004380466"
ADS_MAX_WHEEL = 50
ADS_MAX_TREASURY = 50
ADS_MAX_RAIDERS = 50

BASE_HEADERS = {
    "Accept": "*/*",
    "Accept-Language": "en,en-ID;q=0.9,ja-JP;q=0.8,ja;q=0.7,id-ID;q=0.6,id;q=0.5,en-US;q=0.4",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "Origin": BASE_URL,
    "Pragma": "no-cache",
    "Referer": f"https://money-bux.pro/?tgWebAppStartParam={REFERRAL_ID}",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-origin",
    "User-Agent": "Mozilla/5.0 (Linux; Android 16; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.18 Mobile Safari/537.36 Telegram-Android/12.8.1 (Oppo CPH2631; Android 16; SDK 36; HIGH)",
    "X-Requested-With": "XMLHttpRequest",
    "sec-ch-ua": '"Not=A?Brand";v="99", "Android WebView";v="151", "Chromium";v="151"',
    "sec-ch-ua-mobile": "?1",
    "sec-ch-ua-platform": '"Android"',
}


def log_ok(msg):
    print(G + msg)


def log_warn(msg):
    print(Y + msg)


def log_err(msg):
    print(R + msg)


def load_config():
    with open("config.json") as f:
        return json.load(f)


def load_accounts():
    with open("data.txt") as f:
        return [l.strip() for l in f.read().splitlines() if l.strip()]


def generate_nonce(length=32):
    return "".join(random.choice(string.ascii_letters + string.digits) for _ in range(length))


def create_signature(payload):
    return hmac.new(
        SECRET_KEY.encode(),
        payload.encode(),
        hashlib.sha256,
    ).digest().hex()


def build_signed_payload(validation_hash, phpsessid):
    timestamp = int(time.time())
    nonce = generate_nonce()
    payload = f"{validation_hash}:{phpsessid}:{timestamp}:{nonce}"
    signature = create_signature(payload)
    return payload, signature


async def get_session(session, init_data):
    clean_data = re.split(r'&tgUplineId=', init_data)[0]
    body = f"initData={quote(clean_data)}&tgUplineId={REFERRAL_ID}"
    async with session.post(
        f"{BASE_URL}/authorization",
        headers={**BASE_HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
        data=body,
    ) as resp:
        phpsessid = None
        for cookie in resp.cookies.values():
            if cookie.key == "PHPSESSID":
                phpsessid = cookie.value
                break
        if not phpsessid:
            set_cookie = resp.headers.get("Set-Cookie", "")
            m = re.search(r"PHPSESSID=([^;]+)", set_cookie)
            if m:
                phpsessid = m.group(1)
        try:
            raw = await resp.text()
            if resp.status >= 400 or not raw.strip():
                return None, 0, 0
            data = json.loads(raw)
            gold = str(data.get("gold", 0)).replace(",", "")
            diamonds = str(data.get("diamonds", 0)).replace(",", "")
        except Exception:
            gold = diamonds = 0
        return phpsessid, gold, diamonds


async def process_checkin(session, phpsessid):
    async with session.post(
        f"{BASE_URL}/tasks/claimTaskReward",
        headers={**BASE_HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
        cookies={"PHPSESSID": phpsessid},
        data="category=daily&id=1&data%5Bpayload%5D=&data%5Bsignature%5D=",
    ) as resp:
        try:
            result = await resp.json(content_type=None)
            if result.get("icon") == "success":
                gold = str(result.get("gold", 0)).replace(",", "")
                diamonds = str(result.get("diamonds", 0)).replace(",", "")
                log_ok(f"Check-in claimed. Gold: {gold}  Diamonds: {diamonds}")
            else:
                log_warn("Check-in already claimed or not available.")
        except Exception:
            log_warn("Check-in response could not be parsed.")


async def fetch_game_slugs(session, phpsessid):
    async with session.post(
        f"{BASE_URL}/load/games",
        headers={**BASE_HEADERS, "Content-Length": "0"},
        cookies={"PHPSESSID": phpsessid},
    ) as resp:
        html = await resp.text()
    soup = BeautifulSoup(html, "html.parser")
    games = []
    for btn in soup.find_all("button", onclick=re.compile(r"transition\(")):
        m = re.search(r"transition\('([^']+)'\)", btn.get("onclick", ""))
        if m and m.group(1) not in ("tasks", "friends", "addTask") and m.group(1) not in games:
            games.append(m.group(1))
    return games or ["wheel", "treasury", "raiders"]


async def get_ad_hash(session, phpsessid, endpoint):
    async with session.post(
        f"{BASE_URL}{endpoint}",
        headers={**BASE_HEADERS, "Content-Length": "0"},
        cookies={"PHPSESSID": phpsessid},
    ) as resp:
        try:
            data = json.loads(await resp.text())
            return data.get("validation_hash")
        except Exception:
            return None


async def claim_ad(session, phpsessid, endpoint, v_hash):
    payload, signature = build_signed_payload(v_hash, phpsessid)
    async with session.post(
        f"{BASE_URL}{endpoint}",
        headers={**BASE_HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
        cookies={"PHPSESSID": phpsessid},
        data={"data[payload]": payload, "data[signature]": signature},
    ) as resp:
        try:
            return json.loads(await resp.text())
        except Exception:
            return {}


async def fetch_game_page(session, phpsessid, slug):
    async with session.post(
        f"{BASE_URL}/load/games/{slug}",
        headers={**BASE_HEADERS, "Content-Length": "0"},
        cookies={"PHPSESSID": phpsessid},
    ) as resp:
        return await resp.text()


def parse_ads_watched(html):
    soup = BeautifulSoup(html, "html.parser")
    el = soup.find("span", id="adsWatchedToday")
    try:
        return int(el.get_text(strip=True)) if el else 0
    except Exception:
        return 0


def parse_spins(html):
    soup = BeautifulSoup(html, "html.parser")
    el = soup.find("span", id="spinsCount")
    try:
        return int(el.get_text(strip=True)) if el else 0
    except Exception:
        return 0


def parse_keys(html):
    soup = BeautifulSoup(html, "html.parser")
    el = soup.find("span", id="keysCount")
    try:
        return int(el.get_text(strip=True)) if el else 0
    except Exception:
        return 0


async def process_wheel(session, phpsessid):
    log_ok("Fetching Spin Wheel game info")
    html = await fetch_game_page(session, phpsessid, "wheel")
    ads_watched = parse_ads_watched(html)
    spins = parse_spins(html)
    remaining_ads = ADS_MAX_WHEEL - ads_watched
    log_ok(f"Spin Wheel: {spins} spins available. Ads watched today: {ads_watched} out of {ADS_MAX_WHEEL}")

    if remaining_ads > 0:
        log_warn(f"Collecting {remaining_ads} ad reward(s) for Spin Wheel")
        for i in range(remaining_ads):
            v_hash = await get_ad_hash(session, phpsessid, "/games/wheel/getAdSpins")
            if not v_hash:
                log_err(f"Ad {i + 1}: Failed to obtain validation hash. Stopping ad collection.")
                break
            result = await claim_ad(session, phpsessid, "/games/wheel/getAdSpins", v_hash)
            if result.get("icon") == "success":
                log_ok(f"Wheel ad {i + 1} claimed. Spins: {str(result.get('spins_count', 0)).replace(',', '')}  Gold: {str(result.get('gold', 0)).replace(',', '')}  Ads watched: {result.get('ads_watched_today', 0)}")
            else:
                log_err(f"Wheel ad {i + 1} claim failed. Stopping ad collection.")
                break
    else:
        log_warn("Spin Wheel ad quota already maxed for today")

    html2 = await fetch_game_page(session, phpsessid, "wheel")
    total_spins = parse_spins(html2)
    log_warn(f"Spinning wheel. Available spins: {total_spins}")

    if total_spins <= 0:
        log_warn("No spins available. Skipping spin phase.")
        log_ok(f"Spin Wheel complete. Total spins executed: 0")
        return

    spun = 0
    while True:
        async with session.post(
            f"{BASE_URL}/games/wheel/startRotation",
            headers={**BASE_HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
            cookies={"PHPSESSID": phpsessid},
            data="multiplier=1",
        ) as resp:
            try:
                result = await resp.json(content_type=None)
            except Exception:
                result = {}
        if not result or result.get("icon") == "error":
            log_err("No spins remaining or spin failed. Ending spin phase.")
            break
        spun += 1
        gold_val = str(result.get("gold", 0)).replace(",", "")
        spins_left = str(result.get("spins_count", 0)).replace(",", "")
        log_ok(f"Spin {spun} completed. Gold: {gold_val}  Spins left: {spins_left}")
        try:
            if int(spins_left) <= 0:
                break
        except Exception:
            break

    log_ok(f"Spin Wheel complete. Total spins executed: {spun}")


async def process_treasury(session, phpsessid):
    log_ok("Fetching Treasury game info")
    html = await fetch_game_page(session, phpsessid, "treasury")
    ads_watched = parse_ads_watched(html)
    keys = parse_keys(html)
    remaining_ads = ADS_MAX_TREASURY - ads_watched
    log_ok(f"Treasury: {keys} keys available. Ads watched today: {ads_watched} out of {ADS_MAX_TREASURY}")

    if remaining_ads > 0:
        log_warn(f"Collecting {remaining_ads} ad reward(s) for Treasury")
        for i in range(remaining_ads):
            v_hash = await get_ad_hash(session, phpsessid, "/games/treasury/getAdKeys")
            if not v_hash:
                log_err(f"Ad {i + 1}: Failed to obtain validation hash. Stopping ad collection.")
                break
            result = await claim_ad(session, phpsessid, "/games/treasury/getAdKeys", v_hash)
            if result.get("icon") == "success":
                log_ok(f"Treasury ad {i + 1} claimed. Gold: {str(result.get('gold', 0)).replace(',', '')}  Ads watched: {result.get('ads_watched_today', 0)}")
            else:
                log_err(f"Treasury ad {i + 1} claim failed. Stopping ad collection.")
                break
    else:
        log_warn("Treasury ad quota already maxed for today")

    html2 = await fetch_game_page(session, phpsessid, "treasury")
    total_keys = parse_keys(html2)
    log_warn(f"Opening chests. Available keys: {total_keys}")

    if total_keys <= 0:
        log_warn("No keys available. Skipping chest phase.")
        log_ok(f"Treasury complete. Total chests opened: 0")
        return

    opened = 0
    while True:
        async with session.post(
            f"{BASE_URL}/games/treasury/openChest",
            headers={**BASE_HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"},
            cookies={"PHPSESSID": phpsessid},
            data="multiplier=1",
        ) as resp:
            try:
                result = await resp.json(content_type=None)
            except Exception:
                result = {}
        if not result or result.get("icon") == "error":
            log_err("Chest open failed or no keys remaining. Ending chest phase.")
            break
        opened += 1
        keys_left = result.get("keys_count", 0)
        loot = result.get("loot_amount", {})
        loot_str = " and ".join(str(v) for v in loot.values()) if loot else "0"
        gold_val = str(result.get("gold", 0)).replace(",", "")
        diamonds_val = str(result.get("diamonds", 0)).replace(",", "")
        keys_val = str(keys_left).replace(",", "")
        log_ok(f"Chest {opened} opened. Loot: {loot_str}  Gold: {gold_val}  Diamonds: {diamonds_val}  Keys left: {keys_val}")
        try:
            if int(keys_val) <= 0:
                break
        except Exception:
            break

    log_ok(f"Treasury complete. Total chests opened: {opened}")


async def process_raiders(session, phpsessid):
    log_ok("Fetching Raiders game info")
    html = await fetch_game_page(session, phpsessid, "raiders")
    ads_watched = parse_ads_watched(html)
    remaining_ads = ADS_MAX_RAIDERS - ads_watched
    log_ok(f"Raiders: Ads watched today: {ads_watched} out of {ADS_MAX_RAIDERS}")

    if remaining_ads <= 0:
        log_warn("Raiders ad quota already maxed for today")
        return

    log_warn(f"Collecting {remaining_ads} ad reward(s) for Raiders")
    for i in range(remaining_ads):
        v_hash = await get_ad_hash(session, phpsessid, "/games/raiders/getAdRaidPasses")
        if not v_hash:
            log_err(f"Ad {i + 1}: Failed to obtain validation hash. Stopping ad collection.")
            break
        result = await claim_ad(session, phpsessid, "/games/raiders/getAdRaidPasses", v_hash)
        if result.get("icon") == "success":
            log_ok(f"Raiders ad {i + 1} claimed. Gold: {str(result.get('gold', 0)).replace(',', '')}  Ads watched: {result.get('ads_watched_today', 0)}")
        else:
            log_err(f"Raiders ad {i + 1} claim failed. Stopping ad collection.")
            break

    log_ok("Raiders complete.")


GAME_HANDLERS = {
    "wheel": process_wheel,
    "treasury": process_treasury,
    "raiders": process_raiders,
}


async def process_account(index, init_data):
    log_warn(f"Processing account {index + 1}")
    async with aiohttp.ClientSession() as session:
        phpsessid, gold, diamonds = await get_session(session, init_data)
        if not phpsessid:
            log_err(f"Authentication failed for account {index + 1}. Skipping.")
            return
        log_ok(f"Session acquired. Gold: {gold}  Diamonds: {diamonds}")

        await process_checkin(session, phpsessid)

        log_ok("Fetching available games from server")
        games = await fetch_game_slugs(session, phpsessid)
        log_ok(f"Games detected: {', '.join(games)}")

        for slug in games:
            if slug in GAME_HANDLERS:
                await GAME_HANDLERS[slug](session, phpsessid)
            else:
                log_warn(f"Game slug not handled: {slug}. Skipping.")

    log_ok(f"Account {index + 1} processing complete.")


async def countdown(seconds):
    while seconds > 0:
        h = seconds // 3600
        m = (seconds % 3600) // 60
        s = seconds % 60
        print(Y + f"Next cycle in: {h:02d}:{m:02d}:{s:02d}", end="\r", flush=True)
        await asyncio.sleep(1)
        seconds -= 1
    print(" " * 40, end="\r")


async def main():
    config = load_config()
    sleep_seconds = config["settings"]["sleep_seconds"]

    cycle = 0
    while True:
        cycle += 1
        show_banner(MY_PROJECT)
        log_ok(f"Starting automation cycle {cycle}")

        accounts = load_accounts()
        log_ok(f"Loaded {len(accounts)} account(s) from data.txt")

        for idx, init_data in enumerate(accounts):
            await process_account(idx, init_data)
            if idx < len(accounts) - 1:
                print()

        print()
        log_ok(f"All accounts processed. Cycle {cycle} complete.")
        await countdown(sleep_seconds)


def handle_exit(sig, frame):
    print()
    print(R + "Script stopped by user.")
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)
    asyncio.run(main())