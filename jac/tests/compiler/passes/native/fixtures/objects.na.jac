obj Point {
    has x: int = 0, y: int = 0;

    def get_x() -> int {
        return self.x;
    }

    def get_y() -> int {
        return self.y;
    }

    def sum() -> int {
        return self.x + self.y;
    }
}

obj Counter {
    has count: int = 0;

    def increment() -> None {
        self.count = self.count + 1;
    }

    def get_count() -> int {
        return self.count;
    }
}

def make_point(x: int, y: int) -> Point {
    return Point(x=x, y=y);
}

def point_sum(x: int, y: int) -> int {
    p: Point = Point(x=x, y=y);
    return p.sum();
}

def test_counter() -> int {
    c: Counter = Counter();
    c.increment();
    c.increment();
    c.increment();
    return c.get_count();
}

def test_none() -> int {
    p: Point = Point(x=1, y=2);
    if p is not None {
        return 1;
    }
    return 0;
}

obj SimpleObj {
    has value: int;
    has name: str;

    def init(v: int, n: str) {
        self.value = v;
        self.name = n;
    }

    def get_value() -> int {
        return self.value;
    }
}

def test_init_called() -> int {
    sobj = SimpleObj(42, "hello");
    return sobj.get_value();
}

obj InitCounter {
    has init_count: int;
    has final_value: int;

    def init(val: int) {
        self.init_count = 1;
        self.final_value = val * 2;
    }

    def get_init_count() -> int {
        return self.init_count;
    }

    def get_final_value() -> int {
        return self.final_value;
    }
}

def test_init_executed() -> int {
    iobj = InitCounter(10);
    if iobj.get_init_count() == 1 {
        return iobj.get_final_value();
    }
    return 0;
}
