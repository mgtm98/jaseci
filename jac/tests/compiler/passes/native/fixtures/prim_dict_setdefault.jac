"""Dict setdefault primitive.

Cross-backend equivalence fixture -- Python reference + native implementation.
"""

def dict_setdefault_py() -> dict {
    # setdefault with missing key
    d1: dict[str, int] = {"a": 1, "b": 2};
    sd_missing: int = d1.setdefault("c", 99);
    sd_missing_len: int = len(d1);
    sd_missing_c: int = d1["c"];

    # setdefault with existing key
    d2: dict[str, int] = {"x": 10, "y": 20};
    sd_existing: int = d2.setdefault("x", 999);
    sd_existing_len: int = len(d2);
    sd_existing_x: int = d2["x"];

    # setdefault adding multiple keys
    d3: dict[str, int] = {};
    d3.setdefault("a", 1);
    d3.setdefault("b", 2);
    d3.setdefault("a", 100);  # should not overwrite
    sd_multi_len: int = len(d3);
    sd_multi_a: int = d3["a"];
    sd_multi_b: int = d3["b"];

    return {
        "sd_missing": sd_missing,
        "sd_missing_len": sd_missing_len,
        "sd_missing_c": sd_missing_c,
        "sd_existing": sd_existing,
        "sd_existing_len": sd_existing_len,
        "sd_existing_x": sd_existing_x,
        "sd_multi_len": sd_multi_len,
        "sd_multi_a": sd_multi_a,
        "sd_multi_b": sd_multi_b
    };
}

na {
    def dict_setdefault_na() -> dict[str, any] {
        # setdefault with missing key
        d1: dict[str, int] = {"a": 1, "b": 2};
        sd_missing: int = d1.setdefault("c", 99);
        sd_missing_len: int = len(d1);
        sd_missing_c: int = d1["c"];

        # setdefault with existing key
        d2: dict[str, int] = {"x": 10, "y": 20};
        sd_existing: int = d2.setdefault("x", 999);
        sd_existing_len: int = len(d2);
        sd_existing_x: int = d2["x"];

        # setdefault adding multiple keys
        d3: dict[str, int] = {};
        d3.setdefault("a", 1);
        d3.setdefault("b", 2);
        d3.setdefault("a", 100);  # should not overwrite
        sd_multi_len: int = len(d3);
        sd_multi_a: int = d3["a"];
        sd_multi_b: int = d3["b"];

        return {
            "sd_missing": sd_missing,
            "sd_missing_len": sd_missing_len,
            "sd_missing_c": sd_missing_c,
            "sd_existing": sd_existing,
            "sd_existing_len": sd_existing_len,
            "sd_existing_x": sd_existing_x,
            "sd_multi_len": sd_multi_len,
            "sd_multi_a": sd_multi_a,
            "sd_multi_b": sd_multi_b
        };
    }
}
