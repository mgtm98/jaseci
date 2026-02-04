def a(x: int) -> int | None {
    if x > 0 {
        return x;
    } else {
        return None;
    }
}

with entry {
    print(a(10));
    print(a(-5));
}