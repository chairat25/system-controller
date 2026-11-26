from syscontrol.body import Body


def body(**kwargs) -> Body:
    return Body(id="m", home="H", look="cat", hue=0, scale=1, **kwargs)


def run(mascot: Body, seconds: float, can_exit=lambda edge: False, width=1000, height=700):
    for _ in range(int(seconds * 24)):
        result = mascot.step(1 / 24, width, height, can_exit)
        if result:
            return result
    return None


def test_stays_on_screen_without_neighbours():
    mascot = body(x=500)
    for _ in range(24 * 120):
        assert mascot.step(1 / 24, 1000, 700, lambda edge: False) is None
        assert 0 <= mascot.x <= 1000 - mascot.side


def test_leaves_through_an_edge_with_a_neighbour():
    mascot = body(x=500)
    assert run(mascot, 600, can_exit=lambda edge: edge == "right") == ("right", None)


def test_arrives_walking_in_from_the_edge():
    mascot = body()
    mascot.arrive("left", 1000, 700, None)
    assert mascot.x < 0 and mascot.faces_right
    run(mascot, 3)
    assert mascot.x >= 0 and mascot.mode in ("walk", "rest")


def test_thrown_mascot_lands_or_flies_off():
    mascot = body(x=500, lift=300)
    mascot.throw(200, 400)
    run(mascot, 5)
    assert mascot.mode == "rest" and mascot.lift == 0
    flyer = body(x=900, lift=100)
    flyer.throw(3000, 300)
    edge, flight = run(flyer, 2, can_exit=lambda edge: True)
    assert edge == "right" and 0 <= flight["liftFraction"] <= 1 and flight["vx"] > 0


def test_frames_follow_the_mode():
    mascot = body()
    assert mascot.frame == 8
    mascot.mode = "held"
    assert mascot.frame == 9
    mascot.mode = "fly"
    assert mascot.frame == 10
