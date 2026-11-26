"""How one mascot moves on this screen, in points (pixels divided by the display scale): it strolls along the floor,
rests, turns at an edge with no neighbour, leaves through one that has, flies when thrown. Pure, so it is tested
without a screen. Follows the Mac app's `RoamingWalker` and `MascotFling`."""
from __future__ import annotations

import random
from dataclasses import dataclass, field

from . import sprites

WALK_SPEED = 60.0
GRAVITY = 2600.0
WALL_BOUNCE = 0.5
FLOOR_BOUNCE = 0.35
FLOOR_FRICTION = 0.7
SETTLE_SPEED = 180.0
MAXIMUM_SPEED = 6000.0
FRAMES_PER_SECOND = 10


@dataclass
class Body:
    id: str
    home: str | None
    look: str
    hue: float
    scale: float
    x: float = 0.0
    lift: float = 0.0
    faces_right: bool = True
    mode: str = "rest"  # rest, walk, enter, leave, fly, held
    leaving: str | None = None
    vx: float = 0.0
    vy: float = 0.0
    time_left: float = 2.0
    clock: float = 0.0
    rng: random.Random = field(default_factory=random.Random, repr=False)

    @property
    def side(self) -> float:
        return 80.0 * self.scale

    @property
    def frame(self) -> int:
        if self.mode == "held":
            return sprites.HELD
        if self.mode == "fly":
            return sprites.FALL
        if self.mode in ("walk", "enter", "leave"):
            return int(self.clock * FRAMES_PER_SECOND) % sprites.WALK_FRAMES
        return sprites.REST

    def arrive(self, entry: str, width: float, height: float, flight: dict | None) -> None:
        """Comes in from beside the screen through `entry`, walking or still flying."""
        max_x = max(width - self.side, 0)
        self.x = -self.side if entry == "left" else max_x + self.side
        self.faces_right = entry == "left"
        if flight:
            self.mode = "fly"
            self.lift = flight["liftFraction"] * max(height - self.side, 0)
            self.vx, self.vy = flight["vx"], flight["vy"]
        else:
            self.mode = "enter"

    def throw(self, vx: float, vy: float) -> None:
        self.mode = "fly"
        self.vx = max(min(vx, MAXIMUM_SPEED), -MAXIMUM_SPEED)
        self.vy = max(min(vy, MAXIMUM_SPEED), -MAXIMUM_SPEED)

    def step(self, dt: float, width: float, height: float, can_exit) -> tuple[str, dict | None] | None:
        """Moves `dt` seconds. Returns (edge, flight) when it has fully left through an edge with a neighbour."""
        self.clock += dt
        max_x = max(width - self.side, 0)
        max_lift = max(height - self.side, 0)
        if self.mode == "held":
            return None
        if self.mode == "fly":
            return self._fly(dt, max_x, max_lift, can_exit)
        speed = WALK_SPEED * dt * (1 if self.faces_right else -1)
        if self.mode == "leave":
            self.x += speed
            gone = self.x <= -self.side if self.leaving == "left" else self.x >= max_x + self.side
            return (self.leaving, None) if gone else None
        if self.mode == "enter":
            self.x += speed
            if 0 <= self.x <= max_x:
                self._start("walk")
            return None
        self.time_left -= dt
        if self.mode == "rest":
            if self.time_left <= 0:
                self.faces_right = self.rng.random() < 0.5
                self._start("walk")
            return None
        self.x += speed
        if self.x <= 0 or self.x >= max_x:
            edge = "left" if self.x <= 0 else "right"
            if can_exit(edge):
                self.mode, self.leaving = "leave", edge
            else:
                self.x = min(max(self.x, 0), max_x)
                self.faces_right = not self.faces_right
        elif self.time_left <= 0:
            self._start("rest")
        return None

    def _start(self, mode: str) -> None:
        self.mode = mode
        self.time_left = (4 + self.rng.random() * 8) if mode == "walk" else (2 + self.rng.random() * 5)

    def _fly(self, dt: float, max_x: float, max_lift: float, can_exit) -> tuple[str, dict] | None:
        self.vy -= GRAVITY * dt
        next_x = self.x + self.vx * dt
        self.lift += self.vy * dt
        inside = 0 <= self.x <= max_x
        if next_x < 0 or next_x > max_x:
            edge = "left" if next_x < 0 else "right"
            if can_exit(edge):
                if (next_x <= -self.side) if edge == "left" else (next_x >= max_x + self.side):
                    fraction = min(max(self.lift / max_lift, 0), 1) if max_lift > 0 else 0
                    return edge, {"liftFraction": fraction, "vx": self.vx, "vy": self.vy}
            elif inside or (self.vx < 0 if edge == "left" else self.vx > 0):
                next_x = min(max(next_x, 0), max_x)
                self.vx = -self.vx * WALL_BOUNCE
        self.x = next_x
        if self.lift > max_lift > 0:
            self.lift = max_lift
            self.vy = -abs(self.vy) * WALL_BOUNCE
        if self.lift <= 0:
            self.lift = 0
            in_screen = 0 <= self.x <= max_x
            if abs(self.vy) < SETTLE_SPEED and in_screen:
                self.faces_right = self.vx >= 0
                self.vx = self.vy = 0
                self._start("rest")
                return None
            self.vy = abs(self.vy) * FLOOR_BOUNCE
            if in_screen:
                self.vx *= FLOOR_FRICTION
        return None
