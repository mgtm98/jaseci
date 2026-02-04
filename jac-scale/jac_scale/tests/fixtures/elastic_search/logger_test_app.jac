"""
Logger Test Application

This tests the ElasticsearchLogger functionality in jac-scale.
It logs various events to verify Elasticsearch integration.
"""

import from jac_scale.factories.utility_factory { UtilityFactory }
import from time { sleep }

glob logger = UtilityFactory.create_configured_logger();

with entry {
    logger.info("Logger test application started", {
        "event": "app_start",
        "version": "test-1.0",
        "test_id": "es_test_001"
    });
    logger.info("Test info log", {
        "event": "test_info",
        "level": "info",
        "test_id": "es_test_001"
    });

    logger.warn("Test warning log", {
        "event": "test_warning",
        "level": "warning",
        "test_id": "es_test_001"
    });

    logger.error("Test error log", {
        "event": "test_error",
        "level": "error",
        "test_id": "es_test_001"
    });
    
    for i in range(5) {
        logger.info(f"Bulk test log {i}", {
            "event": "bulk_test",
            "iteration": i,
            "test_id": "es_test_001"
        });
    }
    logger.close();
    sleep(1);

    print("✅ Logger test application completed - logged 9 events");
}
