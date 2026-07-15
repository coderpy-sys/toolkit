#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════════════╗
║                     VPS MANAGEMENT BOT - PROXMOX EDITION                    ║
║                   Modern Discord Bot with Proxmox VE API                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""

import discord
from discord.ext import commands, tasks
import json
import os
import logging
import asyncio
import time
import re
import sqlite3
import aiohttp
import secrets
import urllib3
from datetime import datetime
from typing import Optional

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ═══════════════════════════════════════════════════════════════════════════════
# 📝 LOGGING CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('VPSBot')

# ═══════════════════════════════════════════════════════════════════════════════
# ⚙️ CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

DISCORD_TOKEN = os.getenv('DISCORD_TOKEN', '')
BOT_NAME = os.getenv('BOT_NAME', 'Bynex Host')
PREFIX = os.getenv('PREFIX', '.')
YOUR_SERVER_IP = os.getenv('YOUR_SERVER_IP', '127.0.0.1')
MAIN_ADMIN_ID = int(os.getenv('MAIN_ADMIN_ID', '1179394335121350668'))
VPS_USER_ROLE_ID = os.getenv('VPS_USER_ROLE_ID', '1468645015009103953')

# Proxmox Configuration
PROXMOX_URL = os.getenv('PROXMOX_URL', 'https://103.43.19.30/').rstrip('/')
PROXMOX_TOKEN_ID = os.getenv('PROXMOX_TOKEN_ID', 'root@pam!bot')
PROXMOX_TOKEN_SECRET = os.getenv('PROXMOX_TOKEN_SECRET', '11b93b4d-cba1-4d3f-ae34-9f88f354ac02')
PROXMOX_NODE = os.getenv('PROXMOX_NODE', 'pve')  # auto-detected if empty
PROXMOX_STORAGE = os.getenv('PROXMOX_STORAGE', 'local-lvm')
PROXMOX_BRIDGE = os.getenv('PROXMOX_BRIDGE', 'vmbr1')

# Resource Thresholds
# Resource Thresholds
CPU_THRESHOLD = 90
RAM_THRESHOLD = 90
MINING_NOTIFY_CHANNEL = 1468645070910525704

# ═══════════════════════════════════════════════════════════════════════════════
# 🎨 MODERN THEME SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

COLORS = {
    'primary': 0x5865F2,
    'success': 0x57F287,
    'warning': 0xFEE75C,
    'error': 0xED4245,
    'info': 0x5865F2,
    'accent': 0xEB459E,
    'secondary': 0x99AAB5,
    'running': 0x57F287,
    'stopped': 0xED4245,
    'suspended': 0xFEE75C,
    'whitelisted': 0x3BA55C,
}

STATUS_EMOJI = {
    'running': '🟢',
    'stopped': '🔴',
    'suspended': '🟡',
    'unknown': '❓',
    'docker': '🐳',
}

THUMBNAIL_URL = "https://cdn.discordapp.com/icons/1405753051742208020/a18972f65914b79fe089593c638fa549.png?size=1024"

OS_OPTIONS = [
    {"label": "Ubuntu 22.04", "value": "ubuntu-22.04", "description": "Ubuntu 22.04 LTS", "emoji": "🟠"},
    {"label": "Ubuntu 24.04", "value": "ubuntu-24.04", "description": "Ubuntu 24.04 LTS", "emoji": "🟠"},
    {"label": "Debian 12", "value": "debian-12", "description": "Debian 12 Bookworm", "emoji": "🔴"},   
    {"label": "Debian 13", "value": "debian-13", "description": "Debian 13 Trixie", "emoji": "🔴"},
]

OS_TEMPLATE_MAP = {
    "ubuntu-22.04": "ubuntu-22.04-standard_22.04-1_amd64.tar.zst",
    "debian-12": "debian-12-standard_12.12-1_amd64.tar.zst",
    "ubuntu-24.04": "ubuntu-24.04-standard_24.04-2_amd64.tar.zst",
    "debian-13": "debian-13-standard_13.1-2_amd64.tar.zst",
}


# ═══════════════════════════════════════════════════════════════════════════════
# 🔌 PROXMOX API HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

_aiohttp_session: Optional[aiohttp.ClientSession] = None

async def get_session() -> aiohttp.ClientSession:
    global _aiohttp_session
    if _aiohttp_session is None or _aiohttp_session.closed:
        connector = aiohttp.TCPConnector(ssl=False)
        _aiohttp_session = aiohttp.ClientSession(connector=connector)
    return _aiohttp_session

async def proxmox_api(method: str, endpoint: str, data: dict = None) -> dict:
    session = await get_session()
    url = f"{PROXMOX_URL}/api2/json{endpoint}"
    headers = {"Authorization": f"PVEAPIToken={PROXMOX_TOKEN_ID}={PROXMOX_TOKEN_SECRET}"}
    kwargs = {"headers": headers}
    if method in ['GET', 'DELETE']:
        if data:
            kwargs["params"] = data
    elif data:
        kwargs["data"] = data
    async with getattr(session, method.lower())(url, **kwargs) as resp:
        if resp.status >= 400:
            text = await resp.text()
            raise Exception(f"Proxmox API {resp.status} on {method} {url}: {text[:300]}")
        try:
            return await resp.json()
        except:
            return {}

async def get_node_name():
    global PROXMOX_NODE
    if PROXMOX_NODE:
        return PROXMOX_NODE
    try:
        result = await proxmox_api('GET', '/nodes')
        nodes = result.get('data', [])
        if nodes:
            PROXMOX_NODE = nodes[0]['node']
            logger.info(f"Auto-detected Proxmox node: {PROXMOX_NODE}")
            return PROXMOX_NODE
    except Exception as e:
        logger.error(f"Failed to detect node: {e}")
    return PROXMOX_NODE

async def get_next_vmid():
    result = await proxmox_api('GET', '/cluster/nextid')
    return int(result['data'])

async def find_template(os_choice: str) -> Optional[str]:
    filename = OS_TEMPLATE_MAP.get(os_choice)
    if not filename:
        return None
    try:
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/storage/{PROXMOX_STORAGE}/content')
        for item in result.get('data', []):
            if filename in item.get('volid', ''):
                return item['volid']
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/storage/local/content')
        for item in result.get('data', []):
            if filename in item.get('volid', ''):
                return item['volid']
    except Exception as e:
        logger.error(f"Template search error: {e}")
    return f"local:vztmpl/{filename}"

# ═══════════════════════════════════════════════════════════════════════════════
# 👤 PROXMOX USER MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════


async def ensure_proxmox_user(discord_id: str, discord_name: str):
    pve_user = f"discord_{discord_id}@pve"
    password = secrets.token_urlsafe(16)
    try:
        # Try to create user
        await proxmox_api('POST', '/access/users', {
            'userid': pve_user,
            'password': password,
            'comment': f'Discord user: {discord_name} ({discord_id})',
            'enable': 1,
        })
        return pve_user, password, True
    except:
        # User likely exists
        return pve_user, None, False

async def reset_proxmox_user_password(discord_id: str, discord_name: str):
    pve_user = f"discord_{discord_id}@pve"
    password = secrets.token_urlsafe(16)
    raise NotImplementedError("Password reset requires root@pam authentication, not supported with API token.")

async def grant_ct_access(vmid: int, pve_user: str):
    try:
        await proxmox_api('PUT', f'/access/acl', {
            'path': f'/vms/{vmid}',
            'users': pve_user,
            'roles': 'PVEVMUser',
            'propagate': 1,
        })
    except Exception as e:
        logger.warning(f"Failed to grant access for VMID {vmid} to {pve_user}: {e}")

# ═══════════════════════════════════════════════════════════════════════════════
# 🗄️ DATABASE & DATA
# ═══════════════════════════════════════════════════════════════════════════════

DB_FILE = 'vps.db'

def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute('''CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )''')
    cur.execute('''CREATE TABLE IF NOT EXISTS vps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        container_name TEXT NOT NULL,
        vmid INTEGER,
        proxmox_user TEXT,
        ram TEXT,
        cpu TEXT,
        storage TEXT,
        config TEXT,
        os_version TEXT,
        status TEXT DEFAULT 'running',
        suspended INTEGER DEFAULT 0,
        whitelisted INTEGER DEFAULT 0,
        created_at TEXT
    )''')
    cur.execute('''CREATE TABLE IF NOT EXISTS admins (
        user_id TEXT PRIMARY KEY
    )''')
    # Migration: add vmid and proxmox_user columns if missing
    columns = [row[1] for row in cur.execute("PRAGMA table_info(vps)").fetchall()]
    if 'vmid' not in columns:
        cur.execute('ALTER TABLE vps ADD COLUMN vmid INTEGER')
    if 'proxmox_user' not in columns:
        cur.execute('ALTER TABLE vps ADD COLUMN proxmox_user TEXT')
    conn.commit()
    conn.close()

init_db()

def get_setting(key, default=None):
    conn = get_db()
    cur = conn.cursor()
    cur.execute('SELECT value FROM settings WHERE key = ?', (key,))
    row = cur.fetchone()
    conn.close()
    return row[0] if row else default

def set_setting(key, value):
    conn = get_db()
    cur = conn.cursor()
    cur.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', (key, value))
    conn.commit()
    conn.close()

# Load thresholds from DB
CPU_THRESHOLD = int(get_setting('cpu_threshold', str(CPU_THRESHOLD)))
RAM_THRESHOLD = int(get_setting('ram_threshold', str(RAM_THRESHOLD)))

# JSON data files
VPS_DATA_FILE = 'vps_data.json'
ADMIN_DATA_FILE = 'admin_data.json'

