"""Function to stream numbers for testing."""
def stream_numbers(count: int = 3) -> Generator {
    import time;
    for i in range(count) {
        time.sleep(0.5);
        yield i;
    }
}

# Define a walker for streaming reports
walker : pub StreamReporter {
    has count: int = 3;

    can report_items with `root entry {
        import time;
        for i in range(self.count) {
            time.sleep(0.5);
            report yield f"Report {i}";
        }
    }
}
