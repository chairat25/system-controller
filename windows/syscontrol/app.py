"""The window: this PC's mascot, the paired computers and pairing. Closing it quits the companion."""
from __future__ import annotations

import ctypes
import logging
import queue
import sys
import tkinter as tk
from tkinter import ttk

from . import APP_VERSION, protocol
from .desktop import Desktop
from .service import Service
from .store import Store

POLL_MS = 50
SIDES = {"Left": "left", "Not beside": None, "Right": "right"}
ANIMAL_TITLES = {"cat": "Cat", "pig": "Pig", "puppy": "Puppy", "bunny": "Bunny", "panda": "Panda",
                 "penguin": "Penguin", "hippo": "Hippo", "tabby": "Ginger Cat"}


class App:
    def __init__(self) -> None:
        self.events: queue.Queue = queue.Queue()
        self.service = Service(Store(), lambda kind, data: self.events.put((kind, data)))
        self.root = tk.Tk()
        self.root.title("System Controller for Windows")
        self.root.minsize(420, 360)
        self.root.protocol("WM_DELETE_WINDOW", self.quit)
        self.state: dict | None = None
        self._build()
        self.service.run_in_thread()
        self.desktop = Desktop(self.root, self.service)
        self.root.after(POLL_MS, self.poll)

    # ---- layout --------------------------------------------------------------------------------------------

    def _build(self) -> None:
        settings = self.service.settings
        outer = ttk.Frame(self.root, padding=16)
        outer.pack(fill="both", expand=True)

        mascot = ttk.LabelFrame(outer, text="Your mascot", padding=12)
        mascot.pack(fill="x")
        self.animal = tk.StringVar(value=ANIMAL_TITLES[settings.animal])
        self.hue = tk.DoubleVar(value=settings.hue)
        self.size = tk.DoubleVar(value=settings.scale)
        self.count = tk.IntVar(value=settings.count)
        self.roaming = tk.BooleanVar(value=settings.roaming)
        rows = [("Animal", ttk.Combobox(mascot, textvariable=self.animal, state="readonly",
                                        values=list(ANIMAL_TITLES.values()))),
                ("Colour", ttk.Scale(mascot, from_=0, to=359, variable=self.hue)),
                ("Size", ttk.Scale(mascot, from_=0.75, to=2.0, variable=self.size)),
                ("How many", ttk.Spinbox(mascot, from_=1, to=6, textvariable=self.count, width=4))]
        for index, (title, widget) in enumerate(rows):
            ttk.Label(mascot, text=title).grid(row=index, column=0, sticky="w", pady=3)
            widget.grid(row=index, column=1, sticky="ew", padx=(12, 0), pady=3)
        mascot.columnconfigure(1, weight=1)
        ttk.Checkbutton(mascot, text="Walks across to paired computers", variable=self.roaming,
                        command=self._apply).grid(row=len(rows), column=0, columnspan=2, sticky="w", pady=(6, 0))
        rows[0][1].bind("<<ComboboxSelected>>", lambda _: self._apply())
        for _, widget in rows[1:]:
            widget.bind("<ButtonRelease-1>", lambda _: self._apply())
        rows[3][1].configure(command=self._apply)

        self.peers = ttk.LabelFrame(outer, text="Paired computers", padding=12)
        self.peers.pack(fill="x", pady=(14, 0))
        self.pairing = ttk.LabelFrame(outer, text="Pair with a Mac", padding=12)
        self.pairing.pack(fill="x", pady=(14, 0))
        ttk.Label(outer, text=f"Version {APP_VERSION} · {settings.name}", foreground="gray").pack(anchor="w", pady=(10, 0))

    def _apply(self) -> None:
        animal = next((key for key, title in ANIMAL_TITLES.items() if title == self.animal.get()), "cat")
        try:
            count = min(max(int(self.count.get()), 1), 6)
        except (tk.TclError, ValueError):
            count = 1
        self.service.call("update", {"animal": animal, "hue": round(self.hue.get()) % 360,
                                     "scale": round(min(max(self.size.get(), 0.75), 2.0), 2), "count": count,
                                     "roaming": self.roaming.get()})
        self.root.after(200, self.desktop.reconcile)

    def _clear(self, frame: ttk.Frame) -> None:
        for child in frame.winfo_children():
            child.destroy()

    def _render_peers(self) -> None:
        self._clear(self.peers)
        state = self.state
        peers = state["settings"].peers
        if not peers:
            ttk.Label(self.peers, text="None yet. Pair with a Mac below.", foreground="gray").pack(anchor="w")
            return
        for row, peer in enumerate(peers):
            connected = peer.id in state["connected"]
            version = state["versions"].get(peer.id)
            status = "Connected" if connected else "Not nearby"
            if connected and version and version[0] is None:
                status += " · update the Mac app to 1.7 or later"
            frame = ttk.Frame(self.peers)
            frame.pack(fill="x", pady=2)
            ttk.Label(frame, text=("● " if connected else "○ ") + peer.name).pack(side="left")
            ttk.Label(frame, text=status, foreground="gray").pack(side="left", padx=8)
            ttk.Button(frame, text="Unpair", command=lambda pid=peer.id: self.service.call("unpair", pid)).pack(side="right")
            side = tk.StringVar(value=next(t for t, v in SIDES.items() if v == peer.side))
            box = ttk.Combobox(frame, textvariable=side, state="readonly", values=list(SIDES), width=10)
            box.pack(side="right", padx=6)
            box.bind("<<ComboboxSelected>>",
                     lambda _, pid=peer.id, var=side: self.service.call("set_side", pid, SIDES[var.get()]))
        ttk.Label(self.peers, text="Side: the edge of this screen the Mac is beyond. Mascots walk off that edge to it.",
                  foreground="gray", wraplength=380).pack(anchor="w", pady=(6, 0))

    def _render_pairing(self) -> None:
        self._clear(self.pairing)
        state = self.state
        session = state["session"]
        if session and session["state"] == "confirming":
            ttk.Label(self.pairing, text=f"Does {session['peer']} show the same code?").pack(anchor="w")
            code = session["code"] or ""
            ttk.Label(self.pairing, text=f"{code[:3]} {code[3:]}", font=("Consolas", 28, "bold")).pack(anchor="w", pady=6)
            buttons = ttk.Frame(self.pairing)
            buttons.pack(anchor="w")
            ttk.Button(buttons, text="Confirm", command=lambda: self.service.call("confirm_pairing")).pack(side="left")
            ttk.Button(buttons, text="Cancel", command=lambda: self.service.call("cancel_pairing")).pack(side="left", padx=6)
            ttk.Label(self.pairing, text="Click Confirm on both computers only if the codes match.",
                      foreground="gray").pack(anchor="w", pady=(6, 0))
        elif session and session["state"] == "failed":
            ttk.Label(self.pairing, text=session["failure"] or "Pairing failed.", foreground="#c60").pack(anchor="w")
            ttk.Button(self.pairing, text="Try again", command=lambda: self.service.call("cancel_pairing")).pack(anchor="w", pady=4)
        elif session:
            ttk.Label(self.pairing, text=f"Pairing with {session['peer'] or 'a Mac'}…").pack(anchor="w")
        elif state["pairing_open"]:
            ttk.Label(self.pairing, text="Looking for Macs… On the Mac open Settings → Sync → Pair, "
                                         "then pick it here (or pick this PC there).",
                      wraplength=380).pack(anchor="w")
            for found in state["nearby"]:
                row = ttk.Frame(self.pairing)
                row.pack(fill="x", pady=2)
                ttk.Label(row, text=found.name).pack(side="left")
                ttk.Button(row, text="Pair", command=lambda d=found.device_id: self.service.call("pair_with", d)).pack(side="right")
            ttk.Button(self.pairing, text="Stop", command=lambda: self.service.call("close_pairing")).pack(anchor="w", pady=(6, 0))
        else:
            ttk.Button(self.pairing, text="Pair with a Mac…", command=lambda: self.service.call("open_pairing")).pack(anchor="w")
            ttk.Label(self.pairing, text="Both computers must be on the same network. Windows may ask to allow "
                                         "network access: allow Private networks.", foreground="gray",
                      wraplength=380).pack(anchor="w", pady=(6, 0))

    # ---- events --------------------------------------------------------------------------------------------

    def poll(self) -> None:
        changed = False
        while True:
            try:
                kind, data = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "state":
                changed = changed or data != self.state
                self.state = data
            elif kind == "visitor":
                self.desktop.receive(*data)
            elif kind == "returned":
                self.desktop.returned(*data)
            elif kind == "peer_left":
                self.desktop.peer_left(data)
        if changed and self.state:
            self._render_peers()
            self._render_pairing()
        self.root.after(POLL_MS, self.poll)

    def quit(self) -> None:
        self.service.call("stop")
        self.desktop.stop()
        self.root.destroy()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    # zeroconf logs every unreachable interface (VPNs, sleeping adapters) as an error; they do not matter here.
    logging.getLogger("zeroconf").setLevel(logging.CRITICAL)
    if sys.platform == "win32":
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)
        except (AttributeError, OSError):
            pass
    App().root.mainloop()
    return 0
