"""Set advanced operations: symmetric_difference, update, intersection_update,
difference_update, symmetric_difference_update.

Cross-backend equivalence fixture -- Python reference + native implementation.
"""

def set_advanced_py() -> dict {
    # symmetric_difference
    a: set[int] = {1, 2, 3, 4};
    b: set[int] = {3, 4, 5, 6};
    sd: set[int] = a.symmetric_difference(b);
    sd_len: int = len(sd);
    sd_has_1: int = 1 if 1 in sd else 0;
    sd_has_3: int = 1 if 3 in sd else 0;
    sd_has_5: int = 1 if 5 in sd else 0;
    sd_has_6: int = 1 if 6 in sd else 0;

    # update
    c: set[int] = {10, 20};
    d: set[int] = {20, 30, 40};
    c.update(d);
    upd_len: int = len(c);
    upd_has_10: int = 1 if 10 in c else 0;
    upd_has_30: int = 1 if 30 in c else 0;
    upd_has_40: int = 1 if 40 in c else 0;

    # intersection_update
    e: set[int] = {1, 2, 3, 4, 5};
    f: set[int] = {2, 4, 6};
    e.intersection_update(f);
    iupd_len: int = len(e);
    iupd_has_2: int = 1 if 2 in e else 0;
    iupd_has_4: int = 1 if 4 in e else 0;
    iupd_has_1: int = 1 if 1 in e else 0;

    # difference_update
    g: set[int] = {1, 2, 3, 4, 5};
    h: set[int] = {2, 4};
    g.difference_update(h);
    dupd_len: int = len(g);
    dupd_has_1: int = 1 if 1 in g else 0;
    dupd_has_2: int = 1 if 2 in g else 0;
    dupd_has_3: int = 1 if 3 in g else 0;
    dupd_has_5: int = 1 if 5 in g else 0;

    # symmetric_difference_update
    j: set[int] = {1, 2, 3};
    k: set[int] = {2, 3, 4};
    j.symmetric_difference_update(k);
    sdupd_len: int = len(j);
    sdupd_has_1: int = 1 if 1 in j else 0;
    sdupd_has_2: int = 1 if 2 in j else 0;
    sdupd_has_4: int = 1 if 4 in j else 0;

    return {
        "sd_len": sd_len,
        "sd_has_1": sd_has_1,
        "sd_has_3": sd_has_3,
        "sd_has_5": sd_has_5,
        "sd_has_6": sd_has_6,
        "upd_len": upd_len,
        "upd_has_10": upd_has_10,
        "upd_has_30": upd_has_30,
        "upd_has_40": upd_has_40,
        "iupd_len": iupd_len,
        "iupd_has_2": iupd_has_2,
        "iupd_has_4": iupd_has_4,
        "iupd_has_1": iupd_has_1,
        "dupd_len": dupd_len,
        "dupd_has_1": dupd_has_1,
        "dupd_has_2": dupd_has_2,
        "dupd_has_3": dupd_has_3,
        "dupd_has_5": dupd_has_5,
        "sdupd_len": sdupd_len,
        "sdupd_has_1": sdupd_has_1,
        "sdupd_has_2": sdupd_has_2,
        "sdupd_has_4": sdupd_has_4
    };
}

na {
    def set_advanced_na() -> dict[str, any] {
        # symmetric_difference
        a: set[int] = {1, 2, 3, 4};
        b: set[int] = {3, 4, 5, 6};
        sd: set[int] = a.symmetric_difference(b);
        sd_len: int = len(sd);
        sd_has_1: int = 1 if 1 in sd else 0;
        sd_has_3: int = 1 if 3 in sd else 0;
        sd_has_5: int = 1 if 5 in sd else 0;
        sd_has_6: int = 1 if 6 in sd else 0;

        # update
        c: set[int] = {10, 20};
        d: set[int] = {20, 30, 40};
        c.update(d);
        upd_len: int = len(c);
        upd_has_10: int = 1 if 10 in c else 0;
        upd_has_30: int = 1 if 30 in c else 0;
        upd_has_40: int = 1 if 40 in c else 0;

        # intersection_update
        e: set[int] = {1, 2, 3, 4, 5};
        f: set[int] = {2, 4, 6};
        e.intersection_update(f);
        iupd_len: int = len(e);
        iupd_has_2: int = 1 if 2 in e else 0;
        iupd_has_4: int = 1 if 4 in e else 0;
        iupd_has_1: int = 1 if 1 in e else 0;

        # difference_update
        g: set[int] = {1, 2, 3, 4, 5};
        h: set[int] = {2, 4};
        g.difference_update(h);
        dupd_len: int = len(g);
        dupd_has_1: int = 1 if 1 in g else 0;
        dupd_has_2: int = 1 if 2 in g else 0;
        dupd_has_3: int = 1 if 3 in g else 0;
        dupd_has_5: int = 1 if 5 in g else 0;

        # symmetric_difference_update
        j: set[int] = {1, 2, 3};
        k: set[int] = {2, 3, 4};
        j.symmetric_difference_update(k);
        sdupd_len: int = len(j);
        sdupd_has_1: int = 1 if 1 in j else 0;
        sdupd_has_2: int = 1 if 2 in j else 0;
        sdupd_has_4: int = 1 if 4 in j else 0;

        return {
            "sd_len": sd_len,
            "sd_has_1": sd_has_1,
            "sd_has_3": sd_has_3,
            "sd_has_5": sd_has_5,
            "sd_has_6": sd_has_6,
            "upd_len": upd_len,
            "upd_has_10": upd_has_10,
            "upd_has_30": upd_has_30,
            "upd_has_40": upd_has_40,
            "iupd_len": iupd_len,
            "iupd_has_2": iupd_has_2,
            "iupd_has_4": iupd_has_4,
            "iupd_has_1": iupd_has_1,
            "dupd_len": dupd_len,
            "dupd_has_1": dupd_has_1,
            "dupd_has_2": dupd_has_2,
            "dupd_has_3": dupd_has_3,
            "dupd_has_5": dupd_has_5,
            "sdupd_len": sdupd_len,
            "sdupd_has_1": sdupd_has_1,
            "sdupd_has_2": sdupd_has_2,
            "sdupd_has_4": sdupd_has_4
        };
    }
}
