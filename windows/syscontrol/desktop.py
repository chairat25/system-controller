"""Desktop mascots on this screen: one small always-on-top window each, drawn from the exported sprites. Runs on
the Tk thread; talks to the LAN service only through `service.call` and its read-only `can_hand_off`."""
from __future__ import annotations

import ctypes
import sys
import time
import tkinter as tk
import uuid

from PIL import ImageTk

from . import protocol, sprites
from .body import Body

TICK_MS = 42
MAXIMUM_VISITORS = 8
DRAG_THRESHOLD = 3
THROW_WINDOW = 0.08
IS_WINDOWS = sys.platform == "win32"


def work_area(root: tk.Tk) -> tuple[int, int, int, int]:
    """Left, top, right, bottom of the main display without the taskbar, in pixels."""
    if IS_WINDOWS:
        rect = (ctypes.c_long * 4)()
        if ctypes.windll.user32.SystemParametersInfoW(0x0030, 0, ctypes.byref(rect), 0):  # SPI_GETWORKAREA
            return rect[0], rect[1], rect[2], rect[3]
    return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight() - 80


def display_scale(root: tk.Tk) -> float:
    if IS_WINDOWS:
        try:
            return ctypes.windll.user32.GetDpiForSystem() / 96
        except (AttributeError, OSError):
            pass
    return 1.0


class MascotWindow:
    def __init__(self, root: tk.Tk, desktop: "Desktop", body: Body) -> None:
        self.body = body
        self.desktop = desktop
        self.window = tk.Toplevel(root)
        self.window.overrideredirect(True)
        self.window.attributes("-topmost", True)
        if IS_WINDOWS:
            key = "#%02x%02x%02x" % sprites.KEY
            self.window.configure(bg=key)
            self.window.attributes("-transparentcolor", key)
            self.label = tk.Label(self.window, bd=0, bg=key, highlightthickness=0)
        else:
            self.window.attributes("-transparent", True)
            self.window.configure(bg="systemTransparent")
            self.label = tk.Label(self.window, bd=0, bg="systemTransparent", highlightthickness=0)
        self.label.pack()
        self.photo = None
        self.shown = None
        self.pressed_at = None
        self.dragging = False
        self.samples: list[tuple[float, int, int]] = []
        self.label.bind("<ButtonPress-1>", self.press)
        self.label.bind("<B1-Motion>", self.motion)
        self.label.bind("<ButtonRelease-1>", self.release)

    def draw(self, origin: tuple[int, int], side: int) -> None:
        body = self.body
        key = (body.look, body.hue, side, body.faces_right, body.frame)
        if key != self.shown:
            frame = sprites.frames(body.look, body.hue, side, body.faces_right, IS_WINDOWS)[body.frame]
            self.photo = ImageTk.PhotoImage(frame)
            self.label.configure(image=self.photo)
            self.shown = key
        self.window.geometry(f"{side}x{side}+{origin[0]}+{origin[1]}")

    def close(self) -> None:
        self.window.destroy()

    # Press and drag to pick it up and throw it; a click makes it hop.
    def press(self, event) -> None:
        self.pressed_at = (event.x_root, event.y_root)
        self.dragging = False
        self.samples = [(time.monotonic(), event.x_root, event.y_root)]

    def motion(self, event) -> None:
        if not self.pressed_at:
            return
        if not self.dragging:
            dx, dy = event.x_root - self.pressed_at[0], event.y_root - self.pressed_at[1]
            if abs(dx) + abs(dy) < DRAG_THRESHOLD:
                return
            self.dragging = True
            self.body.mode = "held"
        now = time.monotonic()
        self.samples = [s for s in self.samples if now - s[0] <= THROW_WINDOW * 2] + [(now, event.x_root, event.y_root)]
        self.desktop.hold(self.body, event.x_root, event.y_root)

    def release(self, event) -> None:
        if not self.dragging:
            self.body.throw(self.body.vx, 420)  # A hop.
            return
        now = time.monotonic()
        first = next((s for s in self.samples if now - s[0] <= THROW_WINDOW), (now, event.x_root, event.y_root))
        span = max(now - first[0], 1 / 120)
        scale = self.desktop.scale
        self.body.throw((event.x_root - first[1]) / span / scale, -(event.y_root - first[2]) / span / scale)
        self.dragging = False
        self.pressed_at = None