def load_json(path, default):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except:
        return default

vps_data = load_json(VPS_DATA_FILE, {})
admin_data = load_json(ADMIN_DATA_FILE, {"admins": []})

def save_vps_data():
    with open(VPS_DATA_FILE, 'w') as f:
        json.dump(vps_data, f, indent=2)

def save_admin_data():
    with open(ADMIN_DATA_FILE, 'w') as f:
        json.dump(admin_data, f, indent=2)

def get_admins():
    return admin_data.get("admins", [])

# ═══════════════════════════════════════════════════════════════════════════════
# 🤖 BOT SETUP
# ═══════════════════════════════════════════════════════════════════════════════

intents = discord.Intents.default()
intents.message_content = True
intents.members = True

bot = commands.Bot(command_prefix=PREFIX, intents=intents, help_command=None)

# ═══════════════════════════════════════════════════════════════════════════════
# 🎨 EMBED FACTORY
# ═══════════════════════════════════════════════════════════════════════════════

def create_embed(title, description="", color=None):
    color = color or COLORS['primary']
    embed = discord.Embed(title=f"✨ {BOT_NAME} • {title}", description=description, color=color, timestamp=datetime.now())
    embed.set_thumbnail(url=THUMBNAIL_URL)
    embed.set_footer(text=f"⚡ {BOT_NAME}", icon_url=THUMBNAIL_URL)
    return embed

def create_success_embed(title, description=""):
    return create_embed(title, description, COLORS['success'])

def create_error_embed(title, description=""):
    return create_embed(title, description, COLORS['error'])

def create_warning_embed(title, description=""):
    return create_embed(title, description, COLORS['warning'])

def create_info_embed(title, description=""):
    return create_embed(title, description, COLORS['info'])

def add_field(embed, name, value, inline=True):
    embed.add_field(name=name, value=str(value)[:1024], inline=inline)
    return embed

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

resource_monitor_active = False

def is_admin():
    async def predicate(ctx):
        user_id = str(ctx.author.id)
        if user_id == str(MAIN_ADMIN_ID):
            return True
        if user_id in admin_data.get("admins", []):
            return True
        raise commands.CheckFailure("You need admin permissions for this command.")
    return commands.check(predicate)

def is_main_admin():
    async def predicate(ctx):
        if str(ctx.author.id) == str(MAIN_ADMIN_ID):
            return True
        raise commands.CheckFailure("Only the main admin can use this command.")
    return commands.check(predicate)

async def get_or_create_vps_role(guild):
    if not VPS_USER_ROLE_ID:
        return None
    role = guild.get_role(int(VPS_USER_ROLE_ID))
    if not role:
        try:
            role = await guild.create_role(name=f"{BOT_NAME} VPS User", color=discord.Color(COLORS['primary']))
        except:
            return None
    return role

def get_status_display(status, suspended=False, whitelisted=False):
    emoji = STATUS_EMOJI.get(status, '❓')
    display = f"{emoji} {status.upper()}"
    if suspended:
        display += " ⚠️ SUSPENDED"
    if whitelisted:
        display += " ✅ WHITELISTED"
    return display

def get_status_color(status, suspended=False, whitelisted=False):
    if suspended:
        return COLORS['suspended']
    if whitelisted:
        return COLORS['whitelisted']
    return COLORS.get(status, COLORS['primary'])

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 CONTAINER STATISTICS (PROXMOX API)
# ═══════════════════════════════════════════════════════════════════════════════

async def get_ct_status(vmid) -> str:
    try:
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/current')
        return result.get('data', {}).get('status', 'unknown')
    except:
        return 'unknown'

async def get_ct_stats(vmid) -> dict:
    try:
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/current')
        return result.get('data', {})
    except:
        return {}

async def get_container_status(identifier) -> str:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 'unknown'
    return await get_ct_status(vmid)

async def get_container_cpu(identifier) -> str:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 'N/A'
    stats = await get_ct_stats(vmid)
    cpu = stats.get('cpu', 0)
    return f"{cpu * 100:.1f}%"

async def get_container_cpu_pct(identifier) -> float:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 0.0
    stats = await get_ct_stats(vmid)
    return stats.get('cpu', 0) * 100

async def get_container_memory(identifier) -> str:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 'N/A'
    stats = await get_ct_stats(vmid)
    mem = stats.get('mem', 0)
    maxmem = stats.get('maxmem', 1)
    if maxmem == 0:
        return 'N/A'
    used_mb = mem / (1024 * 1024)
    total_mb = maxmem / (1024 * 1024)
    pct = (mem / maxmem) * 100
    return f"{used_mb:.0f}MB / {total_mb:.0f}MB ({pct:.1f}%)"

async def get_container_ram_pct(identifier) -> float:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 0.0
    stats = await get_ct_stats(vmid)
    mem = stats.get('mem', 0)
    maxmem = stats.get('maxmem', 1)
    if maxmem == 0:
        return 0.0
    return (mem / maxmem) * 100

async def get_container_disk(identifier) -> str:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 'N/A'
    stats = await get_ct_stats(vmid)
    disk = stats.get('disk', 0)
    maxdisk = stats.get('maxdisk', 1)
    if maxdisk == 0:
        return 'N/A'
    used_gb = disk / (1024 ** 3)
    total_gb = maxdisk / (1024 ** 3)
    pct = (disk / maxdisk) * 100
    return f"{used_gb:.1f}GB / {total_gb:.1f}GB ({pct:.1f}%)"

async def get_container_uptime(identifier) -> str:
    vmid = await resolve_vmid(identifier)
    if vmid is None:
        return 'N/A'
    stats = await get_ct_stats(vmid)
    uptime_secs = stats.get('uptime', 0)
    if uptime_secs == 0:
        return 'Offline'
    days = uptime_secs // 86400
    hours = (uptime_secs % 86400) // 3600
    minutes = (uptime_secs % 3600) // 60
    parts = []
    if days > 0:
        parts.append(f"{days}d")
    if hours > 0:
        parts.append(f"{hours}h")
    parts.append(f"{minutes}m")
    return " ".join(parts)

async def resolve_vmid(identifier) -> Optional[int]:
    """Resolve a container_name or vmid to a numeric VMID."""
    if isinstance(identifier, int):
        return identifier
    if isinstance(identifier, str) and identifier.isdigit():
        return int(identifier)
    # Search vps_data by container_name
    for user_id, vps_list in vps_data.items():
        for vps in vps_list:
            if vps.get('container_name') == identifier:
                vmid = vps.get('vmid')
                if vmid:
                    return int(vmid)
    return None

