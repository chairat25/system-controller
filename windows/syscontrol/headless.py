"""A scriptable companion without a screen, for testing against the Mac app: pairs with the first computer in its
pairing window, confirms, sends a mascot over and prints every event as one JSON line."""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

from . import protocol
from .service import Service
from .store import Store


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="syscontrol --headless")
    parser.add_argument("--data", type=Path, required=True, help="settings folder for this test companion")
    parser.add_argument("--device-id")
    parser.add_argument("--name", default="Test PC")
    parser.add_argument("--pair", action="store_true", help="open pairing and pair with the first one found")
    parser.add_argument("--send", metavar="SIDE", help="once connected, send a mascot through this edge")
    parser.add_argument("--animal", default="tabby")
    parser.add_argument("--hue", type=float, default=200)
    parser.add_argument("--scale", type=float, default=1.6)
    parser.add_argument("--bounce", action="store_true", help="send every visitor straight back")
    parser.add_argument("--seconds", type=float, default=60)
    args = parser.parse_args(argv)

    args.data.mkdir(parents=True, exist_ok=True)
    settings_file = args.data / "settings.json"
    if not settings_file.exists():
        seed = {"name": args.name, "animal": args.animal, "hue": args.hue, "scale": args.scale}
        if args.device_id:
            seed["device_id"] = args.device_id
        settings_file.write_text(json.dumps(seed))

    def say(kind: str, data: object) -> None:
        if kind == "state":
            data = {"connected": data["connected"], "versions": data["versions"],
                    "nearby": [n.name for n in data["nearby"]], "session": data["session"],
                    "peers": [(p.name, p.id, p.side) for p in data["settings"].peers]}
        elif kind in ("visitor", "returned"):
            visitor, extra = data
            data = {"visitor": visitor.to_wire(), "from": extra}
        print(json.dumps({"t": round(time.time(), 2), "event": kind, "data": data}, default=str), flush=True)

    service = Service(Store(args.data), lambda kind, data: on_event(kind, data))
    sent = False
    confirmed_code = None
    asked = False

    def later(action) -> None:
        """Acts after the event is handled, so a reply never re-enters the service mid-step."""
        service.loop.call_soon(action)

    def on_event(kind: str, data: object) -> None:
        nonlocal sent, confirmed_code, asked
        say(kind, data)
        if kind == "state":
            session = data["session"]
            if args.pair and data["pairing_open"] and session is None and data["nearby"] and not asked:
                asked = True
                later(lambda: service.pair_with(data["nearby"][0].device_id))
            if session and session["state"] == "confirming" and confirmed_code != session["code"]:
                confirmed_code = session["code"]
                later(service.confirm_pairing)
            if args.send and not sent and service.can_hand_off(args.send):
                sent = True
                later(lambda: send_one())
        if kind == "visitor" and args.bounce:
            visitor, peer_id = data
            later(lambda: service.send_back(visitor, peer_id))
            say("bounced", visitor.id)

    def send_one() -> None:
        settings = service.settings
        visitor = protocol.Visitor(id=f"{settings.device_id[:8]}-test0001", direction=args.send,
                                   home=settings.device_id, look=settings.animal, hue=settings.hue,
                                   scale=settings.scale)
        service.hand_off(visitor, args.send)
        say("sent", visitor.to_wire())

    async def run() -> None:
        task = asyncio.ensure_future(service.run())
        service.loop = asyncio.get_running_loop()
        await asyncio.sleep(1)
        if args.pair:
            service.open_pairing()
        await asyncio.sleep(args.seconds)
        service.stop()
        await task

    asyncio.run(run())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
