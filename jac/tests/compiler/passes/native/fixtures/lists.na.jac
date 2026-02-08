def list_len_test() -> int {
    items: list[int] = [10, 20, 30];
    return len(items);
}

def list_get_test() -> int {
    items: list[int] = [10, 20, 30];
    return items[1];
}

def list_append_test() -> int {
    items: list[int] = [1, 2, 3];
    items.append(4);
    return len(items);
}

def list_sum() -> int {
    items: list[int] = [10, 20, 30, 40];
    total: int = 0;
    for i in range(len(items)) {
        total = total + items[i];
    }
    return total;
}

def list_set_test() -> int {
    items: list[int] = [1, 2, 3];
    items[1] = 99;
    return items[1];
}

# Test negative indexing (get)
def list_negative_index_get() -> int {
    items: list[int] = [10, 20, 30, 40];
    return items[-1];  # Should return 40
}

def list_negative_index_middle() -> int {
    items: list[int] = [10, 20, 30, 40, 50];
    return items[-3];  # Should return 30
}

# Test negative indexing (set)
def list_negative_index_set() -> int {
    items: list[int] = [10, 20, 30];
    items[-1] = 99;
    return items[2];  # Should return 99
}

# Test pop
def list_pop_test() -> int {
    items: list[int] = [10, 20, 30];
    return items.pop();  # Should return 30
}

def list_pop_len() -> int {
    items: list[int] = [10, 20, 30];
    items.pop();
    return len(items);  # Should return 2
}

# Test clear
def list_clear_test() -> int {
    items: list[int] = [10, 20, 30];
    items.clear();
    return len(items);  # Should return 0
}

# Test insert
def list_insert_start() -> int {
    items: list[int] = [20, 30, 40];
    items.insert(0, 10);
    return items[0];  # Should return 10
}

def list_insert_middle() -> int {
    items: list[int] = [10, 30, 40];
    items.insert(1, 20);
    return items[1];  # Should return 20
}

def list_insert_end() -> int {
    items: list[int] = [10, 20, 30];
    items.insert(3, 40);
    return items[3];  # Should return 40
}

def list_insert_negative() -> int {
    items: list[int] = [10, 30, 40];
    items.insert(-2, 20);
    return items[1];  # Should return 20
}

# Test remove
def list_remove_first() -> int {
    items: list[int] = [10, 20, 30, 20];
    items.remove(20);
    return items[1];  # Should return 30 (first 20 removed)
}

def list_remove_len() -> int {
    items: list[int] = [10, 20, 30];
    items.remove(20);
    return len(items);  # Should return 2
}

# Test float lists
def list_float_sum() -> float {
    values: list[float] = [1.5, 2.5, 3.0];
    total: float = 0.0;
    for i in range(len(values)) {
        total = total + values[i];
    }
    return total;  # Should return 7.0
}

def list_float_append() -> float {
    values: list[float] = [1.0, 2.0];
    values.append(3.5);
    return values[2];  # Should return 3.5
}

# Test empty list
def list_empty_len() -> int {
    items: list[int] = [];
    return len(items);  # Should return 0
}

def list_empty_append() -> int {
    items: list[int] = [];
    items.append(42);
    return items[0];  # Should return 42
}

# Test list growth (capacity expansion)
def list_growth_test() -> int {
    items: list[int] = [];
    for i in range(20) {
        items.append(i);
    }
    return len(items);  # Should return 20
}

def list_growth_values() -> int {
    items: list[int] = [];
    for i in range(15) {
        items.append(i * 2);
    }
    return items[10];  # Should return 20
}

# Test sequential operations
def list_sequential_ops() -> int {
    items: list[int] = [10, 20];
    items.append(30);
    items.insert(1, 15);
    items.remove(20);
    val: int = items.pop();
    items.append(25);
    return items[2];  # [10, 15, 25] -> Should return 25
}

# Test list with multiple same values
def list_duplicate_values() -> int {
    items: list[int] = [5, 5, 5, 5];
    return items[2];  # Should return 5
}

def list_remove_duplicate() -> int {
    items: list[int] = [1, 2, 3, 2, 4];
    items.remove(2);
    # After removing first 2: [1, 3, 2, 4]
    # items[2] should be 2 (not 3)
    return items[1];  # Should return 3
}

# Test lists of objects
obj TestContainer {
    has value: int = 0;
}

def list_objects_create() -> int {
    obj1: TestContainer = TestContainer(value=10);
    obj2: TestContainer = TestContainer(value=20);
    obj3: TestContainer = TestContainer(value=30);
    objects: list[TestContainer] = [obj1, obj2, obj3];
    return len(objects);  # Should return 3
}

def list_objects_get() -> int {
    obj1: TestContainer = TestContainer(value=10);
    obj2: TestContainer = TestContainer(value=20);
    obj3: TestContainer = TestContainer(value=30);
    objects: list[TestContainer] = [obj1, obj2, obj3];
    return objects[1].value;  # Should return 20
}

def list_objects_append() -> int {
    obj1: TestContainer = TestContainer(value=10);
    objects: list[TestContainer] = [obj1];
    obj2: TestContainer = TestContainer(value=20);
    objects.append(obj2);
    return len(objects);  # Should return 2
}

def list_objects_pop() -> int {
    obj1: TestContainer = TestContainer(value=10);
    obj2: TestContainer = TestContainer(value=20);
    objects: list[TestContainer] = [obj1, obj2];
    popped: TestContainer = objects.pop();
    return popped.value;  # Should return 20
}

def list_objects_insert() -> int {
    obj1: TestContainer = TestContainer(value=10);
    obj3: TestContainer = TestContainer(value=30);
    objects: list[TestContainer] = [obj1, obj3];
    obj2: TestContainer = TestContainer(value=20);
    objects.insert(1, obj2);
    return objects[1].value;  # Should return 20
}

# Test nested lists (list of lists)
def list_nested_create() -> int {
    list1: list[int] = [1, 2, 3];
    list2: list[int] = [4, 5, 6];
    list3: list[int] = [7, 8, 9];
    nested: list[list[int]] = [list1, list2, list3];
    return len(nested);  # Should return 3
}

def list_nested_get() -> int {
    list1: list[int] = [1, 2, 3];
    list2: list[int] = [4, 5, 6];
    nested: list[list[int]] = [list1, list2];
    return nested[1][1];  # Should return 5
}

def list_nested_append_inner() -> int {
    list1: list[int] = [1, 2, 3];
    list2: list[int] = [4, 5, 6];
    nested: list[list[int]] = [list1, list2];
    nested[0].append(10);
    return nested[0][3];  # Should return 10
}

def list_nested_append_outer() -> int {
    list1: list[int] = [1, 2, 3];
    nested: list[list[int]] = [list1];
    list2: list[int] = [4, 5, 6];
    nested.append(list2);
    return len(nested);  # Should return 2
}

def list_nested_pop() -> int {
    list1: list[int] = [1, 2, 3];
    list2: list[int] = [4, 5, 6];
    nested: list[list[int]] = [list1, list2];
    popped: list[int] = nested.pop();
    return popped[0];  # Should return 4
}

def list_nested_insert() -> int {
    list1: list[int] = [1, 2, 3];
    list3: list[int] = [7, 8, 9];
    nested: list[list[int]] = [list1, list3];
    list2: list[int] = [4, 5, 6];
    nested.insert(1, list2);
    return nested[1][0];  # Should return 4
}