def get_uptime():
    try:
        import subprocess
        result = subprocess.run(['uptime'], capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return "Unknown"

# ═══════════════════════════════════════════════════════════════════════════════
# 🤖 BOT EVENTS
# ═══════════════════════════════════════════════════════════════════════════════

@tasks.loop(minutes=5)
async def resource_monitor_task():
    await check_mining_activity()

async def check_mining_activity(ctx=None):
    try:
        global PROXMOX_NODE
        if not PROXMOX_NODE:
            await get_node_name()
        
        # Get all LXC status (efficient list call)
        lxc_list = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/lxc')
        lxc_data = lxc_list.get('data', [])
        
        suspended_count = 0
        checked_count = 0
        
        notify_channel = bot.get_channel(MINING_NOTIFY_CHANNEL)
        
        for ct in lxc_data:
            if ct.get('status') != 'running':
                continue
            
            checked_count += 1
            vmid = int(ct.get('vmid'))
            
            # 'cpu' field in /lxc list is current usage ratio (e.g. 0.05 for 5%)
            # 'maxcpu' is allocated cores
            cpu_val = ct.get('cpu', 0)
            max_cpu = ct.get('maxcpu', 1)
            
            # Calculate percentage relative to allocation
            if max_cpu > 0:
                usage_pct = (cpu_val / max_cpu) * 100
            else:
                usage_pct = 0
            
            # Check threshold
            if usage_pct > CPU_THRESHOLD:
                # Double check with specific status call to confirm (avoid transients)
                try:
                    stats = await get_ct_stats(vmid)
                    d_cpu = stats.get('cpu', 0)
                    confirmed_pct = d_cpu * 100
                    
                    if confirmed_pct > CPU_THRESHOLD:
                        logger.warning(f"High CPU on VMID {vmid}: {confirmed_pct:.1f}%")
                        
                        # Find owner in DB
                        owner_id = None
                        container_name = ct.get('name', f'CT-{vmid}')
                        
                        for uid, vlist in vps_data.items():
                            for v in vlist:
                                if int(v.get('vmid', 0)) == vmid:
                                    owner_id = uid
                                    container_name = v.get('container_name', container_name)
                                    v['status'] = 'stopped'
                                    v['suspended'] = True
                                    break
                            if owner_id: break
                        
                        save_vps_data()
                        
                        # Suspend via API
                        await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/stop')
                        
                        suspended_count += 1
                        
                        # Notify
                        if notify_channel:
                            owner_mention = f"<@{owner_id}>" if owner_id else "Unknown"
                            await notify_channel.send(f"🚨 **Suspended VPS**\n**VMID:** `{vmid}`\n**Name:** `{container_name}`\n**Owner:** {owner_mention}\n**Reason:** High CPU ({confirmed_pct:.1f}% > {CPU_THRESHOLD}%) - Potential Mining detected.")
                except Exception as e:
                    logger.error(f"Error confirming high CPU for {vmid}: {e}")

        if ctx:
            await ctx.send(embed=create_info_embed("Resource Check Complete", f"Scanned {checked_count} CTs. Suspended {suspended_count} high-usage VPS."))

    except Exception as e:
        logger.error(f"Resource check failed: {e}")
        if ctx:
             await ctx.send(embed=create_error_embed("Check Failed", str(e)))

@bot.event
async def on_ready():
    logger.info(f'{bot.user} has connected to Discord!')
    await get_node_name()
    await bot.change_presence(activity=discord.Activity(type=discord.ActivityType.watching, name=f"{BOT_NAME} VPS Manager"))
    resource_monitor_task.start()
    logger.info(f"{BOT_NAME} Bot is ready! Node: {PROXMOX_NODE}")

@bot.event
async def on_command_error(ctx, error):
    if isinstance(error, commands.CommandNotFound):
        return
    elif isinstance(error, commands.MissingRequiredArgument):
        await ctx.send(embed=create_error_embed("Missing Argument", f"Please check command usage with `{PREFIX}help`."))
    elif isinstance(error, commands.BadArgument):
        await ctx.send(embed=create_error_embed("Invalid Argument", "Please check your input and try again."))
    elif isinstance(error, commands.CheckFailure):
        error_msg = str(error) if str(error) else "You need admin permissions for this command."
        await ctx.send(embed=create_error_embed("Access Denied", error_msg))
    elif isinstance(error, discord.NotFound):
        await ctx.send(embed=create_error_embed("Error", "The requested resource was not found."))
    else:
        logger.error(f"Command error: {error}")
        await ctx.send(embed=create_error_embed("System Error", "An unexpected error occurred. Support has been notified."))

# ═══════════════════════════════════════════════════════════════════════════════
# 🤖 BOT COMMANDS - GENERAL
# ═══════════════════════════════════════════════════════════════════════════════

@bot.command(name='ping')
async def ping(ctx):
    latency = round(bot.latency * 1000)
    if latency < 100:
        status = "🟢 Excellent"
        color = COLORS['success']
    elif latency < 200:
        status = "🟡 Good"
        color = COLORS['warning']
    else:
        status = "🔴 High"
        color = COLORS['error']
    embed = discord.Embed(title=f"✨ {BOT_NAME} • Pong!", description=f"**Latency:** `{latency}ms` {status}", color=color, timestamp=datetime.now())
    embed.add_field(name="📡 Connection", value=f"WebSocket: `{latency}ms`", inline=True)
    embed.add_field(name="🖥️ Status", value="Operational ✅", inline=True)
    embed.set_thumbnail(url=THUMBNAIL_URL)
    embed.set_footer(text=f"⚡ {BOT_NAME}", icon_url=THUMBNAIL_URL)
    await ctx.send(embed=embed)

@bot.command(name='uptime')
async def uptime(ctx):
    up = get_uptime()
    embed = create_info_embed("Host Uptime", up)
    await ctx.send(embed=embed)

@bot.command(name='thresholds')
@is_admin()
async def thresholds(ctx):
    embed = create_info_embed("Resource Thresholds", f"**CPU:** {CPU_THRESHOLD}%\n**RAM:** {RAM_THRESHOLD}%")
    await ctx.send(embed=embed)

@bot.command(name='set-threshold')
@is_admin()
async def set_threshold(ctx, cpu: int, ram: int):
    global CPU_THRESHOLD, RAM_THRESHOLD
    if cpu < 0 or ram < 0:
        await ctx.send(embed=create_error_embed("Invalid Thresholds", "Thresholds must be non-negative."))
        return
    CPU_THRESHOLD = cpu
    RAM_THRESHOLD = ram
    set_setting('cpu_threshold', str(cpu))
    set_setting('ram_threshold', str(ram))
    embed = create_success_embed("Thresholds Updated", f"**CPU:** {cpu}%\n**RAM:** {ram}%")
    await ctx.send(embed=embed)

@bot.command(name='set-status')
@is_admin()
async def set_status(ctx, activity_type: str, *, name: str):
    types = {
        'playing': discord.ActivityType.playing,
        'watching': discord.ActivityType.watching,
        'listening': discord.ActivityType.listening,
        'streaming': discord.ActivityType.streaming,
    }
    if activity_type.lower() not in types:
        await ctx.send(embed=create_error_embed("Invalid Type", "Valid types: playing, watching, listening, streaming"))
        return
    await bot.change_presence(activity=discord.Activity(type=types[activity_type.lower()], name=name))
    embed = create_success_embed("Status Updated", f"Set to {activity_type}: {name}")
    await ctx.send(embed=embed)

@bot.command(name='resource-check')
@is_admin()
async def resource_check_cmd(ctx):
    await ctx.send("🔍 Scanning all VPS via Proxmox API...")
    await check_mining_activity(ctx)

@bot.command(name='myvps')
async def my_vps(ctx):
    user_id = str(ctx.author.id)
    vps_list = vps_data.get(user_id, [])
    if not vps_list:
        embed = discord.Embed(title=f"✨ {BOT_NAME} • My VPS", description="You don't have any VPS instances yet.", color=COLORS['warning'], timestamp=datetime.now())
        embed.add_field(name="🚀 Get Started", value=f"Contact an administrator to create your first VPS!\n\n**Quick Commands:**\n• `{PREFIX}manage` - Manage your VPS\n• `{PREFIX}help` - View all commands", inline=False)
        embed.set_thumbnail(url=THUMBNAIL_URL)
        embed.set_footer(text=f"⚡ {BOT_NAME}", icon_url=THUMBNAIL_URL)
        await ctx.send(embed=embed)
        return
    embed = discord.Embed(title=f"✨ {BOT_NAME} • My VPS Dashboard", description=f"You have **{len(vps_list)}** VPS instance(s)", color=COLORS['primary'], timestamp=datetime.now())
    for i, vps in enumerate(vps_list):
        status = vps.get('status', 'unknown')
        suspended = vps.get('suspended', False)
        whitelisted = vps.get('whitelisted', False)
        status_display = get_status_display(status, suspended, whitelisted)
        config = vps.get('config', 'Custom')
        vmid = vps.get('vmid', 'N/A')
        vps_info = f"""╭ **Status:** {status_display}
├ **Config:** {config}
├ **OS:** {vps.get('os_version', 'unknown')}
├ **VMID:** `{vmid}`
╰ **Container:** `{vps['container_name']}`"""
        embed.add_field(name=f"🖥️ VPS #{i+1}", value=vps_info, inline=True)
    embed.add_field(name="🎮 Quick Actions", value=f"Use `{PREFIX}manage` to control your VPS instances", inline=False)
    embed.set_thumbnail(url=THUMBNAIL_URL)
    embed.set_footer(text=f"⚡ {BOT_NAME} • VPS Dashboard", icon_url=THUMBNAIL_URL)
    await ctx.send(embed=embed)

@bot.command(name='ct-list')
@is_admin()
async def ct_list(ctx):
    try:
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/lxc')
        cts = result.get('data', [])
        if not cts:
            await ctx.send(embed=create_info_embed("CT List", "No containers found on this node."))
            return
        lines = []
        for ct in cts:
            status_emoji = '🟢' if ct.get('status') == 'running' else '🔴'
            lines.append(f"{status_emoji} **VMID {ct['vmid']}** • `{ct.get('name', 'unnamed')}` • {ct.get('status', 'unknown').upper()}")
        text = "\n".join(lines)
        chunks = [text[i:i+1024] for i in range(0, len(text), 1024)]
        for idx, chunk in enumerate(chunks, 1):
            embed = create_info_embed(f"Proxmox CT List (Part {idx})", "")
            add_field(embed, "Containers", chunk, False)
            await ctx.send(embed=embed)
    except Exception as e:
        await ctx.send(embed=create_error_embed("Error", str(e)[:500]))

@bot.command(name='templates')
@is_admin()
async def list_templates(ctx):
    try:
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/storage/local/content')
        templates = [i for i in result.get('data', []) if i.get('content') == 'vztmpl']
        if not templates:
            await ctx.send(embed=create_info_embed("Templates", "No OS templates found on local storage."))
            return
        lines = [f"📦 `{t['volid']}`" for t in templates]
        embed = create_info_embed("OS Templates", "\n".join(lines))
        await ctx.send(embed=embed)
    except Exception as e:
        await ctx.send(embed=create_error_embed("Error", str(e)[:500]))

# ═══════════════════════════════════════════════════════════════════════════════
# 🎮 MODERN UI COMPONENTS - OS SELECTION
# ═══════════════════════════════════════════════════════════════════════════════

class OSSelectView(discord.ui.View):
    def __init__(self, ram: int, cpu: int, disk: int, user: discord.Member, ctx):
        super().__init__(timeout=300)
        self.ram = ram
        self.cpu = cpu
        self.disk = disk
        self.user = user
        self.ctx = ctx
        self.select = discord.ui.Select(
            placeholder="🖥️ Select Operating System...",
            options=[
                discord.SelectOption(label=o["label"], value=o["value"], description=o.get("description", ""), emoji=o.get("emoji", "📦"))
                for o in OS_OPTIONS
            ],
            row=0
        )
        self.select.callback = self.select_os
        self.add_item(self.select)
        cancel_btn = discord.ui.Button(label="Cancel", style=discord.ButtonStyle.secondary, emoji="❌", row=1)
        cancel_btn.callback = self.cancel
        self.add_item(cancel_btn)

    async def cancel(self, interaction: discord.Interaction):
        if str(interaction.user.id) != str(self.ctx.author.id):
            await interaction.response.send_message(embed=create_error_embed("Access Denied", "Only the command author can cancel."), ephemeral=True)
            return
        self.stop()
        await interaction.response.edit_message(embed=create_info_embed("Cancelled", "VPS creation cancelled."), view=None)

    async def select_os(self, interaction: discord.Interaction):
        if str(interaction.user.id) != str(self.ctx.author.id):
            await interaction.response.send_message(embed=create_error_embed("Access Denied", "Only the command author can select."), ephemeral=True)
            return
        os_choice = self.select.values[0]
        self.select.disabled = True
        await interaction.response.edit_message(embed=create_info_embed("Creating VPS", f"Deploying **{os_choice}** CT on Proxmox..."), view=self)
        try:
            user_id = str(self.user.id)
            pve_username, password, is_new = await ensure_proxmox_user(user_id, self.user.name)
            template = await find_template(os_choice)
            if not template:
                await interaction.followup.send(embed=create_error_embed("Template Not Found", f"OS template `{os_choice}` not found. Check `{PREFIX}templates`."), ephemeral=True)
                self.stop()
                return
            vmid = await get_next_vmid()
            if user_id not in vps_data:
                vps_data[user_id] = []
            hostname = f"bynexhost-{user_id}-{len(vps_data.get(user_id, [])) + 1}"
            container_name = hostname
            ram_mb = self.ram * 1024
            ct_password = secrets.token_urlsafe(16)
            create_data = {
                'vmid': vmid,
                'ostemplate': template,
                'hostname': hostname,
                'memory': ram_mb,
                'swap': 512,
                'cores': self.cpu,
                'rootfs': f'{PROXMOX_STORAGE}:{self.disk}',
                'net0': f'name=eth0,bridge={PROXMOX_BRIDGE},ip=dhcp',
                'unprivileged': 1,
                'features': 'nesting=1',
                'start': 1,
                'password': ct_password,
            }
            await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc', data=create_data)
            # Wait for CT to be running
            for _ in range(30):
                await asyncio.sleep(2)
                status = await get_ct_status(vmid)
                if status == 'running':
                    break
            await grant_ct_access(vmid, pve_username)
            config_str = f"{self.ram}GB RAM / {self.cpu} CPU / {self.disk}GB Disk"
            vps_entry = {
                'id': None,
                'container_name': container_name,
                'vmid': vmid,
                'proxmox_user': pve_username,
                'ram': f'{self.ram}GB',
                'cpu': str(self.cpu),
                'storage': f'{self.disk}GB',
                'config': config_str,
                'os_version': os_choice,
                'status': 'running',
                'suspended': False,
                'whitelisted': False,
                'created_at': datetime.now().isoformat(),
                'shared_with': [],
                'suspension_history': [],
            }
            vps_data[user_id].append(vps_entry)
            save_vps_data()
            if self.ctx.guild:
                vps_role = await get_or_create_vps_role(self.ctx.guild)
                if vps_role and vps_role not in self.user.roles:
                    try:
                        await self.user.add_roles(vps_role, reason=f"{BOT_NAME} VPS ownership granted")
                    except:
                        pass
            embed = create_success_embed("VPS Created!", f"CT deployed on Proxmox for {self.user.mention}")
            add_field(embed, "Resources", f"**RAM:** {self.ram}GB\n**CPU:** {self.cpu} Cores\n**Storage:** {self.disk}GB", False)
            add_field(embed, "Details", f"**VMID:** {vmid}\n**Hostname:** `{hostname}`\n**OS:** {os_choice}", False)
            add_field(embed, "Access", f"🌐 Panel: **{PROXMOX_URL}**\n👤 User: `{pve_username}`\nCredentials sent via DM 📩", False)
            await interaction.followup.send(embed=embed)
            try:
                dm_embed = create_success_embed("Your VPS is Ready!", f"Your new VPS has been created on {BOT_NAME}!")
                add_field(dm_embed, "VPS Details", f"**VMID:** {vmid}\n**Hostname:** `{hostname}`\n**OS:** {os_choice}\n**Resources:** {config_str}", False)
                add_field(dm_embed, "Panel Access", f"🌐 **URL:** {PROXMOX_URL}\n👤 **User:** `{pve_username}`", False)
                add_field(dm_embed, "🔑 Root Password", f"||`{ct_password}`||\n*(For SSH/Console)*", False)
                if password:
                    add_field(dm_embed, "🔑 Panel Password", f"||`{password}`||\n*(Save this!)*", False)
                else:
                    add_field(dm_embed, "🔑 Panel Password", "*(Using existing account)*", False)
                add_field(dm_embed, "Quick Start", "1. Login to the Proxmox panel\n2. Find your CT in the sidebar\n3. Click 'Console' to access shell", False)
                await self.user.send(embed=dm_embed)
            except:
                logger.warning(f"Could not DM user {self.user.name}")
            self.stop()
        except Exception as e:
            logger.error(f"VPS creation failed: {e}")
            await interaction.followup.send(embed=create_error_embed("Creation Failed", f"Error: {str(e)[:500]}"))
            self.stop()

@bot.command(name='create')
@is_admin()
async def create_vps(ctx, ram: int, cpu: int, disk: int, user: discord.Member):
    if ram <= 0 or cpu <= 0 or disk <= 0:
        await ctx.send(embed=create_error_embed("Invalid Specs", "RAM, CPU, and Disk must be positive integers."))
        return
    embed = create_info_embed("VPS Creation", f"Creating VPS for {user.mention} with {ram}GB RAM, {cpu} CPU cores, {disk}GB Disk.\nSelect OS below.")
    view = OSSelectView(ram, cpu, disk, user, ctx)
    await ctx.send(embed=embed, view=view)

class ReinstallOSSelectView(discord.ui.View):
    def __init__(self, parent_view, container_name, owner_id, actual_idx, ram_gb, cpu, storage_gb, vmid):
        super().__init__(timeout=300)
        self.parent_view = parent_view
        self.container_name = container_name
        self.owner_id = owner_id
        self.actual_idx = actual_idx
        self.ram_gb = ram_gb
        self.cpu = cpu
        self.storage_gb = storage_gb
        self.vmid = vmid
        self.select = discord.ui.Select(
            placeholder="Select an OS for the reinstall",
            options=[discord.SelectOption(label=o["label"], value=o["value"]) for o in OS_OPTIONS]
        )
        self.select.callback = self.select_os
        self.add_item(self.select)

    async def select_os(self, interaction: discord.Interaction):
        os_choice = self.select.values[0]
        self.select.disabled = True
        await interaction.response.edit_message(embed=create_info_embed("Reinstalling VPS", f"Deploying {os_choice} for VMID `{self.vmid}`..."), view=self)
        try:
            template = await find_template(os_choice)
            if not template:
                await interaction.followup.send(embed=create_error_embed("Template Not Found", f"OS template `{os_choice}` not found."), ephemeral=True)
                self.stop()
                return
            ram_mb = self.ram_gb * 1024
            create_data = {
                'vmid': self.vmid,
                'ostemplate': template,
                'hostname': self.container_name,
                'memory': ram_mb,
                'swap': 512,
                'cores': self.cpu,
                'rootfs': f'{PROXMOX_STORAGE}:{self.storage_gb}',
                'net0': f'name=eth0,bridge={PROXMOX_BRIDGE},ip=dhcp',
                'unprivileged': 1,
                'features': 'nesting=1',
                'start': 1,
                'password': (ct_password := secrets.token_urlsafe(16)),
            }
            await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc', data=create_data)
            for _ in range(30):
                await asyncio.sleep(2)
                status = await get_ct_status(self.vmid)
                if status == 'running':
                    break
            target_vps = vps_data[self.owner_id][self.actual_idx]
            target_vps["os_version"] = os_choice
            target_vps["status"] = "running"
            target_vps["suspended"] = False
            target_vps["created_at"] = datetime.now().isoformat()
            config_str = f"{self.ram_gb}GB RAM / {self.cpu} CPU / {self.storage_gb}GB Disk"
            target_vps["config"] = config_str
            save_vps_data()
            embed = create_success_embed("Reinstall Complete", f"VPS `{self.container_name}` (VMID {self.vmid}) reinstalled!")
            add_field(embed, "Resources", f"**RAM:** {self.ram_gb}GB\n**CPU:** {self.cpu} Cores\n**Storage:** {self.storage_gb}GB", False)
            add_field(embed, "OS", os_choice, True)
            add_field(embed, "Access", "Credentials sent via DM �", False)
            await interaction.followup.send(embed=embed, ephemeral=True)
            try:
                dm_embed = create_success_embed("VPS Reinstalled", f"Your VPS `{self.container_name}` has been reinstalled.")
                add_field(dm_embed, "Panel Access", f"🌐 **URL:** {PROXMOX_URL}", False)
                add_field(dm_embed, "�🔑 Root Password", f"||`{ct_password}`||\n*(For SSH/Console)*", False)
                await interaction.user.send(embed=dm_embed)
            except:
                pass
            self.stop()
        except Exception as e:
            await interaction.followup.send(embed=create_error_embed("Reinstall Failed", f"Error: {str(e)[:500]}"), ephemeral=True)
            self.stop()

# ═══════════════════════════════════════════════════════════════════════════════
# 🎮 MODERN DASHBOARD - VPS MANAGEMENT VIEW
# ═══════════════════════════════════════════════════════════════════════════════

class ManageView(discord.ui.View):
    def __init__(self, user_id, vps_list, is_shared=False, owner_id=None, is_admin=False, actual_index: Optional[int] = None):
        super().__init__(timeout=300)
        self.user_id = user_id
        self.vps_list = vps_list[:]
        self.selected_index = None
        self.is_shared = is_shared
        self.owner_id = owner_id or user_id
        self.is_admin = is_admin
        self.actual_index = actual_index
        self.indices = list(range(len(vps_list)))
        if self.is_shared and self.actual_index is None:
            raise ValueError("actual_index required for shared views")
        if len(vps_list) > 1:
            options = [
                discord.SelectOption(
                    label=f"VPS #{i+1} • {v.get('config', 'Custom')}",
                    description=f"{get_status_display(v.get('status', 'unknown'), v.get('suspended', False))}",
                    value=str(i),
                    emoji=STATUS_EMOJI.get(v.get('status', 'unknown'), '❓')
                ) for i, v in enumerate(vps_list)
            ]
            self.select = discord.ui.Select(placeholder="🖥️ Select a VPS to manage...", options=options, row=0)
            self.select.callback = self.select_vps
            self.add_item(self.select)
            self.initial_embed = discord.Embed(title=f"✨ {BOT_NAME} • VPS Dashboard", description="Select a VPS from the dropdown to manage it.", color=COLORS['primary'], timestamp=datetime.now())
            vps_overview = []
            for i, v in enumerate(vps_list):
                status_emoji = STATUS_EMOJI.get(v.get('status', 'unknown'), '❓')
                status = v.get('status', 'unknown').upper()
                if v.get('suspended'):
                    status += " ⚠️"
                if v.get('whitelisted'):
                    status += " ✅"
                vmid = v.get('vmid', 'N/A')
                vps_overview.append(f"{status_emoji} **VPS #{i+1}** • VMID `{vmid}` • `{v['container_name']}`\n   └ {v.get('config', 'Custom')}")
            self.initial_embed.add_field(name="📋 Your VPS Instances", value="\n".join(vps_overview), inline=False)
            self.initial_embed.set_thumbnail(url=THUMBNAIL_URL)
            self.initial_embed.set_footer(text=f"⚡ {BOT_NAME} • Select a VPS above", icon_url=THUMBNAIL_URL)
        else:
            self.selected_index = 0
            self.initial_embed = None
            self.add_action_buttons()

    async def get_initial_embed(self):
        if self.initial_embed is not None:
            return self.initial_embed
        self.initial_embed = await self.create_vps_embed(self.selected_index)
        return self.initial_embed

    async def create_vps_embed(self, index):
        vps = self.vps_list[index]
        status = vps.get('status', 'unknown')
        suspended = vps.get('suspended', False)
        whitelisted = vps.get('whitelisted', False)
        status_color = get_status_color(status, suspended, whitelisted)
        container_name = vps['container_name']
        vmid = vps.get('vmid', 'N/A')
        # Fetch live stats via Proxmox API
        if vmid and vmid != 'N/A':
            pve_status = await get_ct_status(vmid)
            cpu_usage = await get_container_cpu(vmid)
            memory_usage = await get_container_memory(vmid)
            disk_usage = await get_container_disk(vmid)
            uptime_str = await get_container_uptime(vmid)
        else:
            pve_status = status
            cpu_usage = memory_usage = disk_usage = uptime_str = 'N/A'
        status_display = get_status_display(pve_status, suspended, whitelisted)
        owner_text = ""
        if self.is_admin and self.owner_id != self.user_id:
            try:
                owner_user = await bot.fetch_user(int(self.owner_id))
                owner_text = f"\n👤 **Owner:** {owner_user.mention}"
            except:
                owner_text = f"\n👤 **Owner ID:** {self.owner_id}"
        embed = discord.Embed(title=f"🖥️ VPS #{index + 1} • VMID `{vmid}` • `{container_name}`", description=f"**Status:** {status_display}{owner_text}", color=status_color, timestamp=datetime.now())
        resources = f"""╭ **RAM:** {vps['ram']}
├ **CPU:** {vps['cpu']} Cores
├ **Storage:** {vps['storage']}
╰ **OS:** {vps.get('os_version', 'unknown')}"""
        embed.add_field(name="📦 Resources", value=resources, inline=True)
        config_info = f"""╭ **Config:** {vps.get('config', 'Custom')}
├ **Uptime:** {uptime_str[:30] if uptime_str else 'N/A'}
╰ **Nesting:** ✅ Enabled"""
        embed.add_field(name="⚙️ Configuration", value=config_info, inline=True)
        live_stats = f"""💻 **CPU:** {cpu_usage}
🧠 **Memory:** {memory_usage}
💾 **Disk:** {disk_usage}"""
        embed.add_field(name="📈 Live Stats", value=live_stats, inline=False)
        if suspended:
            embed.add_field(name="⚠️ Suspended", value="Contact admin to unsuspend", inline=True)
        if whitelisted:
            embed.add_field(name="✅ Whitelisted", value="Exempt from auto-suspend", inline=True)
        embed.add_field(name="🎮 Actions", value="Use buttons below to control your VPS", inline=False)
        embed.set_thumbnail(url=THUMBNAIL_URL)
        embed.set_footer(text=f"⚡ {BOT_NAME} • VPS Management", icon_url=THUMBNAIL_URL)
        return embed

    def add_action_buttons(self):
        start_button = discord.ui.Button(label="Start", style=discord.ButtonStyle.success, emoji="▶️", row=1)
        start_button.callback = lambda inter: self.action_callback(inter, 'start')
        stop_button = discord.ui.Button(label="Stop", style=discord.ButtonStyle.secondary, emoji="⏹️", row=1)
        stop_button.callback = lambda inter: self.action_callback(inter, 'stop')
        console_button = discord.ui.Button(label="Console", style=discord.ButtonStyle.primary, emoji="🖥️", row=1)
        console_button.callback = lambda inter: self.action_callback(inter, 'console')
        stats_button = discord.ui.Button(label="Stats", style=discord.ButtonStyle.secondary, emoji="📊", row=1)
        stats_button.callback = lambda inter: self.action_callback(inter, 'stats')
        self.add_item(start_button)
        self.add_item(stop_button)
        self.add_item(console_button)
        self.add_item(stats_button)
        if not self.is_shared and not self.is_admin:
            reinstall_button = discord.ui.Button(label="Reinstall", style=discord.ButtonStyle.danger, emoji="🔄", row=2)
            reinstall_button.callback = lambda inter: self.action_callback(inter, 'reinstall')
            self.add_item(reinstall_button)
        refresh_button = discord.ui.Button(label="Refresh", style=discord.ButtonStyle.secondary, emoji="🔃", row=2)
        refresh_button.callback = self.refresh_stats
        self.add_item(refresh_button)

    async def refresh_stats(self, interaction: discord.Interaction):
        if str(interaction.user.id) != self.user_id and not self.is_admin:
            await interaction.response.send_message(embed=create_error_embed("Access Denied", "This is not your VPS!"), ephemeral=True)
            return
        await interaction.response.defer()
        new_embed = await self.create_vps_embed(self.selected_index)
        await interaction.edit_original_response(embed=new_embed, view=self)

    async def select_vps(self, interaction: discord.Interaction):
        if str(interaction.user.id) != self.user_id and not self.is_admin:
            await interaction.response.send_message(embed=create_error_embed("Access Denied", "This is not your VPS!"), ephemeral=True)
            return
        self.selected_index = int(self.select.values[0])
        await interaction.response.defer()
        new_embed = await self.create_vps_embed(self.selected_index)
        self.clear_items()
        self.add_action_buttons()
        await interaction.edit_original_response(embed=new_embed, view=self)

    async def action_callback(self, interaction: discord.Interaction, action: str):
        if str(interaction.user.id) != self.user_id and not self.is_admin:
            await interaction.response.send_message(embed=create_error_embed("Access Denied", "This is not your VPS!"), ephemeral=True)
            return
        if self.selected_index is None:
            await interaction.response.send_message(embed=create_error_embed("No VPS Selected", "Please select a VPS first."), ephemeral=True)
            return
        actual_idx = self.actual_index if self.is_shared else self.indices[self.selected_index]
        target_vps = vps_data[self.owner_id][actual_idx]
        suspended = target_vps.get('suspended', False)
        vmid = target_vps.get('vmid')
        container_name = target_vps["container_name"]

        if suspended and not self.is_admin and action != 'stats':
            await interaction.response.send_message(embed=create_error_embed("Access Denied", "This VPS is suspended. Contact an admin."), ephemeral=True)
            return

        if action == 'stats':
            await interaction.response.defer(ephemeral=True)
            if vmid:
                cpu_usage = await get_container_cpu(vmid)
                memory_usage = await get_container_memory(vmid)
                disk_usage = await get_container_disk(vmid)
                uptime_str = await get_container_uptime(vmid)
                pve_status = await get_ct_status(vmid)
            else:
                cpu_usage = memory_usage = disk_usage = uptime_str = 'N/A'
                pve_status = 'unknown'
            stats_embed = create_info_embed("📈 Live Statistics", f"Real-time stats for `{container_name}` (VMID {vmid})")
            add_field(stats_embed, "Status", f"`{pve_status.upper()}`", True)
            add_field(stats_embed, "CPU", cpu_usage, True)
            add_field(stats_embed, "Memory", memory_usage, True)
            add_field(stats_embed, "Disk", disk_usage, True)
            add_field(stats_embed, "Uptime", uptime_str, True)
            await interaction.followup.send(embed=stats_embed, ephemeral=True)
            return

        if action == 'console':
            await interaction.response.defer(ephemeral=True)
            if vmid:
                console_url = f"{PROXMOX_URL}/#v1:0:18:4:::::::{PROXMOX_NODE}/lxc/{vmid}"
                embed = create_info_embed("🖥️ Console Access", f"Access the web console for VMID `{vmid}`")
                add_field(embed, "Panel URL", f"🌐 **[Open Proxmox Panel]({PROXMOX_URL})**", False)
                add_field(embed, "Instructions", "1. Login to the Proxmox panel\n2. Select your CT from the sidebar\n3. Click **Console** tab", False)
                pve_user = target_vps.get('proxmox_user', 'N/A')
                add_field(embed, "Your Login", f"👤 User: `{pve_user}`", False)
            else:
                embed = create_error_embed("No VMID", "This VPS has no VMID assigned.")
            await interaction.followup.send(embed=embed, ephemeral=True)
            return

        if action == 'reinstall':
            if self.is_shared or self.is_admin:
                await interaction.response.send_message(embed=create_error_embed("Access Denied", "Only the VPS owner can reinstall!"), ephemeral=True)
                return
            if suspended:
                await interaction.response.send_message(embed=create_error_embed("Cannot Reinstall", "Unsuspend the VPS first."), ephemeral=True)
                return
            ram_gb = int(target_vps['ram'].replace('GB', ''))
            cpu = int(target_vps['cpu'])
            storage_gb = int(target_vps['storage'].replace('GB', ''))
            confirm_embed = create_warning_embed("Reinstall Warning",
                f"⚠️ **WARNING:** This will erase all data on VPS VMID `{vmid}` and reinstall a fresh OS.\n\nThis action cannot be undone. Continue?")
            class ConfirmView(discord.ui.View):
                def __init__(cv_self, parent_view, container_name, owner_id, actual_idx, ram_gb, cpu, storage_gb, vmid):
                    super().__init__(timeout=60)
                    cv_self.parent_view = parent_view
                    cv_self.container_name = container_name
                    cv_self.owner_id = owner_id
                    cv_self.actual_idx = actual_idx
                    cv_self.ram_gb = ram_gb
                    cv_self.cpu = cpu
                    cv_self.storage_gb = storage_gb
                    cv_self.vmid = vmid
                @discord.ui.button(label="Confirm", style=discord.ButtonStyle.danger)
                async def confirm(cv_self, inter: discord.Interaction, item: discord.ui.Button):
                    await inter.response.defer(ephemeral=True)
                    try:
                        await inter.followup.send(embed=create_info_embed("Deleting Container", f"Removing VMID `{cv_self.vmid}`..."), ephemeral=True)
                        await proxmox_api('DELETE', f'/nodes/{PROXMOX_NODE}/lxc/{cv_self.vmid}', data={'force': 1, 'purge': 1})
                        await asyncio.sleep(3)
                        os_view = ReinstallOSSelectView(cv_self.parent_view, cv_self.container_name, cv_self.owner_id, cv_self.actual_idx, cv_self.ram_gb, cv_self.cpu, cv_self.storage_gb, cv_self.vmid)
                        await inter.followup.send(embed=create_info_embed("Select OS", "Choose the new OS for reinstallation."), view=os_view, ephemeral=True)
                    except Exception as e:
                        await inter.followup.send(embed=create_error_embed("Delete Failed", f"Error: {str(e)[:500]}"), ephemeral=True)
                @discord.ui.button(label="Cancel", style=discord.ButtonStyle.secondary)
                async def cancel_btn(cv_self, inter: discord.Interaction, item: discord.ui.Button):
                    new_embed = await cv_self.parent_view.create_vps_embed(cv_self.parent_view.selected_index)
                    await inter.response.edit_message(embed=new_embed, view=cv_self.parent_view)
            await interaction.response.send_message(embed=confirm_embed, view=ConfirmView(self, container_name, self.owner_id, actual_idx, ram_gb, cpu, storage_gb, vmid), ephemeral=True)
            return

        # Start / Stop actions
        await interaction.response.defer(ephemeral=True)
        if action == 'start':
            try:
                await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/start')
                target_vps["status"] = "running"
                if target_vps.get('suspended'):
                    target_vps['suspended'] = False
                save_vps_data()
                await interaction.followup.send(embed=create_success_embed("VPS Started", f"VMID `{vmid}` is now running!"), ephemeral=True)
            except Exception as e:
                await interaction.followup.send(embed=create_error_embed("Start Failed", str(e)[:200]), ephemeral=True)
        elif action == 'stop':
            try:
                await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/stop')
                target_vps["status"] = "stopped"
                save_vps_data()
                await interaction.followup.send(embed=create_success_embed("VPS Stopped", f"VMID `{vmid}` has been stopped!"), ephemeral=True)
            except Exception as e:
                await interaction.followup.send(embed=create_error_embed("Stop Failed", str(e)[:200]), ephemeral=True)
        new_embed = await self.create_vps_embed(self.selected_index)
        await interaction.edit_original_response(embed=new_embed, view=self)

@bot.command(name='manage')
async def manage_vps(ctx, user: discord.Member = None):
    if user:
        user_id_check = str(ctx.author.id)
        if user_id_check != str(MAIN_ADMIN_ID) and user_id_check not in admin_data.get("admins", []):
            await ctx.send(embed=create_error_embed("Access Denied", "Only admins can manage other users' VPS."))
            return
        user_id = str(user.id)
        vps_list = vps_data.get(user_id, [])
        if not vps_list:
            await ctx.send(embed=create_error_embed("No VPS Found", f"{user.mention} doesn't have any {BOT_NAME} VPS."))
            return
        view = ManageView(str(ctx.author.id), vps_list, is_admin=True, owner_id=user_id)
        await ctx.send(embed=create_info_embed(f"Managing {user.name}'s VPS", f"Managing VPS for {user.mention}"), view=view)
    else:
        user_id = str(ctx.author.id)
        vps_list = vps_data.get(user_id, [])
        if not vps_list:
            embed = create_error_embed("No VPS Found", f"You don't have any {BOT_NAME} VPS. Contact an admin to create one.")
            add_field(embed, "Quick Actions", f"• `{PREFIX}manage` - Manage VPS\n• Contact admin for VPS creation", False)
            await ctx.send(embed=embed)
            return
        view = ManageView(user_id, vps_list)
        embed = await view.get_initial_embed()
        await ctx.send(embed=embed, view=view)

@bot.command(name='list-all')
@is_admin()
async def list_all_vps(ctx):
    total_vps = 0
    total_users = len(vps_data)
    running_vps = 0
    stopped_vps = 0
    vps_info = []
    
    # Proxmox sync check could go here, but for now just list DB data
    for user_id, vps_list in vps_data.items():
        try:
            user = await bot.fetch_user(int(user_id))
            total_vps += len(vps_list)
            for i, vps in enumerate(vps_list):
                status = vps.get('status', 'unknown')
                if status == 'running':
                    running_vps += 1
                else:
                    stopped_vps += 1
                
                status_emoji = '🟢' if status == 'running' else '🔴'
                vmid = vps.get('vmid', 'N/A')
                vps_info.append(f"{status_emoji} **{user.name}** • VMID `{vmid}` • `{vps['container_name']}`")
        except:
            vps_info.append(f"❓ Unknown User ({user_id}) - {len(vps_list)} VPS")

    embed = create_embed("All VPS Information", "Complete overview of all VPS deployments", COLORS['primary'])
    add_field(embed, "System Overview", f"**Total Users:** {total_users}\n**Total VPS:** {total_vps}\n**Running:** {running_vps}\n**Stopped:** {stopped_vps}", False)
    
    if vps_info:
        vps_text = "\n".join(vps_info)
        # Split into chunks if needed
        chunks = [vps_text[i:i+1024] for i in range(0, len(vps_text), 1024)]
        for idx, chunk in enumerate(chunks, 1):
             add_field(embed, f"VPS List (Part {idx})", chunk, False)
    
    await ctx.send(embed=embed)

@bot.command(name='manage-shared')
async def manage_shared_vps(ctx, owner: discord.Member, vps_number: int):
    owner_id = str(owner.id)
    user_id = str(ctx.author.id)
    if owner_id not in vps_data or vps_number < 1 or vps_number > len(vps_data[owner_id]):
        await ctx.send(embed=create_error_embed("Invalid VPS", "Invalid VPS number or owner doesn't have a VPS."))
        return
    vps = vps_data[owner_id][vps_number - 1]
    if user_id not in vps.get("shared_with", []):
        await ctx.send(embed=create_error_embed("Access Denied", "You do not have access to this VPS."))
        return
    view = ManageView(user_id, [vps], is_shared=True, owner_id=owner_id, actual_index=vps_number - 1)
    embed = await view.get_initial_embed()
    await ctx.send(embed=embed, view=view)

@bot.command(name='share-user')
async def share_user(ctx, shared_user: discord.Member, vps_number: int):
    user_id = str(ctx.author.id)
    shared_user_id = str(shared_user.id)
    if user_id not in vps_data or vps_number < 1 or vps_number > len(vps_data[user_id]):
        await ctx.send(embed=create_error_embed("Invalid VPS", "Invalid VPS number or you don't have a VPS."))
        return
    vps = vps_data[user_id][vps_number - 1]
    if "shared_with" not in vps:
        vps["shared_with"] = []
    if shared_user_id in vps["shared_with"]:
        await ctx.send(embed=create_error_embed("Already Shared", f"{shared_user.mention} already has access."))
        return
    vps["shared_with"].append(shared_user_id)
    save_vps_data()
    
    # Grant Proxmox access to the shared user's unique user
    target_pve_user, _, _ = await ensure_proxmox_user(shared_user_id, shared_user.name)
    vmid = vps.get('vmid')
    if vmid:
        await grant_ct_access(vmid, target_pve_user)
        
    await ctx.send(embed=create_success_embed("VPS Shared", f"VPS #{vps_number} shared with {shared_user.mention}!"))
    try:
        await shared_user.send(embed=create_embed("VPS Access Granted", f"You have access to VPS #{vps_number} from {ctx.author.mention}.", COLORS['success']))
    except:
        pass

@bot.command(name='share-ruser')
async def revoke_share(ctx, shared_user: discord.Member, vps_number: int):
    user_id = str(ctx.author.id)
    shared_user_id = str(shared_user.id)
    if user_id not in vps_data or vps_number < 1 or vps_number > len(vps_data[user_id]):
        await ctx.send(embed=create_error_embed("Invalid VPS", "Invalid VPS number."))
        return
    vps = vps_data[user_id][vps_number - 1]
    if "shared_with" not in vps:
        vps["shared_with"] = []
    if shared_user_id not in vps["shared_with"]:
        await ctx.send(embed=create_error_embed("Not Shared", f"{shared_user.mention} doesn't have access."))
        return
    vps["shared_with"].remove(shared_user_id)
    save_vps_data()
    # Revoking Proxmox access is complex because we need to know the shared user's PVE username
    # For now, we rely on the bot filtering access. Fully revoking PVE permission would require lookup.
    
    await ctx.send(embed=create_success_embed("Access Revoked", f"Access to VPS #{vps_number} revoked from {shared_user.mention}!"))

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️ ADMIN COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

@bot.command(name='delete-vps')
@is_admin()
async def delete_vps(ctx, user: discord.Member, vps_number: int, *, reason: str = "No reason"):
    user_id = str(user.id)
    if user_id not in vps_data or vps_number < 1 or vps_number > len(vps_data[user_id]):
        await ctx.send(embed=create_error_embed("Invalid VPS", "Invalid VPS number or user doesn't have a VPS."))
        return
    vps = vps_data[user_id][vps_number - 1]
    container_name = vps["container_name"]
    vmid = vps.get('vmid')
    
    await ctx.send(embed=create_info_embed("Deleting VPS", f"Removing VPS #{vps_number} (VMID {vmid})..."))
    try:
        if vmid:
            await proxmox_api('DELETE', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}', data={'force': 1, 'purge': 1})
        
        del vps_data[user_id][vps_number - 1]
        if not vps_data[user_id]:
            del vps_data[user_id]
            if ctx.guild:
                vps_role = await get_or_create_vps_role(ctx.guild)
                if vps_role and vps_role in user.roles:
                    try:
                        await user.remove_roles(vps_role)
                    except:
                        pass
        save_vps_data()
        
        embed = create_success_embed("VPS Deleted Successfully")
        add_field(embed, "Owner", user.mention, True)
        add_field(embed, "VMID", str(vmid), True)
        add_field(embed, "Reason", reason, False)
        await ctx.send(embed=embed)
    except Exception as e:
        await ctx.send(embed=create_error_embed("Deletion Failed", f"Error: {str(e)}"))

@bot.command(name='delete-user')
@is_admin()
async def delete_pve_user(ctx, user: discord.Member):
    user_id = str(user.id)
    pve_user = f"discord_{user_id}@pve"
    await ctx.send(embed=create_info_embed("Deleting User", f"Deleting Proxmox user `{pve_user}`..."))
    try:
        await proxmox_api('DELETE', f'/access/users/{pve_user}')
        await ctx.send(embed=create_success_embed("User Deleted", f"Proxmox user `{pve_user}` deleted."))
    except Exception as e:
        await ctx.send(embed=create_error_embed("Deletion Failed", f"Error: {str(e)}"))

@bot.command(name='resize-vps')
@is_admin()
async def resize_vps(ctx, container_name: str, ram_gb: int = None, cpu: int = None, disk_gb: int = None):
    # Find VPS
    target_vps = None
    user_id = None
    idx = 0
    for uid, vps_list in vps_data.items():
        for i, vps in enumerate(vps_list):
            if vps['container_name'] == container_name:
                target_vps = vps
                user_id = uid
                idx = i
                break
        if target_vps: break
    
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", f"VPS `{container_name}` not found."))
        return
    
    vmid = target_vps.get('vmid')
    if not vmid:
        await ctx.send(embed=create_error_embed("Error", "VPS has no VMID."))
        return

    changes = []
    try:
        if ram_gb:
            await proxmox_api('PUT', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/config', data={'memory': ram_gb * 1024})
            target_vps['ram'] = f"{ram_gb}GB"
            changes.append(f"RAM: {ram_gb}GB")
        if cpu:
            await proxmox_api('PUT', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/config', data={'cores': cpu})
            target_vps['cpu'] = str(cpu)
            changes.append(f"CPU: {cpu}")
        if disk_gb:
            # Resize rootfs
            await proxmox_api('PUT', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/resize', data={'disk': 'rootfs', 'size': f"{disk_gb}G"})
            target_vps['storage'] = f"{disk_gb}GB"
            changes.append(f"Disk: {disk_gb}GB")

        target_vps['config'] = f"{target_vps['ram']} RAM / {target_vps['cpu']} CPU / {target_vps['storage']} Disk"
        save_vps_data()
        
        embed = create_success_embed("VPS Resized", f"Updated resources for `{container_name}` (VMID {vmid})")
        add_field(embed, "Changes", "\n".join(changes) if changes else "No changes specified", False)
        if disk_gb:
             add_field(embed, "Note", "Filesystem resize applied automatically by Proxmox.", False)
        await ctx.send(embed=embed)
    except Exception as e:
        await ctx.send(embed=create_error_embed("Resize Failed", f"Proxmox Error: {str(e)}"))

@bot.command(name='suspend-vps')
@is_admin()
async def suspend_vps(ctx, container_name: str, *, reason: str = "Admin action"):
    # Find VPS
    target_vps = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                target_vps = vps
                break
        if target_vps: break
        
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", "VPS not found."))
        return

    vmid = target_vps.get('vmid')
    if not vmid:
         await ctx.send(embed=create_error_embed("Error", "VPS has no VMID."))
         return

    try:
        await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/stop')
        target_vps['status'] = 'stopped'
        target_vps['suspended'] = True
        save_vps_data()
        await ctx.send(embed=create_success_embed("VPS Suspended", f"VPS `{container_name}` suspended. Reason: {reason}"))
    except Exception as e:
        await ctx.send(embed=create_error_embed("Suspend Failed", str(e)))

@bot.command(name='unsuspend-vps')
@is_admin()
async def unsuspend_vps(ctx, container_name: str):
    # Find VPS
    target_vps = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                target_vps = vps
                break
        if target_vps: break
        
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", "VPS not found."))
        return
        
    vmid = target_vps.get('vmid')
    if not vmid:
         await ctx.send(embed=create_error_embed("Error", "VPS has no VMID."))
         return

    try:
        await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/start')
        target_vps['status'] = 'running'
        target_vps['suspended'] = False
        save_vps_data()
        await ctx.send(embed=create_success_embed("VPS Unsuspended", f"VPS `{container_name}` is now running."))
    except Exception as e:
        await ctx.send(embed=create_error_embed("Unsuspend Failed", str(e)))

@bot.command(name='serverstats')
@is_admin()
async def server_stats(ctx):
    try:
        # Get Node Status
        node_status = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/status')
        node_data = node_status.get('data', {})
        cpu = node_data.get('cpu', 0) * 100
        mem_used = node_data.get('memory', {}).get('used', 0)
        mem_total = node_data.get('memory', {}).get('total', 1)
        mem_pct = (mem_used / mem_total) * 100
        
        # Count VPS
        total_vps = sum(len(v_list) for v_list in vps_data.values())
        
        embed = create_embed("📊 Server Statistics", f"Node: **{PROXMOX_NODE}**", COLORS['primary'])
        add_field(embed, "Host CPU", f"{cpu:.1f}%", True)
        add_field(embed, "Host RAM", f"{mem_pct:.1f}% ({mem_used//1024**3}GB Used)", True)
        add_field(embed, "Total VPS", str(total_vps), True)
        await ctx.send(embed=embed)
    except Exception as e:
        await ctx.send(embed=create_error_embed("Stats Failed", str(e)))

@bot.command(name='snapshot')
@is_admin()
async def snapshot_vps(ctx, container_name: str, snap_name: str = "snap"):
    # Find VPS
    target_vps = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                target_vps = vps
                break
        if target_vps: break
    
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", "VPS not found."))
        return
    vmid = target_vps.get('vmid')
    
    await ctx.send(embed=create_info_embed("Creating Snapshot", f"Snapshotting `{container_name}`..."))
    try:
        await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/snapshot', data={'snapname': snap_name})
        await ctx.send(embed=create_success_embed("Snapshot Created", f"Created snapshot `{snap_name}`."))
    except Exception as e:
        await ctx.send(embed=create_error_embed("Snapshot Failed", str(e)))

@bot.command(name='list-snapshots')
@is_admin()
async def list_snapshots(ctx, container_name: str):
    # Find VPS
    target_vps = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                target_vps = vps
                break
        if target_vps: break
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", "VPS not found."))
        return
    vmid = target_vps.get('vmid')
    
    try:
        result = await proxmox_api('GET', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/snapshot')
        snaps = result.get('data', [])
        parent_snaps = [s for s in snaps if s.get('parent')] # Basic filtering attempt, or just list all
        # Proxmox returns a tree structure flat list usually.
        snapshot_list = []
        for s in snaps:
            if s.get('name') != 'current':
                snapshot_list.append(f"📸 `{s.get('name')}` - {s.get('description', 'No desc')}")
        
        if not snapshot_list:
            await ctx.send(embed=create_info_embed("Snapshots", "No snapshots found."))
            return
            
        embed = create_info_embed(f"Snapshots for {container_name}", "\n".join(snapshot_list))
        await ctx.send(embed=embed)
    except Exception as e:
        await ctx.send(embed=create_error_embed("List Failed", str(e)))

@bot.command(name='restore-snapshot')
@is_admin()
async def restore_snapshot(ctx, container_name: str, snap_name: str):
    # Find VPS
    target_vps = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                target_vps = vps
                break
        if target_vps: break
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", "VPS not found."))
        return
    vmid = target_vps.get('vmid')

    await ctx.send(embed=create_info_embed("Restoring Snapshot", f"Rollback to `{snap_name}`..."))
    try:
        await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/snapshot/{snap_name}/rollback')
        await ctx.send(embed=create_success_embed("Restored", f"VPS `{container_name}` restored to `{snap_name}`."))
    except Exception as e:
        await ctx.send(embed=create_error_embed("Restore Failed", str(e)))

@bot.command(name='admin-add')
@is_main_admin()
async def admin_add(ctx, user: discord.Member):
    user_id = str(user.id)
    if user_id == str(MAIN_ADMIN_ID):
        await ctx.send(embed=create_error_embed("Already Admin", "This user is already the main admin!"))
        return
    if user_id in admin_data.get("admins", []):
        await ctx.send(embed=create_error_embed("Already Admin", f"{user.mention} is already an admin!"))
        return
    admin_data["admins"].append(user_id)
    save_admin_data()
    await ctx.send(embed=create_success_embed("Admin Added", f"{user.mention} is now an admin!"))

@bot.command(name='admin-remove')
@is_main_admin()
async def admin_remove(ctx, user: discord.Member):
    user_id = str(user.id)
    if user_id == str(MAIN_ADMIN_ID):
        await ctx.send(embed=create_error_embed("Cannot Remove", "You cannot remove the main admin!"))
        return
    if user_id not in admin_data.get("admins", []):
        await ctx.send(embed=create_error_embed("Not Admin", f"{user.mention} is not an admin!"))
        return
    admin_data["admins"].remove(user_id)
    save_admin_data()
    await ctx.send(embed=create_success_embed("Admin Removed", f"{user.mention} is no longer an admin!"))

@bot.command(name='admin-list')
@is_main_admin()
async def admin_list(ctx):
    admins = admin_data.get("admins", [])
    main_admin = await bot.fetch_user(MAIN_ADMIN_ID)
    embed = create_embed("👑 Admin Team", "Current administrators:", COLORS['primary'])
    add_field(embed, "🔰 Main Admin", f"{main_admin.mention} (ID: {MAIN_ADMIN_ID})", False)
    if admins:
        admin_list = []
        for admin_id in admins:
            try:
                admin_user = await bot.fetch_user(int(admin_id))
                admin_list.append(f"• {admin_user.mention}")
            except:
                admin_list.append(f"• ID: {admin_id}")
        add_field(embed, "🛡️ Admins", "\n".join(admin_list), False)
    else:
        add_field(embed, "🛡️ Admins", "No additional admins", False)
    await ctx.send(embed=embed)


@bot.command(name='restart-vps')
@is_admin()
async def restart_vps(ctx, container_name: str):
    # Find VPS
    target_vps = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                target_vps = vps
                break
        if target_vps: break
    if not target_vps:
        await ctx.send(embed=create_error_embed("Not Found", "VPS not found."))
        return
    vmid = target_vps.get('vmid')
    await ctx.send(embed=create_info_embed("Restarting VPS", f"Restarting `{container_name}`..."))
    try:
        await proxmox_api('POST', f'/nodes/{PROXMOX_NODE}/lxc/{vmid}/status/reboot')
        target_vps['status'] = 'running'
        target_vps['suspended'] = False
        save_vps_data()
        await ctx.send(embed=create_success_embed("Restarted", f"VPS `{container_name}` restarted."))
    except Exception as e:
        await ctx.send(embed=create_error_embed("Restart Failed", str(e)))

@bot.command(name='vpsinfo')
@is_admin()
async def vps_info(ctx, container_name: str = None):
    if not container_name:
        await list_all_vps(ctx)
        return
    
    # Find VPS
    found_vps = None
    user_id = None
    for uid, vps_list in vps_data.items():
        for vps in vps_list:
            if vps['container_name'] == container_name:
                found_vps = vps
                user_id = uid
                break
        if found_vps: break
        
    if not found_vps:
        await ctx.send(embed=create_error_embed("Not Found", f"VPS `{container_name}` not found."))
        return

    try:
        owner = await bot.fetch_user(int(user_id))
    except:
        owner = None
        
    vmid = found_vps.get('vmid')
    status = found_vps.get('status', 'unknown')
    suspended = found_vps.get('suspended', False)
    
    embed = create_embed(f"VPS Info: {container_name}", f"VMID: `{vmid}`", COLORS['primary'])
    if owner:
        add_field(embed, "Owner", f"{owner.mention} ({user_id})", False)
    else:
        add_field(embed, "Owner ID", user_id, False)
        
    add_field(embed, "Config", found_vps.get('config', 'N/A'), True)
    add_field(embed, "OS", found_vps.get('os_version', 'N/A'), True)
    add_field(embed, "Status", get_status_display(status, suspended), True)
    add_field(embed, "Proxmox User", f"`{found_vps.get('proxmox_user', 'N/A')}`", False)
    
    await ctx.send(embed=embed)

@bot.command(name='vps-uptime')
@is_admin()
async def vps_uptime(ctx, container_name: str):
    uptime = await get_container_uptime(container_name)
    await ctx.send(embed=create_info_embed("VPS Uptime", f"`{container_name}`: {uptime}"))

# ═══════════════════════════════════════════════════════════════════════════════
# 📚 HELP SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

class HelpView(discord.ui.View):
    def __init__(self, ctx):
        super().__init__(timeout=300)
        self.ctx = ctx
        self.category_colors = {
            "user": COLORS['info'],
            "vps": COLORS['success'],
            "admin": COLORS['error'],
        }
        self.command_categories = {
            "user": {
                "name": "👤 User", "emoji": "👤",
                "commands": [
                    (f"`{PREFIX}ping`", "Check latency"),
                    (f"`{PREFIX}myvps`", "View VPS"),
                    (f"`{PREFIX}manage`", "Manage VPS"),
                    (f"`{PREFIX}share-user`", "Share VPS"),
                ]
            },
            "vps": {
                "name": "🖥️ VPS", "emoji": "🖥️",
                "commands": [
                    (f"`{PREFIX}myvps`", "List VPS"),
                    (f"`{PREFIX}manage`", "Manage VPS"),
                ]
            },
            "admin": {
                "name": "🛡️ Admin", "emoji": "🛡️",
                "commands": [
                    (f"`{PREFIX}create`", "Create VPS"),
                    (f"`{PREFIX}delete-vps`", "Delete VPS"),
                    (f"`{PREFIX}delete-user`", "Delete User"),
                    (f"`{PREFIX}suspend-vps`", "Suspend VPS"),
                    (f"`{PREFIX}unsuspend-vps`", "Unsuspend VPS"),
                    (f"`{PREFIX}resize-vps`", "Resize VPS"),
                    (f"`{PREFIX}ct-list`", "List Proxmox CTs"),
                    (f"`{PREFIX}serverstats`", "Node Stats"),
                ],
                "admin_only": True
            },
        }
        
        options = []
        for cat_id, cat_data in self.command_categories.items():
            if cat_data.get("admin_only"):
                user_id = str(ctx.author.id)
                if user_id != str(MAIN_ADMIN_ID) and user_id not in admin_data.get("admins", []):
                    continue
            options.append(discord.SelectOption(label=cat_data["name"], value=cat_id, emoji=cat_data["emoji"]))
        
        self.select = discord.ui.Select(placeholder="Select Category", options=options)
        self.select.callback = self.select_callback
        self.add_item(self.select)
        self.current_category = "user"
        self.update_embed()

    async def select_callback(self, interaction: discord.Interaction):
        if str(interaction.user.id) != str(self.ctx.author.id):
             await interaction.response.send_message(embed=create_error_embed("Access Denied", "Not your help session."), ephemeral=True)
             return
        self.current_category = self.select.values[0]
        self.update_embed()
        await interaction.response.edit_message(embed=self.embed, view=self)

    def update_embed(self):
        cat_data = self.command_categories[self.current_category]
        self.embed = discord.Embed(
            title=f"✨ {BOT_NAME} Help • {cat_data['name']}",
            description="Use the dropdown to navigate.",
            color=self.category_colors.get(self.current_category, COLORS['primary'])
        )
        cmd_list = [f"**{c[0]}**\n╰ {c[1]}" for c in cat_data["commands"]]
        self.embed.add_field(name="Commands", value="\n".join(cmd_list), inline=False)
        self.embed.set_thumbnail(url=THUMBNAIL_URL)
        self.embed.set_footer(text=f"⚡ {BOT_NAME}", icon_url=THUMBNAIL_URL)

@bot.command(name='reset-password')
async def reset_password(ctx):
    user_id = str(ctx.author.id)
    await ctx.send(embed=create_error_embed("Unavailable", "Password reset is not available with the current bot configuration (API token restriction). Please contact an administrator."))


@bot.command(name='help')
async def show_help(ctx):
    view = HelpView(ctx)
    await ctx.send(embed=view.embed, view=view)

if __name__ == "__main__":
    if DISCORD_TOKEN:
        bot.run(DISCORD_TOKEN)
    else:
        logger.error("No Discord token found.")