class Desktop:
    def __init__(self, root: tk.Tk, service) -> None:
        self.root = root
        self.service = service
        self.scale = display_scale(root)
        self.windows: dict[str, MascotWindow] = {}
        self.away: dict[str, str] = {}  # own mascot id -> edge it left through
        self.last = time.monotonic()
        self.root.after(TICK_MS, self.tick)

    @property
    def settings(self):
        return self.service.settings

    def area(self) -> tuple[int, int, float, float]:
        left, top, right, bottom = work_area(self.root)
        return left, bottom, (right - left) / self.scale, (bottom - top) / self.scale

    def own(self) -> list[MascotWindow]:
        return [w for w in self.windows.values() if w.body.home == self.settings.device_id]

    def reconcile(self) -> None:
        """Brings this PC's own mascots to the chosen number and look."""
        settings = self.settings
        own = self.own()
        for window in own:
            window.body.look, window.body.hue, window.body.scale = settings.animal, settings.hue, settings.scale
        missing = settings.count - len(own) - len(self.away)
        for _ in range(max(missing, 0)):
            self.spawn()
        for window in own[settings.count:] if missing < 0 else []:
            if window.body.mode != "held":
                self.remove(window.body.id)

    def spawn(self) -> None:
        settings = self.settings
        _, _, width, _ = self.area()
        body = Body(id=f"{settings.device_id[:8]}-{uuid.uuid4().hex[:8].upper()}", home=settings.device_id,
                    look=settings.animal, hue=settings.hue, scale=settings.scale)
        body.x = body.rng.random() * max(width - body.side, 0)
        self.windows[body.id] = MascotWindow(self.root, self, body)

    def remove(self, mascot_id: str) -> None:
        window = self.windows.pop(mascot_id, None)
        if window:
            window.close()

    def receive(self, visitor: protocol.Visitor, peer_id: str) -> None:
        visitors = [w for w in self.windows.values() if w.body.home != self.settings.device_id]
        if visitor.id in self.windows:
            return
        if visitor.home != self.settings.device_id and len(visitors) >= MAXIMUM_VISITORS:
            self.service.call("send_back", visitor, peer_id)
            return
        self.place(visitor)

    def returned(self, visitor: protocol.Visitor, edge: str) -> None:
        if visitor.id in self.windows:
            return
        back = protocol.Visitor(id=visitor.id, direction="right" if edge == "left" else "left", home=visitor.home,
                                look=visitor.look, hue=visitor.hue, scale=visitor.scale)
        self.place(back)

    def place(self, visitor: protocol.Visitor) -> None:
        self.away.pop(visitor.id, None)
        is_own = visitor.home == self.settings.device_id
        settings = self.settings
        body = Body(id=visitor.id, home=visitor.home, look=settings.animal if is_own else visitor.look,
                    hue=settings.hue if is_own else (visitor.hue or 0),
                    scale=settings.scale if is_own else (visitor.scale or 1))
        _, _, width, height = self.area()
        body.arrive(visitor.entry_edge, width, height, visitor.flight)
        self.windows[body.id] = MascotWindow(self.root, self, body)
        self.reconcile()

    def peer_left(self, peer_id: str) -> None:
        """Its visitors go home with it; this PC's own mascots over there are lost and are born again here."""
        for window in [w for w in self.windows.values() if w.body.home == peer_id and w.body.mode != "held"]:
            self.remove(window.body.id)
        self.away = {mascot: edge for mascot, edge in self.away.items() if self.service.can_hand_off(edge)}
        self.reconcile()

    def hold(self, body: Body, x_root: int, y_root: int) -> None:
        left, bottom, width, height = self.area()
        body.x = min(max((x_root - left) / self.scale - body.side / 2, 0), width - body.side)
        body.lift = min(max((bottom - y_root) / self.scale - body.side / 2, 0), height - body.side)

    def tick(self) -> None:
        now = time.monotonic()
        dt = min(now - self.last, 0.25)
        self.last = now
        left, bottom, width, height = self.area()
        if len(self.own()) + len(self.away) < self.settings.count:
            self.reconcile()
        for window in list(self.windows.values()):
            body = window.body
            gone = body.step(dt, width, height, self.can_exit)
            if gone:
                self.hand_off(window, *gone)
                continue
            side = round(body.side * self.scale)
            window.draw((round(left + body.x * self.scale), round(bottom - body.lift * self.scale) - side), side)
        self.root.after(TICK_MS, self.tick)

    def can_exit(self, edge: str) -> bool:
        return self.settings.roaming and self.service.can_hand_off(edge)

    def hand_off(self, window: MascotWindow, edge: str, flight: dict | None) -> None:
        body = window.body
        self.remove(body.id)
        if body.home == self.settings.device_id:
            self.away[body.id] = edge
        visitor = protocol.Visitor(id=body.id, direction=edge, home=body.home, look=body.look, hue=body.hue,
                                   scale=body.scale, flight=flight)
        self.service.call("hand_off", visitor, edge)

    def stop(self) -> None:
        for mascot_id in list(self.windows):
            self.remove(mascot_id)
